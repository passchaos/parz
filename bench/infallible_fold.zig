//! Fixed-CPU infallible folds, with per-call dispatch allocation accounting.
const std = @import("std");
const parz = @import("parz");
const affinity = @import("affinity.zig");
const timing = @import("timing.zig");

fn work(comptime heavy: bool, value: u64) u64 {
    if (!heavy) return value;
    var x = value +% 0x9e3779b97f4a7c15;
    for (0..64) |_| {
        x = x *% 6364136223846793005 +% 1442695040888963407;
        x ^= x >> 17;
    }
    return x;
}

fn serial(comptime heavy: bool, data: []const u64) align(64) u64 {
    var total: u64 = 0;
    for (data) |value| total +%= work(heavy, value);
    return total;
}

const Config = struct {
    count: usize,
    lanes: usize,
    cpu: usize,
    min_chunk: usize,
    chunks_per_worker: usize,
    rounds: usize,
};

fn benchmark(comptime heavy: bool, init: std.process.Init, config: Config) !void {
    const data = try init.gpa.alloc(u64, config.count);
    defer init.gpa.free(data);
    for (data, 0..) |*value, index| value.* = @intCast(index);
    var counted = std.testing.FailingAllocator.init(init.gpa, .{});
    var pool = try parz.Pool(void).init(counted.allocator(), init.io, .{
        .workers = if (config.lanes > 1) config.lanes - 1 else 0,
        .max_workers = if (config.lanes == 1) 0 else 64,
        .max_callers = 1,
        .pin_workers = true,
    });
    defer pool.deinit();
    try pool.start();
    try affinity.pinCaller(&pool, config.cpu);
    var token = parz.CancelToken{};
    const Map = struct {
        fn run(_: *parz.Worker(void), values: []const u64, index: usize) u64 {
            return work(heavy, values[index]);
        }
        fn add(a: u64, b: u64) u64 {
            return a +% b;
        }
    };
    const options = parz.ParallelOptions{
        .min_chunk = config.min_chunk,
        .chunks_per_worker = config.chunks_per_worker,
        .max_chunks = 256,
        .serial_threshold = 0,
    };
    const expected = serial(heavy, data);
    if (!heavy) {
        const oracle: u64 = @truncate(@as(u128, config.count) * (config.count - 1) / 2);
        if (expected != oracle) return error.ChecksumMismatch;
    }
    const storage = try init.gpa.alloc(i96, try std.math.mul(usize, 4, config.rounds));
    defer init.gpa.free(storage);
    var samples: [4][]i96 = undefined;
    for (&samples, 0..) |*slice, index| slice.* = storage[index * config.rounds ..][0..config.rounds];
    // Warm up and validate both public API paths before timing.
    var cancellable = options;
    cancellable.cancel = &token;
    if (try parz.parallelFoldInfallible(&pool, u64, data, data.len, options, 0, Map.run, Map.add) != expected) return error.ChecksumMismatch;
    if (try parz.parallelFoldInfallible(&pool, u64, data, data.len, cancellable, 0, Map.run, Map.add) != expected) return error.ChecksumMismatch;
    std.debug.print("infallible-fold workload={s} count={d} workers={d} min_chunk={d} chunks_per_worker={d} caller_cpu={d} worker_cpus={any} checksum={d}\n", .{
        if (heavy) "compute" else "scan", config.count, pool.spawned_background, config.min_chunk, config.chunks_per_worker, config.cpu, pool.pinned_cpus[0..pool.spawned_background], expected,
    });
    var allocation_counts: [4]usize = @splat(0);
    var allocation_bytes: [4]usize = @splat(0);
    for (0..config.rounds) |round| {
        for (0..4) |order| {
            const path = if (round % 2 == 0) order else 3 - order;
            const initial_allocations = counted.allocations;
            const initial_bytes = counted.allocated_bytes;
            std.mem.doNotOptimizeAway(data.ptr);
            const start = std.Io.Clock.Timestamp.now(init.io, .awake);
            const result = switch (path) {
                0, 2 => serial(heavy, data),
                1 => try parz.parallelFoldInfallible(&pool, u64, data, data.len, options, 0, Map.run, Map.add),
                3 => try parz.parallelFoldInfallible(&pool, u64, data, data.len, cancellable, 0, Map.run, Map.add),
                else => unreachable,
            };
            samples[path][round] = start.untilNow(init.io).raw.toNanoseconds();
            if (result != expected) return error.ChecksumMismatch;
            allocation_counts[path] = counted.allocations - initial_allocations;
            allocation_bytes[path] = counted.allocated_bytes - initial_bytes;
            std.debug.print("sample={d} path={d} ns={d} allocations={d} allocated_bytes={d}\n", .{
                round, path, samples[path][round], allocation_counts[path], allocation_bytes[path],
            });
        }
    }
    for (samples) |values| std.mem.sort(i96, values, {}, std.sort.asc(i96));
    for ([_]usize{ 1, 3 }) |path| {
        const times = timing.Times{ .serial_ns = samples[path - 1][config.rounds / 2], .parallel_ns = samples[path][config.rounds / 2] };
        std.debug.print("infallible-fold cancel={s} serial_ns={d} parallel_ns={d} speedup={d:.3} allocations={d} allocated_bytes={d} statistic=median\n", .{
            if (path == 1) "none" else "token", times.serial_ns, times.parallel_ns, times.speedup(), allocation_counts[path], allocation_bytes[path],
        });
    }
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const kind = args.next() orelse "scan";
    const config = Config{
        .count = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 1_000_000,
        .lanes = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 8,
        .cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 31,
        .min_chunk = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 1,
        .chunks_per_worker = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 64,
        .rounds = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 9,
    };
    if (config.count == 0 or config.rounds == 0) return error.InvalidArguments;
    if (std.mem.eql(u8, kind, "scan")) return benchmark(false, init, config);
    if (std.mem.eql(u8, kind, "compute")) return benchmark(true, init, config);
    return error.InvalidArguments;
}
