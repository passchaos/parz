const std = @import("std");
const parz = @import("parz");
const timing = @import("timing");
const affinity = @import("affinity");
const Context = struct {
    allocator: std.mem.Allocator,
    memory: []u8,
    fn init(allocator: std.mem.Allocator, _: usize) !@This() {
        const memory = try allocator.alloc(u8, 65536);
        @memset(memory, 0);
        std.mem.doNotOptimizeAway(memory.ptr);
        return .{ .allocator = allocator, .memory = memory };
    }
    fn deinit(_: std.mem.Allocator, self: *@This()) void { self.allocator.free(self.memory); }
};
const Run = struct {
    pool: *parz.Pool(Context),
    token: *parz.CancelToken,
    flat_calls: usize = 0,
    fn serial(self: *@This()) !u64 {
        for (0..1024) |_| {
            std.mem.doNotOptimizeAway(self);
            if (!self.token.isCancelled()) return error.UnexpectedTokenState;
        }
        return 0;
    }
    fn callback(_: *parz.Worker(Context), _: void, _: parz.Chunk) anyerror!void { return error.UnexpectedCallback; }
    fn flat(self: *@This()) !u64 {
        for (0..1024) |_| {
            std.mem.doNotOptimizeAway(self);
            self.flat_calls += 1;
            parz.parallelForRange(self.pool, {}, 64, .{ .cancel = self.token }, callback) catch |err| {
                if (err == error.Cancelled) continue;
                return err;
            };
            return error.UnexpectedSuccess;
        }
        return 0;
    }
};
pub fn main(init: std.process.Init) !void {
    var counted = std.testing.FailingAllocator.init(init.gpa, .{});
    var pool = try parz.Pool(Context).init(counted.allocator(), init.io, .{ .max_workers = 0, .max_callers = 1, .context_init = Context.init, .context_deinit = Context.deinit });
    defer pool.deinit();
    try pool.start();
    try affinity.pinCaller(&pool, 31);
    var token = parz.CancelToken{};
    token.cancel();
    var run = Run{ .pool = &pool, .token = &token };
    const allocations = counted.allocations;
    const bytes = counted.allocated_bytes;
    const result = try timing.paired(u64, init.gpa, init.io, 9, 0, &run, Run.serial, Run.flat);
    std.debug.print("cancelled-context bytes=65536 calls={d} allocations={d} allocated_bytes={d} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median_batch_1024 checksum=0\n", .{run.flat_calls, counted.allocations-allocations, counted.allocated_bytes-bytes, result.serial_ns, result.parallel_ns, result.speedup()});
}
