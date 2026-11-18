//! Decompose a cold flat fold into caller-slot claim, dispatch/work and release.
//!
//! The dispatch phase uses the borrowed-worker API so it contains only chunk
//! planning, future/kickstart/join and the callback work. Comparing the three
//! phases shows whether a cold regression sits in the pool mutex, the worker
//! wake path or the caller itself.

const std = @import("std");
const parz = @import("parz");
const affinity = @import("affinity.zig");

fn nowNs(io: std.Io) i64 {
    return @intCast(std.Io.Clock.Timestamp.now(io, .awake).raw.toNanoseconds());
}

fn work(value: u64, comptime heavy: bool) u64 {
    if (!heavy) return value;
    var x = value +% 0x9e3779b97f4a7c15;
    for (0..64) |_| {
        x = x *% 6364136223846793005 +% 1442695040888963407;
        x ^= x >> 17;
    }
    return x;
}

fn scanMap(_: *parz.Worker(void), values: []const u64, index: usize) u64 {
    return work(values[index], false);
}

fn heavyMap(_: *parz.Worker(void), values: []const u64, index: usize) u64 {
    return work(values[index], true);
}

fn add(a: u64, b: u64) u64 {
    return a +% b;
}

fn median(values: []i64) i64 {
    std.mem.sort(i64, values, {}, std.sort.asc(i64));
    return if (values.len == 0) 0 else values[values.len / 2];
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const kind = args.next() orelse "scan";
    const count = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 65536;
    const lanes = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 8;
    const caller_cpu = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 31;
    const idle_ms = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 100;
    const rounds = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 21;
    const heartbeat_cpu = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else null;
    if (count == 0 or lanes == 0 or rounds == 0) return error.InvalidArguments;
    const heavy = std.mem.eql(u8, kind, "compute");
    if (!heavy and !std.mem.eql(u8, kind, "scan")) return error.InvalidArguments;

    const data = try init.gpa.alloc(u64, count);
    defer init.gpa.free(data);
    for (data, 0..) |*value, index| value.* = @intCast(index);

    var pool = try parz.Pool(void).init(init.gpa, init.io, .{
        .workers = if (lanes > 1) lanes - 1 else 0,
        .max_workers = if (lanes == 1) 0 else 64,
        .max_callers = 1,
        .pin_workers = true,
    });
    defer pool.deinit();
    try pool.start();
    try affinity.pinCaller(&pool, caller_cpu);
    if (heartbeat_cpu) |cpu| try affinity.pinHeartbeat(&pool, cpu);

    const options = parz.ParallelOptions{ .chunks_per_worker = 16 };
    const expected = if (heavy) blk: {
        var total: u64 = 0;
        for (data) |value| total +%= work(value, true);
        break :blk total;
    } else @as(u64, @truncate(@as(u128, count) * (count - 1) / 2));

    var claim_samples = try init.gpa.alloc(i64, rounds);
    defer init.gpa.free(claim_samples);
    var dispatch_samples = try init.gpa.alloc(i64, rounds);
    defer init.gpa.free(dispatch_samples);
    var release_samples = try init.gpa.alloc(i64, rounds);
    defer init.gpa.free(release_samples);
    var total_samples = try init.gpa.alloc(i64, rounds);
    defer init.gpa.free(total_samples);

    for (0..rounds) |round| {
        try init.io.sleep(std.Io.Duration.fromNanoseconds(@as(i96, idle_ms) * std.time.ns_per_ms), .awake);
        const total_start = nowNs(init.io);
        const claim_start = total_start;
        const caller = pool.claimFlatCaller() orelse return error.NoCallerSlot;
        const claim_end = nowNs(init.io);
        const dispatch_start = claim_end;
        const result = if (heavy)
            try parz.parallelFoldInfallible(caller, u64, data, data.len, options, 0, heavyMap, add)
        else
            try parz.parallelFoldInfallible(caller, u64, data, data.len, options, 0, scanMap, add);
        const dispatch_end = nowNs(init.io);
        if (result != expected) return error.ChecksumMismatch;
        pool.releaseCaller(caller);
        const release_end = nowNs(init.io);
        claim_samples[round] = claim_end - claim_start;
        dispatch_samples[round] = dispatch_end - dispatch_start;
        release_samples[round] = release_end - dispatch_end;
        total_samples[round] = release_end - total_start;
        std.debug.print(
            "cold_phase round={d} kind={s} count={d} lanes={d} claim_ns={d} dispatch_ns={d} release_ns={d} total_ns={d}\n",
            .{
                round,
                kind,
                count,
                pool.parallelWorkerCount(),
                claim_samples[round],
                dispatch_samples[round],
                release_samples[round],
                total_samples[round],
            },
        );
    }

    std.debug.print(
        "cold_phases kind={s} count={d} lanes={d} caller_cpu={d} idle_ms={d} rounds={d} claim_ns={d} dispatch_ns={d} release_ns={d} total_ns={d} statistic=median\n",
        .{
            kind,
            count,
            pool.parallelWorkerCount(),
            caller_cpu,
            idle_ms,
            rounds,
            median(claim_samples),
            median(dispatch_samples),
            median(release_samples),
            median(total_samples),
        },
    );
}
