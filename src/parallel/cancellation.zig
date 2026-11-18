//! Cooperative cancellation checkpoints for flat callbacks and reduction.

const std = @import("std");
const builtin = @import("builtin");
const core = @import("../core.zig");
const api = @import("../parallel.zig");
const types = @import("types.zig");
const Chunk = types.Chunk;
const Options = types.Options;
const CancelToken = @import("../cancel.zig").CancelToken;

pub const cancel_block = 4096;

pub inline fn checkCancel(token: ?*CancelToken) anyerror!void {
    if (token) |t| {
        if (t.isCancelled()) return error.Cancelled;
    }
}

test "final callback cancellation is observed across flat APIs and serial fallbacks" {
    const State = struct {
        token: CancelToken = .{},
        calls: usize = 0,
        fn visit(self: *@This(), index: usize) void {
            self.calls += 1;
            if (index == 63) self.token.cancel();
        }
        fn item(_: *core.Worker(void), self: *@This(), index: usize) anyerror!void {
            self.visit(index);
        }
        fn cell(_: *core.Worker(void), self: *@This(), row: usize, col: usize) anyerror!void {
            self.visit(row * 8 + col);
        }
        fn range(_: *core.Worker(void), self: *@This(), chunk: Chunk) anyerror!void {
            for (chunk.start..chunk.end) |index| self.visit(index);
        }
        fn map(_: *core.Worker(void), self: *@This(), index: usize) anyerror!u64 {
            self.visit(index);
            return index;
        }
        fn value(_: *core.Worker(void), self: *@This(), index: usize) u64 {
            self.visit(index);
            return index;
        }
        fn rangeMap(_: *core.Worker(void), self: *@This(), chunk: Chunk) anyerror!u64 {
            var total: u64 = 0;
            for (chunk.start..chunk.end) |index| {
                self.visit(index);
                total += index;
            }
            return total;
        }
        fn rangeValue(_: *core.Worker(void), self: *@This(), chunk: Chunk) u64 {
            var total: u64 = 0;
            for (chunk.start..chunk.end) |index| {
                self.visit(index);
                total += index;
            }
            return total;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
        fn reset(self: *@This()) void {
            self.token.reset();
            self.calls = 0;
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
        for (0..3) |mode| {
            const held = if (mode == 2) pool.claimCaller().? else null;
            defer if (held) |caller| pool.releaseCaller(caller);
            var state = State{};
            const options = Options{
                .max_chunks = 1,
                .max_workers = 1,
                .serial_threshold = if (mode == 1) 4096 else 0,
                .cancel = &state.token,
            };
            try std.testing.expectError(error.Cancelled, api.parallelFor(&pool, &state, 64, options, State.item));
            try std.testing.expectEqual(@as(usize, 64), state.calls);
            state.reset();
            try std.testing.expectError(error.Cancelled, api.parallelForRange(&pool, &state, 64, options, State.range));
            try std.testing.expectEqual(@as(usize, 64), state.calls);
            state.reset();
            try std.testing.expectError(error.Cancelled, api.parallelFor2D(&pool, &state, 8, 8, options, State.cell));
            try std.testing.expectEqual(@as(usize, 64), state.calls);
            state.reset();
            try std.testing.expectError(error.Cancelled, api.parallelFold(&pool, u64, &state, 64, options, 0, State.map, State.add));
            try std.testing.expectEqual(@as(usize, 64), state.calls);
            state.reset();
            try std.testing.expectError(error.Cancelled, api.parallelFoldInfallible(&pool, u64, &state, 64, options, 0, State.value, State.add));
            try std.testing.expectEqual(@as(usize, 64), state.calls);
            state.reset();
            try std.testing.expectError(error.Cancelled, api.parallelFoldRange(&pool, u64, &state, 64, options, 0, State.rangeMap, State.add));
            try std.testing.expectEqual(@as(usize, 64), state.calls);
            state.reset();
            try std.testing.expectError(error.Cancelled, api.parallelFoldRangeInfallible(&pool, u64, &state, 64, options, 0, State.rangeValue, State.add));
            try std.testing.expectEqual(@as(usize, 64), state.calls);
        }
    }
}

test "cancellation from final ordered reduction is observed" {
    const Count = struct {
        items: usize,
        token: *CancelToken,
        fn map(_: *core.Worker(void), token: *CancelToken, _: usize) @This() {
            return .{ .items = 1, .token = token };
        }
        fn fallible(w: *core.Worker(void), token: *CancelToken, index: usize) anyerror!@This() {
            return map(w, token, index);
        }
        fn range(_: *core.Worker(void), token: *CancelToken, chunk: Chunk) @This() {
            return .{ .items = chunk.end - chunk.start, .token = token };
        }
        fn rangeFallible(w: *core.Worker(void), token: *CancelToken, chunk: Chunk) anyerror!@This() {
            return range(w, token, chunk);
        }
        fn combine(a: @This(), b: @This()) @This() {
            const result = @This(){ .items = a.items + b.items, .token = a.token };
            if (result.items == 64) result.token.cancel();
            return result;
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
        var token = CancelToken{};
        const options = Options{ .max_chunks = 4, .chunks_per_worker = 4, .serial_threshold = 0, .cancel = &token };
        const identity = Count{ .items = 0, .token = &token };
        try std.testing.expectError(error.Cancelled, api.parallelFold(&pool, Count, &token, 64, options, identity, Count.fallible, Count.combine));
        token.reset();
        try std.testing.expectError(error.Cancelled, api.parallelReduceInfallible(&pool, Count, &token, 64, options, identity, Count.map, Count.combine));
        token.reset();
        try std.testing.expectError(error.Cancelled, api.parallelFoldRange(&pool, Count, &token, 64, options, identity, Count.rangeFallible, Count.combine));
        token.reset();
        try std.testing.expectError(error.Cancelled, api.parallelFoldRangeInfallible(&pool, Count, &token, 64, options, identity, Count.range, Count.combine));
    }
}

test "callback errors retain chunk-index precedence over exit cancellation" {
    const State = struct {
        token: CancelToken = .{},
        cancel_with_error: bool,
        fn item(_: *core.Worker(void), self: *@This(), index: usize) anyerror!void {
            if (index == 0) {
                if (self.cancel_with_error) self.token.cancel();
                return error.FirstChunkFailure;
            }
            self.token.cancel();
        }
        fn map(w: *core.Worker(void), self: *@This(), index: usize) anyerror!u64 {
            try item(w, self, index);
            return index;
        }
        fn rangeMap(w: *core.Worker(void), self: *@This(), chunk: Chunk) anyerror!u64 {
            try item(w, self, chunk.start);
            return chunk.start;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
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
        for ([_]bool{ false, true }) |same_callback| {
            for ([_]usize{ 0, 4096 }) |threshold| {
                var state = State{ .cancel_with_error = same_callback };
                const options = Options{ .max_workers = 1, .max_chunks = 2, .chunks_per_worker = 2, .serial_threshold = threshold, .cancel = &state.token };
                try std.testing.expectError(error.FirstChunkFailure, api.parallelFor(&pool, &state, 2, options, State.item));
                state.token.reset();
                try std.testing.expectError(error.FirstChunkFailure, api.parallelFold(&pool, u64, &state, 2, options, 0, State.map, State.add));
                state.token.reset();
                try std.testing.expectError(error.FirstChunkFailure, api.parallelFoldRange(&pool, u64, &state, 2, options, 0, State.rangeMap, State.add));
            }
        }
    }
}

test "cancelled calls drain callbacks and select errors by chunk index" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const State = struct {
        token: CancelToken = .{},
        started: std.atomic.Value(usize) = .init(0),
        finished: std.atomic.Value(usize) = .init(0),
        release: std.atomic.Value(bool) = .init(false),
        fail_first: bool,
        fn run(w: *core.Worker(void), self: *@This(), index: usize) anyerror!void {
            _ = self.started.fetchAdd(1, .acq_rel);
            defer _ = self.finished.fetchAdd(1, .release);
            if (index == 0) {
                while (!self.release.load(.acquire)) std.atomic.spinLoopHint();
                try w.pool.io.sleep(std.Io.Duration.fromMilliseconds(2), .awake);
                if (self.fail_first) return error.FirstChunkFailure;
            } else {
                while (self.started.load(.acquire) != 2) std.atomic.spinLoopHint();
                self.token.cancel();
                self.release.store(true, .release);
            }
        }
    };
    var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
        .workers = 1,
        .max_workers = 1,
        .max_callers = 1,
        .max_execute_states = 8,
    });
    defer pool.deinit();
    try pool.start();
    if (pool.parallelWorkerCount() != 2) return error.SkipZigTest;
    for ([_]bool{ false, true }) |fail_first| {
        for (0..10) |_| {
            var state = State{ .fail_first = fail_first };
            const expected = if (fail_first) error.FirstChunkFailure else error.Cancelled;
            try std.testing.expectError(expected, api.parallelFor(&pool, &state, 2, .{
                .max_chunks = 2,
                .chunks_per_worker = 1,
                .serial_threshold = 0,
                .cancel = &state.token,
            }, State.run));
            try std.testing.expectEqual(@as(usize, 2), state.finished.load(.acquire));
            const caller = pool.claimCaller().?;
            pool.releaseCaller(caller);
        }
    }
}

test "parallelFor returns Cancelled for an already-cancelled token" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 1,
        .max_execute_states = 128,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    var token = CancelToken{};
    token.cancel();
    const Ctx = struct {
        fn run(_: *core.Worker(void), _: void, _: usize) anyerror!void {}
    };
    try std.testing.expectError(
        error.Cancelled,
        api.parallelFor(&pool, {}, 10_000, .{
            .min_chunk = 16,
            .serial_threshold = 0,
            .cancel = &token,
        }, Ctx.run),
    );
}

test "parallelFold cancels from a callback" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 1,
        .max_execute_states = 128,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    var token = CancelToken{};
    const Ctx = struct {
        token: *CancelToken,
        fn map(_: *core.Worker(void), ctx: *@This(), index: usize) anyerror!u64 {
            if (index == 100) ctx.token.cancel();
            return index;
        }
    };
    var ctx = Ctx{ .token = &token };
    const Add = struct {
        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    try std.testing.expectError(
        error.Cancelled,
        api.parallelFold(&pool, u64, &ctx, 10_000, .{
            .min_chunk = 1,
            .chunks_per_worker = 1,
            .serial_threshold = 0,
            .cancel = &token,
        }, 0, Ctx.map, Add.combine),
    );
}

test "parallelFoldInfallible honors cancellation" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 1,
        .max_execute_states = 128,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    var token = CancelToken{};
    const Ctx = struct {
        token: *CancelToken,
        fn map(_: *core.Worker(void), ctx: *@This(), index: usize) u64 {
            if (index == 100) ctx.token.cancel();
            return index;
        }
    };
    var ctx = Ctx{ .token = &token };
    const Add = struct {
        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    try std.testing.expectError(
        error.Cancelled,
        api.parallelFoldInfallible(&pool, u64, &ctx, 10_000, .{
            .min_chunk = 1,
            .chunks_per_worker = 1,
            .serial_threshold = 0,
            .cancel = &token,
        }, 0, Ctx.map, Add.combine),
    );
}

test "serial fold honors cancellation" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 1,
        .max_execute_states = 128,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    var token = CancelToken{};
    token.cancel();
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
    try std.testing.expectError(
        error.Cancelled,
        api.parallelFold(&pool, u64, {}, 100, .{
            .min_chunk = 1,
            .serial_threshold = 1000,
            .cancel = &token,
        }, 0, Map.map, Add.combine),
    );
}

test "parallelFor cancellation from another thread" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 4,
        .max_workers = 4,
        .max_callers = 1,
        .max_execute_states = 256,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    var token = CancelToken{};
    const Canceller = struct {
        fn run(t: *CancelToken, thread_io: std.Io) void {
            thread_io.sleep(
                std.Io.Duration.fromNanoseconds(100 * std.time.ns_per_us),
                .awake,
            ) catch {};
            t.cancel();
        }
    };
    const thread = try std.Thread.spawn(.{}, Canceller.run, .{ &token, io });

    const Ctx = struct {
        fn run(_: *core.Worker(void), _: void, _: usize) anyerror!void {
            std.atomic.spinLoopHint();
        }
    };
    if (api.parallelFor(&pool, {}, 1_000_000, .{
        .min_chunk = 1,
        .serial_threshold = 0,
        .cancel = &token,
    }, Ctx.run)) |_| {} else |err| {
        try std.testing.expectEqual(error.Cancelled, err);
    }
    thread.join();
}
