//! Bounded result/future storage, lane scheduling and ordered error selection.

const std = @import("std");
const builtin = @import("builtin");
const core = @import("../core.zig");
const api = @import("../parallel.zig");
const types = @import("types.zig");
const Chunk = types.Chunk;
const Schedule = types.Schedule;
const CancelToken = @import("../cancel.zig").CancelToken;
const Scratch = @import("scratch.zig").Scratch;
const ScratchLease = @import("scratch.zig").Lease;
const ChunkCursor = @import("planning.zig").ChunkCursor;
const dynamicClaimBatch = @import("planning.zig").dynamicClaimBatch;

// Keep dispatch storage in one bounded buffer, outside the serial fallback frame.
pub noinline fn dispatchRange(
    pool: anytype,
    task: anytype,
    comptime Input: type,
    runner: anytype,
    count: usize,
    chunks: usize,
    lanes: usize,
    schedule: Schedule,
    scratch: ?*Scratch,
    comptime exec: anytype,
) anyerror!void {
    var fallback = std.heap.stackFallback(4096, pool.allocator);
    var lease = ScratchLease.init(scratch, fallback.get());
    defer lease.deinit();
    const allocator = lease.allocator;
    const results = try allocator.alloc(anyerror!void, chunks);
    defer allocator.free(results);
    try runLanes(pool, task, Input, runner, count, lanes, schedule, results, allocator, exec);
    for (results) |result| try result;
}

pub noinline fn dispatchFold(
    pool: anytype,
    task: anytype,
    comptime T: type,
    comptime Input: type,
    runner: anytype,
    count: usize,
    chunks: usize,
    lanes: usize,
    schedule: Schedule,
    scratch: ?*Scratch,
    identity: T,
    comptime exec: anytype,
    comptime combine: anytype,
) anyerror!T {
    var fallback = std.heap.stackFallback(4096, pool.allocator);
    var lease = ScratchLease.init(scratch, fallback.get());
    defer lease.deinit();
    const allocator = lease.allocator;
    const results = try allocator.alloc(anyerror!T, chunks);
    defer allocator.free(results);
    try runLanes(pool, task, Input, runner, count, lanes, schedule, results, allocator, exec);
    var total = identity;
    for (results) |result| total = combine(total, try result);
    return total;
}

/// Without callback errors or cancellation, store only values and use the
/// plain-return chunk callback. Allocation errors still propagate to callers.
pub noinline fn dispatchFoldValue(
    pool: anytype,
    task: anytype,
    comptime T: type,
    comptime Input: type,
    runner: anytype,
    count: usize,
    chunks: usize,
    lanes: usize,
    schedule: Schedule,
    scratch: ?*Scratch,
    identity: T,
    comptime exec: anytype,
    comptime combine: anytype,
) anyerror!T {
    var fallback = std.heap.stackFallback(4096, pool.allocator);
    var lease = ScratchLease.init(scratch, fallback.get());
    defer lease.deinit();
    const allocator = lease.allocator;
    const results = try allocator.alloc(T, chunks);
    defer allocator.free(results);
    try runLanes(pool, task, Input, runner, count, lanes, schedule, results, allocator, exec);
    var total = identity;
    for (results) |result| total = combine(total, result);
    return total;
}

/// One future per lane bounds the number of simultaneous chunk callbacks.
/// Dynamic lanes claim disjoint result slots; static lanes own contiguous
/// spans. All futures are joined before ordered reduction. The caller's
/// future is the retained local tail and runs before any waits.
fn runLanes(
    pool: anytype,
    task: anytype,
    comptime Input: type,
    runner: anytype,
    count: usize,
    requested_lanes: usize,
    schedule: Schedule,
    results: anytype,
    allocator: std.mem.Allocator,
    comptime exec: anytype,
) anyerror!void {
    const Result = @typeInfo(@TypeOf(results)).pointer.child;
    const lanes = @min(requested_lanes, results.len);
    if (lanes == 1) {
        var cursor = ChunkCursor.init(count, results.len);
        for (results) |*result| result.* = task.call(Result, exec, Input{ .runner = runner, .chunk = cursor.next() });
        return;
    }

    return switch (schedule) {
        .dynamic => runDynamicLanes(pool, task, Input, runner, count, lanes, results, allocator, exec),
        .static => runStaticLanes(pool, task, Input, runner, count, lanes, results, allocator, exec),
    };
}

fn runDynamicLanes(
    pool: anytype,
    task: anytype,
    comptime Input: type,
    runner: anytype,
    count: usize,
    lanes: usize,
    results: anytype,
    allocator: std.mem.Allocator,
    comptime exec: anytype,
) anyerror!void {
    const P = @TypeOf(pool.*);
    const Task = P.TaskType;
    const Runner = @TypeOf(runner);
    const Result = @typeInfo(@TypeOf(results)).pointer.child;

    const State = struct {
        runner: Runner,
        results: []Result,
        size: usize,
        extra: usize,
        claim_batch: usize,
        next: std.atomic.Value(usize) = .init(0),

        fn run(t: *Task, self: *@This()) void {
            // Keep the common single-chunk claim loop byte-for-byte tight;
            // batching only starts where cursor contention can matter.
            if (self.claim_batch == 1) {
                while (true) {
                    const index = self.next.fetchAdd(1, .monotonic);
                    if (index >= self.results.len) return;
                    self.execute(t, index);
                }
            }
            while (true) {
                const first = self.next.fetchAdd(self.claim_batch, .monotonic);
                if (first >= self.results.len) return;
                const end = @min(first +| self.claim_batch, self.results.len);
                for (first..end) |index| self.execute(t, index);
            }
        }

        inline fn execute(self: *@This(), t: *Task, index: usize) void {
            const start = index * self.size + @min(index, self.extra);
            const chunk = Chunk{ .start = start, .end = start + self.size + @intFromBool(index < self.extra) };
            self.results[index] = t.call(Result, exec, Input{ .runner = self.runner, .chunk = chunk });
        }
    };
    var state = State{
        .runner = runner,
        .results = results,
        .size = count / results.len,
        .extra = count % results.len,
        .claim_batch = dynamicClaimBatch(results.len),
    };
    const Fut = core.Future(P.Context, *State, void);
    const futures = try allocator.alloc(Fut, lanes);
    defer allocator.free(futures);
    for (futures) |*future| future.initFork(task, State.run, &state);
    pool.kickstart(task.worker, lanes);
    futures[lanes - 1].joinOrCall(task, State.run);
    for (futures[0 .. lanes - 1]) |*future| future.joinOrCall(task, State.run);
}

fn runStaticLanes(
    pool: anytype,
    task: anytype,
    comptime Input: type,
    runner: anytype,
    count: usize,
    lanes: usize,
    results: anytype,
    allocator: std.mem.Allocator,
    comptime exec: anytype,
) anyerror!void {
    const P = @TypeOf(pool.*);
    const Task = P.TaskType;
    const Runner = @TypeOf(runner);
    const Result = @typeInfo(@TypeOf(results)).pointer.child;

    const State = struct {
        runner: Runner,
        results: []Result,
        size: usize,
        extra: usize,
        lanes: usize,

        fn execute(self: *@This(), t: *Task, index: usize) void {
            const start = index * self.size + @min(index, self.extra);
            const chunk = Chunk{ .start = start, .end = start + self.size + @intFromBool(index < self.extra) };
            self.results[index] = t.call(Result, exec, Input{ .runner = self.runner, .chunk = chunk });
        }

        fn runLane(self: *@This(), t: *Task, lane: usize) void {
            const size = self.results.len / self.lanes;
            const extra = self.results.len % self.lanes;
            var index = lane * size + @min(lane, extra);
            const end = index + size + @intFromBool(lane < extra);
            while (index < end) : (index += 1) self.execute(t, index);
        }
    };
    const LaneInput = struct { state: *State, lane: usize };
    const LaneExec = struct {
        fn run(t: *Task, input: LaneInput) void {
            input.state.runLane(t, input.lane);
        }
    };
    var state = State{
        .runner = runner,
        .results = results,
        .size = count / results.len,
        .extra = count % results.len,
        .lanes = lanes,
    };
    const Fut = core.Future(P.Context, LaneInput, void);
    const futures = try allocator.alloc(Fut, lanes);
    defer allocator.free(futures);
    for (futures, 0..) |*future, lane| {
        future.initFork(task, LaneExec.run, .{ .state = &state, .lane = lane });
    }
    pool.kickstart(task.worker, lanes);
    futures[lanes - 1].joinOrCall(task, LaneExec.run);
    for (futures[0 .. lanes - 1]) |*future| future.joinOrCall(task, LaneExec.run);
}

test "capped allocation failures release caller slots before invoking callbacks" {
    const Run = struct {
        fn range(_: *core.Worker(void), calls: *usize, _: Chunk) anyerror!void {
            calls.* += 1;
        }
        fn map(_: *core.Worker(void), _: void, index: usize) anyerror!u64 {
            return index;
        }
        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var pool = try core.Pool(void).init(failing.allocator(), std.testing.io, .{
        .workers = 3,
        .max_workers = 3,
        .max_callers = 1,
    });
    defer pool.deinit();
    try pool.start();
    if (pool.parallelWorkerCount() <= 2) return error.SkipZigTest;
    failing.fail_index = failing.alloc_index;
    var calls: usize = 0;
    // The range results fill the 4 KiB buffer, so lane-future allocation
    // fails. No jobs have been forked at the point either allocation fails.
    try std.testing.expectError(error.OutOfMemory, api.parallelForRange(&pool, &calls, 4096, .{
        .max_workers = 2,
        .chunks_per_worker = 1024,
        .serial_threshold = 0,
    }, Run.range));
    try std.testing.expectEqual(@as(usize, 0), calls);
    const caller = pool.claimCaller().?;
    pool.releaseCaller(caller);
    // The larger fold result array requires the fallback allocator itself.
    try std.testing.expectError(error.OutOfMemory, api.parallelFold(
        &pool,
        u64,
        {},
        4096,
        .{ .max_workers = 2, .chunks_per_worker = 512, .serial_threshold = 0 },
        0,
        Run.map,
        Run.combine,
    ));
    const again = pool.claimCaller().?;
    pool.releaseCaller(again);
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectEqual(@as(u64, 8386560), try api.parallelFold(
        &pool,
        u64,
        {},
        4096,
        .{ .max_workers = 2, .chunks_per_worker = 512, .serial_threshold = 0 },
        0,
        Run.map,
        Run.combine,
    ));
}

test "capped nested calls and cancellation drain their lane futures" {
    const n = 32;
    const State = struct {
        counts: [n]std.atomic.Value(u32) = [_]std.atomic.Value(u32){.init(0)} ** n,
        token: CancelToken = .{},

        fn inner(_: *core.Worker(void), self: *@This(), index: usize) anyerror!void {
            _ = self.counts[index].fetchAdd(1, .monotonic);
        }
        fn outer(w: *core.Worker(void), self: *@This(), _: usize) anyerror!void {
            try api.parallelFor(w.pool, self, n, .{ .max_workers = 2, .serial_threshold = 0 }, inner);
        }
        fn cancelling(_: *core.Worker(void), self: *@This(), index: usize) anyerror!void {
            if (index == 2) self.token.cancel();
        }
    };
    for ([_]usize{ 0, 3 }) |workers| {
        var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 2,
        });
        defer pool.deinit();
        try pool.start();
        var state = State{};
        try api.parallelFor(&pool, &state, n, .{ .max_workers = 2, .serial_threshold = 0 }, State.outer);
        for (state.counts) |count| try std.testing.expectEqual(@as(u32, n), count.load(.monotonic));
        try std.testing.expectError(error.Cancelled, api.parallelFor(&pool, &state, n, .{
            .max_workers = 2,
            .max_chunks = 8,
            .serial_threshold = 0,
            .cancel = &state.token,
        }, State.cancelling));
        const caller = pool.claimCaller().?;
        pool.releaseCaller(caller);
    }
}

test "parallelFold covers stack and heap dispatch storage" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 4,
        .max_workers = 4,
        .max_callers = 1,
        .max_execute_states = 512,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    const n = 4096;
    const Map = struct {
        fn map(_: *core.Worker(void), _: void, index: usize) anyerror!u64 {
            return index;
        }
    };
    const Add = struct {
        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    const expected = @as(u64, n - 1) * @as(u64, n) / 2;

    // The chunk results and lane futures fit in the stack fallback buffer.
    const stack_total = try api.parallelFold(
        &pool,
        u64,
        {},
        n,
        .{ .min_chunk = 64, .chunks_per_worker = 16, .serial_threshold = 0 },
        0,
        Map.map,
        Add.combine,
    );
    try std.testing.expectEqual(expected, stack_total);

    // The larger result array must use the pool allocator fallback.
    const heap_total = try api.parallelFold(
        &pool,
        u64,
        {},
        n,
        .{ .min_chunk = 1, .chunks_per_worker = 128, .serial_threshold = 0 },
        0,
        Map.map,
        Add.combine,
    );
    try std.testing.expectEqual(expected, heap_total);
}

test "uncancelled infallible fold fits 256 u64 results and lane futures on the stack" {
    const Run = struct {
        fn map(_: *core.Worker(void), _: void, index: usize) u64 {
            return index;
        }
        fn range(_: *core.Worker(void), _: void, chunk: Chunk) u64 {
            return (chunk.start + chunk.end - 1) * (chunk.end - chunk.start) / 2;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    for (0..5) |workers| {
        for ([_]usize{ 0, 16 }) |states| {
            var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
            var pool = try core.Pool(void).init(failing.allocator(), std.testing.io, .{
                .workers = workers,
                .max_workers = workers,
                .max_callers = 1,
                .max_execute_states = states,
            });
            defer pool.deinit();
            try pool.start();
            const allocated = failing.alloc_index;
            failing.fail_index = allocated;
            for (0..3) |_| {
                const result = try api.parallelFoldInfallible(&pool, u64, {}, 4096, .{
                    .min_chunk = 1,
                    .max_chunks = 256,
                    .chunks_per_worker = 256,
                    .serial_threshold = 0,
                }, 0, Run.map, Run.add);
                try std.testing.expectEqual(@as(u64, 8386560), result);
                try std.testing.expectEqual(allocated, failing.alloc_index);
                try std.testing.expect(!failing.has_induced_failure);
                const range_result = try api.parallelFoldRangeInfallible(&pool, u64, {}, 4096, .{
                    .min_chunk = 1,
                    .max_chunks = 256,
                    .chunks_per_worker = 256,
                    .serial_threshold = 0,
                }, 0, Run.range, Run.add);
                try std.testing.expectEqual(@as(u64, 8386560), range_result);
                try std.testing.expectEqual(allocated, failing.alloc_index);
                try std.testing.expect(!failing.has_induced_failure);
                const caller = pool.claimCaller().?;
                pool.releaseCaller(caller);
            }
        }
    }
}

test "infallible value dispatch allocation failures release caller before callbacks" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const Packet = struct { words: [8]u64 = @splat(0) };
    const Run = struct {
        fn map(_: *core.Worker(void), calls: *std.atomic.Value(usize), index: usize) u64 {
            _ = calls.fetchAdd(1, .monotonic);
            return index;
        }
        fn packet(w: *core.Worker(void), calls: *std.atomic.Value(usize), index: usize) Packet {
            return .{ .words = @splat(map(w, calls, index)) };
        }
        fn range(_: *core.Worker(void), calls: *std.atomic.Value(usize), chunk: Chunk) u64 {
            _ = calls.fetchAdd(1, .monotonic);
            return (chunk.start + chunk.end - 1) * (chunk.end - chunk.start) / 2;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
        fn combine(a: Packet, b: Packet) Packet {
            var result: Packet = undefined;
            for (&result.words, a.words, b.words) |*out, left, right| out.* = left + right;
            return result;
        }
    };
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var pool = try core.Pool(void).init(failing.allocator(), std.testing.io, .{
        .workers = 1,
        .max_workers = 1,
        .max_callers = 1,
    });
    defer pool.deinit();
    try pool.start();
    if (pool.parallelWorkerCount() < 2) return error.SkipZigTest;
    failing.fail_index = failing.alloc_index;
    var calls = std.atomic.Value(usize).init(0);
    try std.testing.expectError(error.OutOfMemory, api.parallelFoldInfallible(&pool, u64, &calls, 4096, .{
        .min_chunk = 1,
        .max_chunks = 1024,
        .chunks_per_worker = 1024,
        .serial_threshold = 0,
    }, 0, Run.map, Run.add));
    try std.testing.expectEqual(@as(usize, 0), calls.load(.monotonic));
    const caller = pool.claimCaller().?;
    pool.releaseCaller(caller);
    try std.testing.expectError(error.OutOfMemory, api.parallelFoldRangeInfallible(&pool, u64, &calls, 4096, .{
        .min_chunk = 1,
        .max_chunks = 1024,
        .chunks_per_worker = 1024,
        .serial_threshold = 0,
    }, 0, Run.range, Run.add));
    try std.testing.expectEqual(@as(usize, 0), calls.load(.monotonic));
    const after_range = pool.claimCaller().?;
    pool.releaseCaller(after_range);
    // The value array fits exactly; allocation of lane futures must fail.
    try std.testing.expectError(error.OutOfMemory, api.parallelFoldInfallible(&pool, Packet, &calls, 64, .{
        .min_chunk = 1,
        .max_chunks = 64,
        .chunks_per_worker = 64,
        .serial_threshold = 0,
    }, .{}, Run.packet, Run.combine));
    try std.testing.expectEqual(@as(usize, 0), calls.load(.monotonic));
    const again = pool.claimCaller().?;
    pool.releaseCaller(again);
    failing.fail_index = std.math.maxInt(usize);
    const result = try api.parallelFoldInfallible(&pool, Packet, &calls, 64, .{
        .min_chunk = 1,
        .max_chunks = 64,
        .chunks_per_worker = 64,
        .serial_threshold = 0,
    }, .{}, Run.packet, Run.combine);
    try std.testing.expectEqual(@as(usize, 64), calls.load(.monotonic));
    for (result.words) |word| try std.testing.expectEqual(@as(u64, 2016), word);
}
