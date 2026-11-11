//! Fixed-core concurrent callers: checked throughput and per-call latency.
const std = @import("std");
const parz = @import("parz");
const timing = @import("timing.zig");

const max_callers = 8;
const Seed = struct { caller: usize, call: usize };

fn pin(cpu: usize) !void {
    var set = std.mem.zeroes(std.os.linux.cpu_set_t);
    if (cpu >= set.len * @bitSizeOf(usize)) return error.InvalidCpu;
    set[cpu / @bitSizeOf(usize)] = @as(usize, 1) << @intCast(cpu % @bitSizeOf(usize));
    try std.os.linux.sched_setaffinity(0, &set);
}

fn work(seed: Seed, index: usize) u64 {
    var x = @as(u64, @intCast(index)) +% (@as(u64, @intCast(seed.caller)) *% 0x9e3779b97f4a7c15) +% seed.call;
    for (0..64) |_| {
        x = x *% 6364136223846793005 +% 1442695040888963407;
        x ^= x >> 17;
    }
    return x;
}

fn serialCall(seed: Seed, count: usize) u64 {
    var sum: u64 = 0;
    for (0..count) |index| sum +%= work(seed, index);
    return sum;
}

const Run = struct {
    pool: *parz.Pool(void),
    io: std.Io,
    count: usize,
    iterations: usize,
    cpus: []const usize,
    expected: []const u64,
    latencies: []i96,
    latency_batch: usize = 0,
    callers: usize,

    fn map(_: *parz.Worker(void), seed: Seed, index: usize) u64 {
        return work(seed, index);
    }
    fn add(a: u64, b: u64) u64 {
        return a +% b;
    }

    fn serial(self: *@This()) !u64 {
        var sum: u64 = 0;
        for (0..self.callers) |caller| for (0..self.iterations) |call| {
            std.mem.doNotOptimizeAway(self);
            const result = serialCall(.{ .caller = caller, .call = call }, self.count);
            if (result != self.expected[caller * self.iterations + call]) return error.ChecksumMismatch;
            sum +%= result;
        };
        return sum;
    }

    fn parallel(self: *@This()) !u64 {
        const State = struct {
            run: *Run,
            latencies: []i96,
            ready: std.atomic.Value(usize) = .init(0),
            start: std.atomic.Value(bool) = .init(false),
            stop: std.atomic.Value(bool) = .init(false),
            failed: std.atomic.Value(bool) = .init(false),
            sums: [max_callers]u64 = @splat(0),

            fn caller(shared: *@This(), index: usize) void {
                pin(shared.run.cpus[index]) catch {
                    shared.failed.store(true, .release);
                    _ = shared.ready.fetchAdd(1, .release);
                    return;
                };
                _ = shared.ready.fetchAdd(1, .release);
                while (!shared.start.load(.acquire)) std.atomic.spinLoopHint();
                if (shared.stop.load(.acquire)) return;
                var sum: u64 = 0;
                for (0..shared.run.iterations) |call| {
                    const begin = std.Io.Clock.Timestamp.now(shared.run.io, .awake);
                    const result = parz.parallelFoldInfallible(shared.run.pool, u64, Seed{ .caller = index, .call = call }, shared.run.count, .{ .serial_threshold = 0, .chunks_per_worker = 8, .max_chunks = 64 }, 0, map, add) catch {
                        shared.failed.store(true, .release);
                        return;
                    };
                    const offset = index * shared.run.iterations + call;
                    shared.latencies[offset] = begin.untilNow(shared.run.io).raw.toNanoseconds();
                    if (result != shared.run.expected[offset]) {
                        shared.failed.store(true, .release);
                        return;
                    }
                    sum +%= result;
                }
                shared.sums[index] = sum;
            }
        };
        const batch_size = self.callers * self.iterations;
        const offset = self.latency_batch * batch_size;
        self.latency_batch += 1;
        var state = State{ .run = self, .latencies = self.latencies[offset..][0..batch_size] };
        var threads: [max_callers]std.Thread = undefined;
        var spawned: usize = 0;
        defer for (threads[0..spawned]) |thread| thread.join();
        errdefer {
            state.stop.store(true, .release);
            state.start.store(true, .release);
        }
        for (threads[0..self.callers], 0..) |*thread, index| {
            thread.* = try std.Thread.spawn(.{}, State.caller, .{ &state, index });
            spawned += 1;
        }
        while (state.ready.load(.acquire) != self.callers) std.atomic.spinLoopHint();
        state.start.store(true, .release);
        for (threads[0..spawned]) |thread| thread.join();
        spawned = 0;
        if (state.failed.load(.acquire)) return error.CallerFailed;
        var sum: u64 = 0;
        for (state.sums[0..self.callers]) |value| sum +%= value;
        return sum;
    }
};

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const callers = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 4;
    const count = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 4096;
    const iterations = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 8;
    const cpu_arg = args.next() orelse "24,25,26,27,28,29,30,31";
    const rounds = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 9;
    const fair = if (args.next()) |a| std.mem.eql(u8, a, "fair") else false;
    var cpus = std.ArrayList(usize).empty;
    defer cpus.deinit(init.gpa);
    var parts = std.mem.splitScalar(u8, cpu_arg, ',');
    const allowed = try std.posix.sched_getaffinity(0);
    while (parts.next()) |part| {
        const cpu = try std.fmt.parseInt(usize, part, 10);
        if (cpu >= allowed.len * @bitSizeOf(usize) or
            allowed[cpu / @bitSizeOf(usize)] & (@as(usize, 1) << @intCast(cpu % @bitSizeOf(usize))) == 0 or
            std.mem.indexOfScalar(usize, cpus.items, cpu) != null) return error.InvalidCpu;
        try cpus.append(init.gpa, cpu);
    }
    if (callers == 0 or callers > max_callers or callers > cpus.items.len or count == 0 or iterations == 0 or rounds == 0) return error.InvalidArguments;
    const backgrounds = cpus.items.len - callers;
    var options = parz.Options(void){
        .workers = backgrounds,
        .max_workers = backgrounds,
        .max_callers = callers,
        .enable_heartbeat = false,
        .pin_workers = true,
    };
    if (comptime @hasField(parz.Options(void), "fair_shared_owners")) options.fair_shared_owners = fair;
    var pool = try parz.Pool(void).init(init.gpa, init.io, options);
    defer pool.deinit();
    try pool.start();
    if (pool.spawned_background != backgrounds) return error.WorkerSpawnFailed;
    for (pool.pinned_cpus[0..backgrounds], cpus.items[0..backgrounds]) |actual, expected| {
        if (actual != expected) return error.WorkerPlacementMismatch;
    }
    try pin(cpus.items[cpus.items.len - 1]);
    const calls = try std.math.mul(usize, callers, iterations);
    const expected = try init.gpa.alloc(u64, calls);
    defer init.gpa.free(expected);
    var checksum: u64 = 0;
    for (expected, 0..) |*value, index| {
        value.* = serialCall(.{ .caller = index / iterations, .call = index % iterations }, count);
        checksum +%= value.*;
    }
    const latencies = try init.gpa.alloc(i96, try std.math.mul(usize, calls, rounds + 1));
    defer init.gpa.free(latencies);
    var run = Run{ .pool = &pool, .io = init.io, .count = count, .iterations = iterations, .cpus = cpus.items[backgrounds..], .expected = expected, .latencies = latencies, .callers = callers };
    const times = try timing.paired(u64, init.gpa, init.io, rounds, checksum, &run, Run.serial, Run.parallel);
    // Exclude the warm-up group, and retain all timed per-call observations.
    const samples = latencies[calls..];
    std.mem.sort(i96, samples, {}, std.sort.asc(i96));
    std.debug.print("multi-caller callers={d} backgrounds={d} count={d} iterations={d} cpus={any} checksum={d} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median p50_ns={d} p95_ns={d} max_ns={d}\n", .{
        callers,           backgrounds,     count,                    iterations,                      cpus.items,               checksum, times.serial_ns,
        times.parallel_ns, times.speedup(), samples[samples.len / 2], samples[samples.len * 95 / 100], samples[samples.len - 1],
    });
}
