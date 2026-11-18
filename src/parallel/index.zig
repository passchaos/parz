//! Direct index, slice and row-major grid callbacks.

const std = @import("std");
const core = @import("../core.zig");
const types = @import("types.zig");
const Chunk = types.Chunk;
const Options = types.Options;
const CancelToken = @import("../cancel.zig").CancelToken;
const executor_mod = @import("executor.zig");
const parallelForRange = @import("range.zig").parallelForRange;
const checkCancel = @import("cancellation.zig").checkCancel;
const cancel_block = @import("cancellation.zig").cancel_block;

/// Parallel loop over `[0, count)`.
pub fn parallelFor(
    executor: anytype,
    shared: anytype,
    count: usize,
    options: Options,
    comptime run: anytype,
) anyerror!void {
    const pool = executor_mod.getPool(executor);
    const P = @TypeOf(pool.*);
    const W = P.WorkerType;
    const Shared = @TypeOf(shared);

    const IndexRunner = struct {
        shared: *const Shared,
        cancel: ?*CancelToken,

        fn range(w: *W, self: *@This(), chunk: Chunk) anyerror!void {
            var i = chunk.start;
            while (i < chunk.end) {
                try checkCancel(self.cancel);
                const block_end = @min(i +| cancel_block, chunk.end);
                while (i < block_end) : (i += 1) {
                    // Call the comptime callback directly so the per-item call
                    // is inlined instead of going through a function pointer.
                    try run(w, self.shared.*, i);
                }
            }
        }
    };

    var runner = IndexRunner{ .shared = &shared, .cancel = options.cancel };
    return parallelForRange(executor, &runner, count, options, IndexRunner.range);
}

/// Parallel loop over a slice. The callback receives the slice and an index.
pub fn parallelForEach(
    executor: anytype,
    slice: anytype,
    options: Options,
    comptime run: anytype,
) anyerror!void {
    return parallelFor(executor, slice, slice.len, options, run);
}

/// Parallel loop over a row-major `rows x cols` grid. The callback receives
/// `(row, col)` and every cell is visited exactly once.
pub fn parallelFor2D(
    executor: anytype,
    shared: anytype,
    rows: usize,
    cols: usize,
    options: Options,
    comptime run: anytype,
) anyerror!void {
    const pool = executor_mod.getPool(executor);
    if (rows == 0 or cols == 0) return;
    const total = std.math.mul(usize, rows, cols) catch return error.Overflow;

    const P = @TypeOf(pool.*);
    const W = P.WorkerType;
    const Shared = @TypeOf(shared);

    const Runner = struct {
        shared: *const Shared,
        cols: usize,
        cancel: ?*CancelToken,

        fn range(w: *W, self: *@This(), chunk: Chunk) anyerror!void {
            // Convert the flat chunk offset to row/col once, then advance
            // with increments instead of dividing for every cell.
            var i = chunk.start;
            var row = i / self.cols;
            var col = i % self.cols;
            while (i < chunk.end) {
                try checkCancel(self.cancel);
                const block_end = @min(i +| cancel_block, chunk.end);
                while (i < block_end) : (i += 1) {
                    try run(w, self.shared.*, row, col);
                    col += 1;
                    if (col == self.cols) {
                        col = 0;
                        row += 1;
                    }
                }
            }
        }
    };

    var runner = Runner{
        .shared = &shared,
        .cols = cols,
        .cancel = options.cancel,
    };
    return parallelForRange(executor, &runner, total, options, Runner.range);
}

test "parallelFor covers every index exactly once" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 2,
        .max_execute_states = 64,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    const n = 257;
    var counts = [_]std.atomic.Value(u32){.init(0)} ** n;

    const Ctx = struct {
        fn run(_: *core.Worker(void), shared: *[n]std.atomic.Value(u32), index: usize) anyerror!void {
            _ = shared[index].fetchAdd(1, .monotonic);
        }
    };

    try parallelFor(&pool, &counts, n, .{ .min_chunk = 1, .chunks_per_worker = 4, .serial_threshold = 0 }, Ctx.run);
    for (counts) |count| {
        try std.testing.expectEqual(@as(u32, 1), count.load(.monotonic));
    }
}

test "nested parallelFor" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 2,
        .max_execute_states = 64,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    const n = 32;
    var counts = [_]std.atomic.Value(u32){.init(0)} ** n;

    const Outer = struct {
        fn run(w: *core.Worker(void), shared: *[n]std.atomic.Value(u32), _: usize) anyerror!void {
            const Inner = struct {
                fn run(
                    _: *core.Worker(void),
                    inner_shared: *[n]std.atomic.Value(u32),
                    inner_index: usize,
                ) anyerror!void {
                    _ = inner_shared[inner_index].fetchAdd(1, .monotonic);
                }
            };
            try parallelFor(w.pool, shared, n, .{ .min_chunk = 1, .serial_threshold = 0 }, Inner.run);
        }
    };

    try parallelFor(&pool, &counts, n, .{ .min_chunk = 1, .serial_threshold = 0 }, Outer.run);
    for (counts) |count| {
        try std.testing.expectEqual(@as(u32, n), count.load(.monotonic));
    }
}

test "parallelFor returns the first error by index" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 2,
        .max_execute_states = 64,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    const Ctx = struct {
        fn run(_: *core.Worker(void), _: void, index: usize) anyerror!void {
            if (index == 3) return error.FirstFailure;
            if (index == 9) return error.SecondFailure;
        }
    };

    try std.testing.expectError(
        error.FirstFailure,
        parallelFor(&pool, {}, 64, .{ .min_chunk = 1, .serial_threshold = 0 }, Ctx.run),
    );
}

test "parallelFor2D covers every cell exactly once" {
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

    const rows = 17;
    const cols = 31;
    const n = rows * cols;
    var counts = [_]std.atomic.Value(u32){.init(0)} ** n;
    const Ctx = struct {
        fn run(
            _: *core.Worker(void),
            shared: *[n]std.atomic.Value(u32),
            row: usize,
            col: usize,
        ) anyerror!void {
            _ = shared[row * cols + col].fetchAdd(1, .monotonic);
        }
    };
    try parallelFor2D(&pool, &counts, rows, cols, .{
        .min_chunk = 1,
        .serial_threshold = 0,
    }, Ctx.run);
    for (counts) |count| {
        try std.testing.expectEqual(@as(u32, 1), count.load(.monotonic));
    }
}

test "parallelFor2D handles empty dimensions and overflow" {
    const io = std.testing.io;
    var pool = try core.Pool(void).init(std.testing.allocator, io, .{
        .workers = 1,
        .max_workers = 1,
        .max_callers = 1,
        .max_execute_states = 16,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    const Ctx = struct {
        fn run(_: *core.Worker(void), _: void, _: usize, _: usize) anyerror!void {
            unreachable;
        }
    };

    try parallelFor2D(&pool, {}, 0, 10, .{ .serial_threshold = 0 }, Ctx.run);
    try parallelFor2D(&pool, {}, 10, 0, .{ .serial_threshold = 0 }, Ctx.run);
    try std.testing.expectError(
        error.Overflow,
        parallelFor2D(&pool, {}, std.math.maxInt(usize), 2, .{ .serial_threshold = 0 }, Ctx.run),
    );
}
