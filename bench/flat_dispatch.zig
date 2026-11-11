//! Fixed-CPU flat cost hints, borrowed contexts and explicit dispatch scratch.
//! Compiles against the pre-feature core too, for identical-harness comparisons.
const std = @import("std");
const parz = @import("parz");
const timing = @import("timing.zig");
const affinity = @import("affinity.zig");

const Config = struct {
    kind: []const u8,
    count: usize,
    lanes: usize,
    cpu: usize,
    chunks_per_worker: usize,
    rounds: usize,
    repetitions: usize,
};

const ScratchContext = struct {
    bytes: []u8,
    fn init(a: std.mem.Allocator, _: usize) !@This() {
        return .{ .bytes = try a.alloc(u8, 65536) };
    }
    fn deinit(a: std.mem.Allocator, self: *@This()) void {
        a.free(self.bytes);
    }
};

fn benchmark(comptime Ctx: type, comptime heavy: bool, init: std.process.Init, config: Config) !void {
    const data = try init.gpa.alloc(u64, config.count);
    defer init.gpa.free(data);
    for (data, 0..) |*value, index| value.* = @intCast(index);
    var counted = std.testing.FailingAllocator.init(init.gpa, .{});
    var pool_options = parz.Options(Ctx){
        .workers = if (config.lanes > 1) config.lanes - 1 else 0,
        .max_workers = if (config.lanes == 1) 0 else 64,
        .max_callers = 1,
        .pin_workers = true,
    };
    if (comptime Ctx != void) {
        pool_options.context_init = Ctx.init;
        pool_options.context_deinit = Ctx.deinit;
    }
    var pool = try parz.Pool(Ctx).init(counted.allocator(), init.io, pool_options);
    defer pool.deinit();
    try pool.start();
    try affinity.pinCaller(&pool, config.cpu);
    const borrowed = Ctx != void and @hasDecl(parz, "ParallelScratch");
    const worker: ?*parz.Worker(Ctx) = if (borrowed) pool.claimCaller() orelse return error.NoCallerSlot else null;
    defer if (worker) |w| pool.releaseCaller(w);
    const DispatchScratch = if (@hasDecl(parz, "ParallelScratch")) parz.ParallelScratch else struct {};
    var bytes: [16384]u8 = undefined;
    var scratch = if (@hasDecl(parz, "ParallelScratch")) DispatchScratch.init(&bytes) else DispatchScratch{};
    var options = parz.ParallelOptions{ .chunks_per_worker = config.chunks_per_worker };
    if (comptime @hasField(parz.ParallelOptions, "estimated_item_ns")) {
        if (std.mem.eql(u8, config.kind, "cheap")) options.estimated_item_ns = 1;
    }
    if (comptime @hasField(parz.ParallelOptions, "scratch")) {
        if (std.mem.eql(u8, config.kind, "scratch")) options.scratch = &scratch;
    }
    const Run = struct {
        pool: *parz.Pool(Ctx),
        worker: ?*parz.Worker(Ctx),
        data: []const u64,
        options: parz.ParallelOptions,
        fn work(value: u64) u64 {
            if (!heavy) return value;
            var x = value +% 0x9e3779b97f4a7c15;
            for (0..64) |_| {
                x = x *% 6364136223846793005 +% 1442695040888963407;
                x ^= x >> 17;
            }
            return x;
        }
        fn serial(self: *@This()) !u64 {
            var sum: u64 = 0;
            for (self.data) |value| sum +%= work(value);
            return sum;
        }
        fn parallel(self: *@This()) !u64 {
            if (comptime borrowed) return parz.parallelFoldInfallible(self.worker.?, u64, self.data, self.data.len, self.options, 0, map, add);
            return parz.parallelFoldInfallible(self.pool, u64, self.data, self.data.len, self.options, 0, map, add);
        }
        fn map(_: *parz.Worker(Ctx), values: []const u64, i: usize) u64 {
            return work(values[i]);
        }
        fn add(a: u64, b: u64) u64 {
            return a +% b;
        }
    };
    var run = Run{ .pool = &pool, .worker = worker, .data = data, .options = options };
    const expected = if (heavy) try run.serial() else @as(u64, @truncate(@as(u128, config.count) * (config.count - 1) / 2));
    const before = counted.allocations;
    const before_bytes = counted.allocated_bytes;
    if (try run.parallel() != expected) return error.ChecksumMismatch;
    const allocations = counted.allocations - before;
    const allocated_bytes = counted.allocated_bytes - before_bytes;
    const times = try timing.pairedRepeated(u64, init.gpa, init.io, config.rounds, config.repetitions, expected, &run, Run.serial, Run.parallel);
    std.debug.print("flat-dispatch kind={s} count={d} lanes={d} cpw={d} caller_cpu={d} worker_cpus={any} checksum={d} allocations={d} allocated_bytes={d} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median repetitions={d}\n", .{
        config.kind,                                  config.count,    pool.parallelWorkerCount(), config.chunks_per_worker, config.cpu,
        pool.pinned_cpus[0..pool.spawned_background], expected,        allocations,                allocated_bytes,          times.serial_ns,
        times.parallel_ns,                            times.speedup(), config.repetitions,
    });
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const config = Config{
        .kind = args.next() orelse "scan",
        .count = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 1000003,
        .lanes = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 8,
        .cpu = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 31,
        .chunks_per_worker = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 16,
        .rounds = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 21,
        .repetitions = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 1,
    };
    if (config.count == 0 or config.lanes == 0 or config.rounds == 0 or config.repetitions == 0) return error.InvalidArguments;
    if (std.mem.eql(u8, config.kind, "context")) return benchmark(ScratchContext, false, init, config);
    if (std.mem.eql(u8, config.kind, "compute")) return benchmark(void, true, init, config);
    if (!std.mem.eql(u8, config.kind, "scan") and !std.mem.eql(u8, config.kind, "cheap") and
        !std.mem.eql(u8, config.kind, "scratch")) return error.InvalidArguments;
    return benchmark(void, false, init, config);
}
