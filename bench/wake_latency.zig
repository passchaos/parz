//! Measure background-worker wake latency after a controlled idle interval.
//!
//! The caller records a timestamp, forks one future per background lane,
//! kickstarts them, and each handler records the delay from kickstart to
//! handler entry. Samples that the caller had to execute itself are counted
//! separately so wake-latency medians only describe real background wake-ups.

const std = @import("std");
const parz = @import("parz");
const affinity = @import("affinity.zig");

const Sample = struct {
    id: u64,
    start_ns: std.atomic.Value(i64) = .init(0),
    latency_ns: std.atomic.Value(i64) = .init(-1),
    worker_index: std.atomic.Value(usize) = .init(std.math.maxInt(usize)),
    background: std.atomic.Value(bool) = .init(false),
};

fn run(t: *parz.Task(void), sample: *Sample) u64 {
    const io = t.worker.pool.io;
    const now = std.Io.Clock.Timestamp.now(io, .awake).raw.toNanoseconds();
    const start = sample.start_ns.load(.acquire);
    sample.latency_ns.store(@intCast(@max(now - start, 0)), .release);
    sample.worker_index.store(t.worker.index, .release);
    sample.background.store(t.worker.index < t.worker.pool.spawned_background, .release);
    return sample.id;
}

fn nowNs(io: std.Io) i64 {
    return @intCast(std.Io.Clock.Timestamp.now(io, .awake).raw.toNanoseconds());
}

fn median(values: []i64) i64 {
    std.mem.sort(i64, values, {}, std.sort.asc(i64));
    return if (values.len == 0) 0 else values[values.len / 2];
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const lanes = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 8;
    const caller_cpu = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 31;
    const idle_ms = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 100;
    const rounds = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 21;
    const heartbeat_cpu = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else null;
    if (lanes == 0 or rounds == 0) return error.InvalidArguments;

    const workers = if (lanes > 1) lanes - 1 else 0;
    var pool = try parz.Pool(void).init(init.gpa, init.io, .{
        .workers = workers,
        .max_workers = if (lanes == 1) 0 else 64,
        .max_callers = 1,
        .pin_workers = true,
    });
    defer pool.deinit();
    try pool.start();
    try affinity.pinCaller(&pool, caller_cpu);
    if (heartbeat_cpu) |cpu| try affinity.pinHeartbeat(&pool, cpu);

    var all: std.ArrayList(i64) = .empty;
    defer all.deinit(init.gpa);
    var fallbacks: usize = 0;
    var samples: [64]Sample = undefined;

    for (0..rounds) |round| {
        try init.io.sleep(std.Io.Duration.fromNanoseconds(@as(i96, idle_ms) * std.time.ns_per_ms), .awake);
        const caller = pool.claimFlatCaller() orelse return error.NoCallerSlot;
        defer pool.releaseCaller(caller);
        const count = @min(workers, samples.len);
        if (count == 0) return error.NoBackgroundWorkers;

        const F = parz.Future(void, *Sample, u64);
        var futures: [64]F = undefined;
        for (samples[0..count], 0..) |*sample, index| {
            sample.* = .{ .id = index };
        }
        var task = caller.beginFlat();
        for (futures[0..count], 0..) |*future, index| {
            future.initFork(&task, run, &samples[index]);
        }
        const start = nowNs(init.io);
        for (samples[0..count]) |*sample| sample.start_ns.store(start, .release);
        pool.kickstart(caller, count);
        // Give background lanes time to pick their jobs up before the caller
        // joins. The handler timestamps still measure kickstart-to-entry; this
        // sleep only prevents the caller from reclaiming unclaimed jobs.
        try init.io.sleep(std.Io.Duration.fromNanoseconds(std.time.ns_per_ms), .awake);
        for (futures[0..count]) |*future| _ = future.joinOrCall(&task, run);

        var latencies: [64]i64 = undefined;
        var valid: usize = 0;
        for (samples[0..count]) |*sample| {
            if (!sample.background.load(.acquire)) {
                fallbacks += 1;
                continue;
            }
            const latency = sample.latency_ns.load(.acquire);
            if (latency >= 0) {
                latencies[valid] = latency;
                valid += 1;
            }
        }
        try all.appendSlice(init.gpa, latencies[0..valid]);
        if (valid != 0) {
            std.mem.sort(i64, latencies[0..valid], {}, std.sort.asc(i64));
            std.debug.print(
                "wake round={d} lanes={d} min_ns={d} median_ns={d} p95_ns={d} max_ns={d} fallback={d}\n",
                .{
                    round,
                    valid,
                    latencies[0],
                    latencies[valid / 2],
                    latencies[@min(valid - 1, (valid * 95) / 100)],
                    latencies[valid - 1],
                    count - valid,
                },
            );
        } else {
            std.debug.print("wake round={d} lanes=0 fallback={d}\n", .{ round, count });
        }
    }

    if (all.items.len != 0) {
        std.mem.sort(i64, all.items, {}, std.sort.asc(i64));
        std.debug.print(
            "wake_latency lanes={d} workers={d} caller_cpu={d} idle_ms={d} rounds={d} samples={d} fallbacks={d} min_ns={d} median_ns={d} p95_ns={d} max_ns={d} statistic=median\n",
            .{
                lanes,
                pool.spawned_background,
                caller_cpu,
                idle_ms,
                rounds,
                all.items.len,
                fallbacks,
                all.items[0],
                median(all.items),
                all.items[@min(all.items.len - 1, (all.items.len * 95) / 100)],
                all.items[all.items.len - 1],
            },
        );
    } else {
        std.debug.print("wake_latency lanes={d} workers={d} samples=0 fallbacks={d}\n", .{
            lanes,
            pool.spawned_background,
            fallbacks,
        });
    }
}
