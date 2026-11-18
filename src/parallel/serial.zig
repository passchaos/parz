//! Serial fallback lifetime, borrowed lane context and callback order.

const std = @import("std");
const core = @import("../core.zig");
const api = @import("../parallel.zig");
const types = @import("types.zig");
const Chunk = types.Chunk;
const Options = types.Options;
const CancelToken = @import("../cancel.zig").CancelToken;
const executor_mod = @import("executor.zig");
const checkCancel = @import("cancellation.zig").checkCancel;
const cancel_block = @import("cancellation.zig").cancel_block;

pub fn serialRange(
    executor: anytype,
    shared: anytype,
    count: usize,
    cancel: ?*CancelToken,
    comptime run: anytype,
) anyerror!void {
    try checkCancel(cancel);
    var lane = try executor_mod.SerialLane(@TypeOf(executor)).init(executor);
    defer lane.deinit();
    const worker = lane.worker();
    try checkCancel(cancel);
    try run(worker, shared, .{ .start = 0, .end = count });
    try checkCancel(cancel);
}

pub fn serialFold(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    cancel: ?*CancelToken,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    try checkCancel(cancel);
    var lane = try executor_mod.SerialLane(@TypeOf(executor)).init(executor);
    defer lane.deinit();
    const worker = lane.worker();
    var total = identity;
    var i: usize = 0;
    while (i < count) {
        try checkCancel(cancel);
        const block_end = @min(i +| cancel_block, count);
        while (i < block_end) : (i += 1) {
            total = combine(total, try map(worker, shared, i));
        }
    }
    try checkCancel(cancel);
    return total;
}

pub fn serialFoldInfallible(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    cancel: ?*CancelToken,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    try checkCancel(cancel);
    var lane = try executor_mod.SerialLane(@TypeOf(executor)).init(executor);
    defer lane.deinit();
    const worker = lane.worker();
    var total = identity;
    var i: usize = 0;
    while (i < count) {
        try checkCancel(cancel);
        const block_end = @min(i +| cancel_block, count);
        while (i < block_end) : (i += 1) {
            total = combine(total, map(worker, shared, i));
        }
    }
    try checkCancel(cancel);
    return total;
}

pub fn serialFoldRange(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    cancel: ?*CancelToken,
    identity: T,
    comptime map_range: anytype,
    comptime combine: anytype,
) anyerror!T {
    try checkCancel(cancel);
    var lane = try executor_mod.SerialLane(@TypeOf(executor)).init(executor);
    defer lane.deinit();
    const worker = lane.worker();
    try checkCancel(cancel);
    const value = try map_range(worker, shared, .{ .start = 0, .end = count });
    try checkCancel(cancel);
    return combine(identity, value);
}

pub fn serialFoldRangeInfallible(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    cancel: ?*CancelToken,
    identity: T,
    comptime map_range: anytype,
    comptime combine: anytype,
) anyerror!T {
    try checkCancel(cancel);
    var lane = try executor_mod.SerialLane(@TypeOf(executor)).init(executor);
    defer lane.deinit();
    const worker = lane.worker();
    try checkCancel(cancel);
    const value = map_range(worker, shared, .{ .start = 0, .end = count });
    try checkCancel(cancel);
    return combine(identity, value);
}

test "serial fallback worker index matches its context initialization index" {
    const Context = struct {
        index: usize,
        fn init(_: std.mem.Allocator, index: usize) !@This() {
            return .{ .index = index };
        }
    };
    const Run = struct {
        fn range(w: *core.Worker(Context), _: void, _: Chunk) anyerror!void {
            try std.testing.expectEqual(w.context().index, w.index);
            try std.testing.expect(!w.active.load(.monotonic));
        }
        fn map(w: *core.Worker(Context), _: void, index: usize) anyerror!u64 {
            try std.testing.expectEqual(w.context().index, w.index);
            return index;
        }
        fn value(w: *core.Worker(Context), mismatch: *bool, index: usize) u64 {
            mismatch.* = mismatch.* or w.context().index != w.index;
            return index;
        }
        fn rangeMap(w: *core.Worker(Context), _: void, chunk: Chunk) anyerror!u64 {
            try std.testing.expectEqual(w.context().index, w.index);
            return (chunk.start + chunk.end - 1) * (chunk.end - chunk.start) / 2;
        }
        fn rangeValue(w: *core.Worker(Context), mismatch: *bool, chunk: Chunk) u64 {
            mismatch.* = mismatch.* or w.context().index != w.index;
            return (chunk.start + chunk.end - 1) * (chunk.end - chunk.start) / 2;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    for (0..5) |workers| {
        var pool = try core.Pool(Context).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .context_init = Context.init,
        });
        defer pool.deinit();
        try pool.start();
        for ([_]bool{ false, true }) |exhausted| {
            const held = if (exhausted) pool.claimCaller().? else null;
            defer if (held) |caller| pool.releaseCaller(caller);
            const options = Options{ .serial_threshold = if (exhausted) 0 else 4096 };
            try api.parallelForRange(&pool, {}, 8, options, Run.range);
            try std.testing.expectEqual(@as(u64, 28), try api.parallelFold(&pool, u64, {}, 8, options, 0, Run.map, Run.add));
            var mismatch = false;
            try std.testing.expectEqual(@as(u64, 28), try api.parallelFoldInfallible(&pool, u64, &mismatch, 8, options, 0, Run.value, Run.add));
            try std.testing.expectEqual(@as(u64, 28), try api.parallelFoldRange(&pool, u64, {}, 8, options, 0, Run.rangeMap, Run.add));
            try std.testing.expectEqual(@as(u64, 28), try api.parallelFoldRangeInfallible(&pool, u64, &mismatch, 8, options, 0, Run.rangeValue, Run.add));
            try std.testing.expect(!mismatch);
        }
    }
}

test "already cancelled serial calls skip temporary context construction" {
    const Context = struct {
        var reject_temporary: bool = false;
        fn init(_: std.mem.Allocator, _: usize) !@This() {
            if (reject_temporary) return error.UnexpectedContextConstruction;
            return .{};
        }
    };
    const Run = struct {
        fn range(_: *core.Worker(Context), _: void, _: Chunk) anyerror!void {
            return error.UnexpectedCallback;
        }
        fn map(_: *core.Worker(Context), _: void, _: usize) anyerror!u64 {
            return error.UnexpectedCallback;
        }
        fn value(_: *core.Worker(Context), _: void, _: usize) u64 {
            @panic("cancelled callback must not run");
        }
        fn rangeMap(_: *core.Worker(Context), _: void, _: Chunk) anyerror!u64 {
            return error.UnexpectedCallback;
        }
        fn rangeValue(_: *core.Worker(Context), _: void, _: Chunk) u64 {
            @panic("cancelled callback must not run");
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    Context.reject_temporary = false;
    var pool = try core.Pool(Context).init(std.testing.allocator, std.testing.io, .{
        .max_workers = 0,
        .max_callers = 1,
        .context_init = Context.init,
    });
    defer pool.deinit();
    try pool.start();
    Context.reject_temporary = true;
    defer Context.reject_temporary = false;
    var token = CancelToken{};
    token.cancel();
    for ([_]bool{ false, true }) |exhausted| {
        const held = if (exhausted) pool.claimCaller().? else null;
        defer if (held) |caller| pool.releaseCaller(caller);
        const options = Options{ .serial_threshold = if (exhausted) 0 else 4096, .cancel = &token };
        try std.testing.expectError(error.Cancelled, api.parallelForRange(&pool, {}, 8, options, Run.range));
        try std.testing.expectError(error.Cancelled, api.parallelFold(&pool, u64, {}, 8, options, 0, Run.map, Run.add));
        try std.testing.expectError(error.Cancelled, api.parallelFoldInfallible(&pool, u64, {}, 8, options, 0, Run.value, Run.add));
        try std.testing.expectError(error.Cancelled, api.parallelFoldRange(&pool, u64, {}, 8, options, 0, Run.rangeMap, Run.add));
        try std.testing.expectError(error.Cancelled, api.parallelFoldRangeInfallible(&pool, u64, {}, 8, options, 0, Run.rangeValue, Run.add));
    }
}

test "serial fallback kickstart leaves jobs local across worker counts" {
    const Run = struct {
        fn leaf(_: *core.Task(void), value: usize) usize {
            return value + 1;
        }
        fn range(w: *core.Worker(void), _: void, _: Chunk) anyerror!void {
            try std.testing.expect(!w.active.load(.monotonic));
            var task = w.begin();
            var first: core.Future(void, usize, usize) = undefined;
            var second: core.Future(void, usize, usize) = undefined;
            first.initFork(&task, leaf, 3);
            second.initFork(&task, leaf, 7);
            w.pool.kickstart(w, 2);
            try std.testing.expectEqual(@import("../job.zig").JobState.queued_local, first.job.state());
            try std.testing.expectEqual(@as(usize, 12), first.joinOrCall(&task, leaf) + second.joinOrCall(&task, leaf));
            try std.testing.expect(w.job_head.isTail());
            try std.testing.expect(w.shared_head.isTail());
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
        for ([_]bool{ false, true }) |exhausted| {
            const caller = if (exhausted) pool.claimCaller().? else null;
            defer if (caller) |held| pool.releaseCaller(held);
            const options = Options{ .serial_threshold = if (exhausted) 0 else 4096 };
            for (0..10) |_| try api.parallelForRange(&pool, {}, 8, options, Run.range);
        }
    }
}

test "serial fallback destroys the mutated worker context" {
    const Context = struct {
        allocator: std.mem.Allocator,
        scratch: std.ArrayList(u8) = .empty,

        fn init(allocator: std.mem.Allocator, _: usize) !@This() {
            return .{ .allocator = allocator };
        }

        fn deinit(_: std.mem.Allocator, self: *@This()) void {
            self.scratch.deinit(self.allocator);
        }
    };
    const Run = struct {
        fn run(w: *core.Worker(Context), _: void, index: usize) anyerror!void {
            const ctx = w.context();
            try ctx.scratch.append(ctx.allocator, @intCast(index));
            try std.testing.expectEqual(index + 1, ctx.scratch.items.len);
        }

        fn map(w: *core.Worker(Context), shared: void, index: usize) anyerror!u64 {
            try run(w, shared, index);
            return index;
        }

        fn infallible(w: *core.Worker(Context), shared: void, index: usize) u64 {
            run(w, shared, index) catch @panic("scratch allocation or contents failed");
            return index;
        }

        fn rangeMap(w: *core.Worker(Context), shared: void, chunk: Chunk) anyerror!u64 {
            var total: u64 = 0;
            for (chunk.start..chunk.end) |index| {
                try run(w, shared, index);
                total += index;
            }
            return total;
        }

        fn rangeInfallible(w: *core.Worker(Context), shared: void, chunk: Chunk) u64 {
            return rangeMap(w, shared, chunk) catch @panic("scratch allocation or contents failed");
        }

        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    var pool = try core.Pool(Context).init(std.testing.allocator, std.testing.io, .{
        .max_workers = 0,
        .max_callers = 1,
        .context_init = Context.init,
        .context_deinit = Context.deinit,
    });
    defer pool.deinit();
    try pool.start();
    // Exercise both the small-input fallback and caller-slot exhaustion.
    for ([_]bool{ false, true }) |exhausted| {
        const caller = if (exhausted) pool.claimCaller().? else null;
        defer if (caller) |lane| pool.releaseCaller(lane);
        const options = Options{ .serial_threshold = if (exhausted) 0 else 4096 };
        try api.parallelFor(&pool, {}, 8, options, Run.run);
        try std.testing.expectEqual(@as(u64, 28), try api.parallelFold(
            &pool,
            u64,
            {},
            8,
            options,
            0,
            Run.map,
            Run.combine,
        ));
        try std.testing.expectEqual(@as(u64, 28), try api.parallelFoldInfallible(
            &pool,
            u64,
            {},
            8,
            options,
            0,
            Run.infallible,
            Run.combine,
        ));
        try std.testing.expectEqual(@as(u64, 28), try api.parallelFoldRange(
            &pool,
            u64,
            {},
            8,
            options,
            0,
            Run.rangeMap,
            Run.combine,
        ));
        try std.testing.expectEqual(@as(u64, 28), try api.parallelFoldRangeInfallible(
            &pool,
            u64,
            {},
            8,
            options,
            0,
            Run.rangeInfallible,
            Run.combine,
        ));
    }
    // std.testing.allocator verifies that each callback's resized scratch is
    // freed by the destructor of the context that the callback actually used.
}

test "parallelFor serial fallback with no background workers" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 0,
        .max_workers = 0,
        .max_callers = 1,
        .max_execute_states = 8,
    });
    defer pool.deinit();
    try pool.start();

    var sum: u64 = 0;
    const Ctx = struct {
        fn run(_: *core.Worker(void), shared: *u64, index: usize) anyerror!void {
            shared.* += index;
        }
    };
    try api.parallelFor(&pool, &sum, 100, .{ .min_chunk = 1 }, Ctx.run);
    try std.testing.expectEqual(@as(u64, 4950), sum);
}
