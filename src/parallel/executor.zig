//! Resolve a pool or an explicitly borrowed worker without runtime dispatch.

pub fn PoolType(comptime Executor: type) type {
    const E = @typeInfo(Executor).pointer.child;
    return if (@hasField(E, "pool")) @typeInfo(@TypeOf(@as(E, undefined).pool)).pointer.child else E;
}

pub fn getPool(executor: anytype) *PoolType(@TypeOf(executor)) {
    return if (comptime @hasField(@TypeOf(executor.*), "pool")) executor.pool else executor;
}

pub fn borrowedWorker(executor: anytype) ?*PoolType(@TypeOf(executor)).WorkerType {
    return if (comptime @hasField(@TypeOf(executor.*), "pool")) executor else null;
}

/// A serial call on an explicit worker borrows its context. A pool call owns
/// the same independent temporary context and fallback index as before.
pub fn SerialLane(comptime Executor: type) type {
    const P = PoolType(Executor);
    const borrowed = @hasField(@typeInfo(Executor).pointer.child, "pool");
    return struct {
        const Self = @This();
        storage: if (borrowed) *P.WorkerType else P.WorkerType,

        pub fn init(executor: Executor) !Self {
            if (comptime borrowed) return .{ .storage = executor };
            const pool = getPool(executor);
            return .{ .storage = .{
                .pool = pool,
                .index = pool.worker_count,
                .active = false,
                .ctx = try pool.createTempContext(),
            } };
        }

        pub inline fn worker(self: *Self) *P.WorkerType {
            return if (comptime borrowed) self.storage else &self.storage;
        }

        pub fn deinit(self: *Self) void {
            if (comptime !borrowed) self.storage.pool.destroyTempContext(&self.storage.ctx);
        }
    };
}

test "explicit worker reuses context for every flat API and keeps its caller slot" {
    const std = @import("std");
    const core = @import("../core.zig");
    const api = @import("../parallel.zig");
    const Ctx = struct {
        bytes: []u8,
        calls: usize = 0,
        fn init(a: std.mem.Allocator, _: usize) !@This() {
            return .{ .bytes = try a.alloc(u8, 65536) };
        }
        fn deinit(a: std.mem.Allocator, ctx: *@This()) void {
            a.free(ctx.bytes);
        }
    };
    const W = core.Worker(Ctx);
    const Run = struct {
        fn item(w: *W, expected: *W, _: usize) anyerror!void {
            if (w != expected) return error.WrongLane;
            w.ctx.calls += 1;
        }
        fn each(w: *W, values: []u64, i: usize) anyerror!void {
            w.ctx.calls += 1;
            values[i] = i;
        }
        fn cell(w: *W, expected: *W, _: usize, _: usize) anyerror!void {
            try item(w, expected, 0);
        }
        fn range(w: *W, expected: *W, c: api.Chunk) anyerror!void {
            if (w != expected) return error.WrongLane;
            w.ctx.calls += c.end - c.start;
        }
        fn map(w: *W, expected: *W, i: usize) anyerror!u64 {
            try item(w, expected, i);
            return i;
        }
        fn value(w: *W, expected: *W, i: usize) u64 {
            std.debug.assert(w == expected);
            w.ctx.calls += 1;
            return i;
        }
        fn foldRange(w: *W, expected: *W, c: api.Chunk) anyerror!u64 {
            try range(w, expected, c);
            return (c.start + c.end - 1) * (c.end - c.start) / 2;
        }
        fn rangeValue(w: *W, expected: *W, c: api.Chunk) u64 {
            std.debug.assert(w == expected);
            w.ctx.calls += c.end - c.start;
            return (c.start + c.end - 1) * (c.end - c.start) / 2;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
        fn fail(_: *W, _: void, i: usize) anyerror!void {
            if (i == 7) return error.ExpectedFailure;
        }
    };
    for (0..5) |workers| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var pool = try core.Pool(Ctx).init(failing.allocator(), std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .context_init = Ctx.init,
            .context_deinit = Ctx.deinit,
        });
        defer pool.deinit();
        try pool.start();
        const worker = pool.claimCaller().?;
        defer pool.releaseCaller(worker);
        const allocated = failing.alloc_index;
        failing.fail_index = allocated;
        for ([_]api.Options{ .{}, .{ .serial_threshold = 0, .max_workers = 1, .chunks_per_worker = 1 } }) |options| {
            for (0..3) |_| {
                var values: [16]u64 = undefined;
                try api.parallelFor(worker, worker, 16, options, Run.item);
                try api.parallelForEach(worker, &values, options, Run.each);
                try api.parallelFor2D(worker, worker, 4, 4, options, Run.cell);
                try api.parallelForRange(worker, worker, 16, options, Run.range);
                try std.testing.expectEqual(@as(u64, 120), try api.parallelFold(worker, u64, worker, 16, options, 0, Run.map, Run.add));
                try std.testing.expectEqual(@as(u64, 120), try api.parallelFoldInfallible(worker, u64, worker, 16, options, 0, Run.value, Run.add));
                try std.testing.expectEqual(@as(u64, 120), try api.parallelFoldRange(worker, u64, worker, 16, options, 0, Run.foldRange, Run.add));
                try std.testing.expectEqual(@as(u64, 120), try api.parallelFoldRangeInfallible(worker, u64, worker, 16, options, 0, Run.rangeValue, Run.add));
                try std.testing.expectEqual(@as(u64, 120), try api.parallelReduce(worker, u64, worker, 16, options, 0, Run.map, Run.add));
                try std.testing.expectEqual(@as(u64, 120), try api.parallelReduceInfallible(worker, u64, worker, 16, options, 0, Run.value, Run.add));
                for (values, 0..) |value, i| try std.testing.expectEqual(i, value);
                try std.testing.expect(pool.caller_busy[0]);
            }
        }
        try std.testing.expectEqual(@as(usize, 960), worker.ctx.calls);
        var tiny: [1]u8 = undefined;
        var scratch = api.Scratch.init(&tiny);
        try std.testing.expectError(error.OutOfMemory, api.parallelFoldInfallible(worker, u64, worker, 16, .{
            .serial_threshold = 0,
            .max_workers = 1,
            .chunks_per_worker = 1,
            .scratch = &scratch,
        }, 0, Run.value, Run.add));
        try std.testing.expect(!scratch.busy);
        try std.testing.expectEqual(@as(usize, 960), worker.ctx.calls);
        try std.testing.expectError(error.ExpectedFailure, api.parallelFor(worker, {}, 16, .{}, Run.fail));
        var token = @import("../cancel.zig").CancelToken{};
        token.cancel();
        try std.testing.expectError(error.Cancelled, api.parallelFor(worker, {}, 16, .{ .cancel = &token }, Run.fail));
        try std.testing.expect(pool.caller_busy[0]);
        try std.testing.expectEqual(allocated, failing.alloc_index);
        try std.testing.expect(!failing.has_induced_failure);
    }
}

test "nested worker dispatch retains parent futures and ordered output across lanes" {
    const std = @import("std");
    const core = @import("../core.zig");
    const api = @import("../parallel.zig");
    const Run = struct {
        fn identity(_: *core.Task(void), value: u64) u64 {
            return value;
        }
        fn map(_: *core.Worker(void), _: void, i: usize) u64 {
            return i;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
        fn range(w: *core.Worker(void), _: void, c: api.Chunk) anyerror!u64 {
            var task = w.begin();
            var parent: core.Future(void, u64, u64) = undefined;
            parent.initFork(&task, identity, 17);
            const inner = api.parallelFoldInfallible(w, u64, {}, 64, .{
                .serial_threshold = 0,
                .chunks_per_worker = 3,
                .max_chunks = 7,
            }, 0, map, add);
            const joined = parent.joinOrCall(&task, identity);
            if (joined != 17 or try inner != 2016) return error.WrongNestedResult;
            return (c.start + c.end - 1) * (c.end - c.start) / 2;
        }
    };
    for (0..5) |workers| {
        var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
        });
        defer pool.deinit();
        try pool.start();
        const worker = pool.claimCaller().?;
        defer pool.releaseCaller(worker);
        for ([_]api.Schedule{ .dynamic, .static }) |schedule| {
            for (0..5) |_| {
                const result = try api.parallelFoldRange(worker, u64, {}, 257, .{
                    .serial_threshold = 0,
                    .max_chunks = 9,
                    .chunks_per_worker = 9,
                    .schedule = schedule,
                }, 0, Run.range, Run.add);
                try std.testing.expectEqual(@as(u64, 32896), result);
                try std.testing.expect(worker.job_head.isTail());
                try std.testing.expect(pool.caller_busy[0]);
            }
        }
    }
}
