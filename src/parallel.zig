//! Flat parallel loop / fold APIs on top of the heartbeat scheduler.
//!
//! These APIs intentionally use direct callbacks instead of a composable
//! Rayon-style iterator. Every chunk owns a disjoint range; results are
//! combined in chunk-index order, so the output does not depend on which
//! worker ran which chunk.

const std = @import("std");
const core = @import("core.zig");
const Job = @import("job.zig").Job;
const CancelToken = @import("cancel.zig").CancelToken;

const cancel_block = 4096;

inline fn checkCancel(token: ?*CancelToken) anyerror!void {
    if (token) |t| {
        if (t.isCancelled()) return error.Cancelled;
    }
}

pub const Chunk = struct {
    start: usize,
    end: usize,
};

pub const Options = struct {
    /// Minimum number of logical items per chunk.
    min_chunk: usize = 1,
    /// Hard upper bound on chunks for one call.
    max_chunks: usize = 4096,
    /// Target chunks per available lane. More chunks improve load balance on
    /// heterogeneous CPUs; the flat APIs share the whole chunk list up front,
    /// so this is no longer a wake-up batching knob.
    chunks_per_worker: usize = 16,
    /// Per-call worker cap. 0 uses all available lanes.
    max_workers: usize = 0,
    /// Run serially below this item count. A flat call with fewer items than
    /// this is almost always dominated by caller-slot setup, future
    /// allocation, and worker wake-up cost. Set to 0 to force parallelism.
    serial_threshold: usize = 4096,
    /// Optional cooperative cancellation token. It is checked at chunk
    /// boundaries and every 4096 items inside a chunk.
    cancel: ?*CancelToken = null,
};

/// Parallel loop over `[0, count)`.
pub fn parallelFor(
    pool: anytype,
    shared: anytype,
    count: usize,
    options: Options,
    comptime run: anytype,
) anyerror!void {
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
                const block_end = @min(i + cancel_block, chunk.end);
                while (i < block_end) : (i += 1) {
                    // Call the comptime callback directly so the per-item call
                    // is inlined instead of going through a function pointer.
                    try run(w, self.shared.*, i);
                }
            }
        }
    };

    var runner = IndexRunner{ .shared = &shared, .cancel = options.cancel };
    return parallelForRange(pool, &runner, count, options, IndexRunner.range);
}

/// Parallel loop over a slice. The callback receives the slice and an index.
pub fn parallelForEach(
    pool: anytype,
    slice: anytype,
    options: Options,
    comptime run: anytype,
) anyerror!void {
    return parallelFor(pool, slice, slice.len, options, run);
}

/// Parallel loop over a row-major `rows x cols` grid. The callback receives
/// `(row, col)` and every cell is visited exactly once.
pub fn parallelFor2D(
    pool: anytype,
    shared: anytype,
    rows: usize,
    cols: usize,
    options: Options,
    comptime run: anytype,
) anyerror!void {
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
            var i = chunk.start;
            while (i < chunk.end) {
                try checkCancel(self.cancel);
                const block_end = @min(i + cancel_block, chunk.end);
                while (i < block_end) : (i += 1) {
                    try run(w, self.shared.*, i / self.cols, i % self.cols);
                }
            }
        }
    };

    var runner = Runner{
        .shared = &shared,
        .cols = cols,
        .cancel = options.cancel,
    };
    return parallelForRange(pool, &runner, total, options, Runner.range);
}

/// Parallel loop over half-open ranges. The callback receives one chunk.
pub fn parallelForRange(
    pool: anytype,
    shared: anytype,
    count: usize,
    options: Options,
    comptime run: anytype,
) anyerror!void {
    if (count == 0) return;

    const P = @TypeOf(pool.*);
    const Ctx = P.Context;
    const T = P.TaskType;
    const Shared = @TypeOf(shared);

    const Runner = struct {
        shared: *const Shared,
        cancel: ?*CancelToken,
    };
    const Input = struct {
        runner: *Runner,
        chunk: Chunk,
    };
    const Fut = core.Future(Ctx, Input, anyerror!void);
    const Exec = struct {
        fn exec(t: *T, input: Input) anyerror!void {
            try checkCancel(input.runner.cancel);
            try run(t.worker, input.runner.shared.*, input.chunk);
        }
    };

    var runner = Runner{ .shared = &shared, .cancel = options.cancel };
    if (shouldRunSerial(count, options, pool.parallelWorkerCount())) {
        return serialRange(pool, shared, count, options.cancel, run);
    }
    const caller = pool.claimCaller() orelse {
        return serialRange(pool, shared, count, options.cancel, run);
    };
    defer pool.releaseCaller(caller);
    var task = caller.begin();

    const chunk_count = plannedChunkCount(count, options, pool.parallelWorkerCount());
    // Keep small flat calls allocation-free. The stack buffer is capped at
    // ~4 KiB; larger calls use the pool allocator.
    const stack_future_count = @min(64, @max(1, 4096 / @sizeOf(Fut)));
    var stack_futures: [stack_future_count]Fut = undefined;
    const futures = if (chunk_count <= stack_future_count)
        stack_futures[0..chunk_count]
    else
        try pool.allocator.alloc(Fut, chunk_count);
    defer if (chunk_count > stack_future_count) pool.allocator.free(futures);

    const chunk_size = (count + chunk_count - 1) / chunk_count;
    for (futures, 0..) |*fut, index| {
        fut.* = .{};
        const start = index * chunk_size;
        const end = @min(start + chunk_size, count);
        fut.fork(&task, Exec.exec, .{
            .runner = &runner,
            .chunk = .{ .start = start, .end = end },
        });
    }
    pool.kickstart(caller, chunk_count);

    for (futures) |*fut| {
        switch (fut.job.state()) {
            .pending => {},
            .queued_local => {
                _ = fut.join(&task);
                fut.output = task.call(anyerror!void, Exec.exec, fut.input);
            },
            .queued_shared, .executing => {
                if (fut.join(&task)) |value| {
                    fut.output = value;
                } else {
                    fut.output = task.call(anyerror!void, Exec.exec, fut.input);
                }
            },
        }
    }

    for (futures) |*fut| {
        if (fut.output) |_| {} else |err| return err;
    }
}

/// Deterministic ordered fold. Each chunk accumulates with `combine`; the
/// caller then combines chunk results in index order. `map` may fail.
pub fn parallelFold(
    pool: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    if (count == 0) return identity;

    const P = @TypeOf(pool.*);
    const Ctx = P.Context;
    const Tm = P.TaskType;
    const Shared = @TypeOf(shared);

    const Runner = struct {
        shared: *const Shared,
        identity: T,
        cancel: ?*CancelToken,
    };
    const Input = struct {
        runner: *Runner,
        chunk: Chunk,
    };
    const Fut = core.Future(Ctx, Input, anyerror!T);
    const Exec = struct {
        fn exec(t: *Tm, input: Input) anyerror!T {
            const runner = input.runner;
            var acc = runner.identity;
            var i = input.chunk.start;
            while (i < input.chunk.end) {
                try checkCancel(runner.cancel);
                const block_end = @min(i + cancel_block, input.chunk.end);
                while (i < block_end) : (i += 1) {
                    acc = combine(acc, try map(t.worker, runner.shared.*, i));
                }
            }
            return acc;
        }
    };

    var runner = Runner{
        .shared = &shared,
        .identity = identity,
        .cancel = options.cancel,
    };
    if (shouldRunSerial(count, options, pool.parallelWorkerCount())) {
        return serialFold(pool, T, shared, count, options.cancel, identity, map, combine);
    }
    const caller = pool.claimCaller() orelse {
        return serialFold(pool, T, shared, count, options.cancel, identity, map, combine);
    };
    defer pool.releaseCaller(caller);
    var task = caller.begin();

    const chunk_count = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const stack_future_count = @min(64, @max(1, 4096 / @sizeOf(Fut)));
    var stack_futures: [stack_future_count]Fut = undefined;
    const futures = if (chunk_count <= stack_future_count)
        stack_futures[0..chunk_count]
    else
        try pool.allocator.alloc(Fut, chunk_count);
    defer if (chunk_count > stack_future_count) pool.allocator.free(futures);

    const chunk_size = (count + chunk_count - 1) / chunk_count;
    for (futures, 0..) |*fut, index| {
        fut.* = .{};
        const start = index * chunk_size;
        const end = @min(start + chunk_size, count);
        fut.fork(&task, Exec.exec, .{
            .runner = &runner,
            .chunk = .{ .start = start, .end = end },
        });
    }
    pool.kickstart(caller, chunk_count);

    for (futures) |*fut| {
        switch (fut.job.state()) {
            .pending => {},
            .queued_local => {
                _ = fut.join(&task);
                fut.output = task.call(anyerror!T, Exec.exec, fut.input);
            },
            .queued_shared, .executing => {
                if (fut.join(&task)) |value| {
                    fut.output = value;
                } else {
                    fut.output = task.call(anyerror!T, Exec.exec, fut.input);
                }
            },
        }
    }

    var total = identity;
    for (futures) |*fut| {
        if (fut.output) |value| {
            total = combine(total, value);
        } else |err| return err;
    }
    return total;
}

/// Deterministic ordered fold for an infallible `map`. The chunk loop has no
/// per-item error-union check.
pub fn parallelFoldInfallible(
    pool: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    if (count == 0) return identity;

    const P = @TypeOf(pool.*);
    const Ctx = P.Context;
    const Tm = P.TaskType;
    const Shared = @TypeOf(shared);

    const Runner = struct {
        shared: *const Shared,
        identity: T,
        cancel: ?*CancelToken,
    };
    const Input = struct {
        runner: *Runner,
        chunk: Chunk,
    };
    const Fut = core.Future(Ctx, Input, anyerror!T);
    const Exec = struct {
        fn exec(t: *Tm, input: Input) anyerror!T {
            const runner = input.runner;
            var acc = runner.identity;
            var i = input.chunk.start;
            while (i < input.chunk.end) {
                try checkCancel(runner.cancel);
                const block_end = @min(i + cancel_block, input.chunk.end);
                while (i < block_end) : (i += 1) {
                    acc = combine(acc, map(t.worker, runner.shared.*, i));
                }
            }
            return acc;
        }
    };

    var runner = Runner{
        .shared = &shared,
        .identity = identity,
        .cancel = options.cancel,
    };
    if (shouldRunSerial(count, options, pool.parallelWorkerCount())) {
        return serialFoldInfallible(pool, T, shared, count, options.cancel, identity, map, combine);
    }
    const caller = pool.claimCaller() orelse {
        return serialFoldInfallible(pool, T, shared, count, options.cancel, identity, map, combine);
    };
    defer pool.releaseCaller(caller);
    var task = caller.begin();

    const chunk_count = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const stack_future_count = @min(64, @max(1, 4096 / @sizeOf(Fut)));
    var stack_futures: [stack_future_count]Fut = undefined;
    const futures = if (chunk_count <= stack_future_count)
        stack_futures[0..chunk_count]
    else
        try pool.allocator.alloc(Fut, chunk_count);
    defer if (chunk_count > stack_future_count) pool.allocator.free(futures);

    const chunk_size = (count + chunk_count - 1) / chunk_count;
    for (futures, 0..) |*fut, index| {
        fut.* = .{};
        const start = index * chunk_size;
        const end = @min(start + chunk_size, count);
        fut.fork(&task, Exec.exec, .{
            .runner = &runner,
            .chunk = .{ .start = start, .end = end },
        });
    }
    pool.kickstart(caller, chunk_count);

    for (futures) |*fut| {
        switch (fut.job.state()) {
            .pending => {},
            .queued_local => {
                _ = fut.join(&task);
                fut.output = task.call(anyerror!T, Exec.exec, fut.input);
            },
            .queued_shared, .executing => {
                if (fut.join(&task)) |value| {
                    fut.output = value;
                } else {
                    fut.output = task.call(anyerror!T, Exec.exec, fut.input);
                }
            },
        }
    }

    var total = identity;
    for (futures) |*fut| {
        if (fut.output) |value| {
            total = combine(total, value);
        } else |err| return err;
    }
    return total;
}

pub fn parallelReduce(
    pool: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    return parallelFold(pool, T, shared, count, options, identity, map, combine);
}

pub fn parallelReduceInfallible(
    pool: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    return parallelFoldInfallible(pool, T, shared, count, options, identity, map, combine);
}

fn plannedLaneCount(options: Options, worker_count: usize) usize {
    const requested_lanes = if (options.max_workers == 0)
        worker_count
    else
        @min(options.max_workers, worker_count);
    return @max(requested_lanes, 1);
}

fn plannedChunkCount(count: usize, options: Options, worker_count: usize) usize {
    if (count == 0) return 0;
    const min_chunk = @max(options.min_chunk, 1);
    const by_chunk = (count + min_chunk - 1) / min_chunk;
    const lanes = plannedLaneCount(options, worker_count);
    const by_lanes = lanes * @max(options.chunks_per_worker, 1);
    const cap = @max(options.max_chunks, 1);
    return @max(1, @min(@min(by_chunk, by_lanes), cap));
}

/// Small flat calls are dominated by caller-slot setup, future allocation and
/// worker wake-up. Run them on the caller instead. A call that cannot produce
/// at least one chunk per lane cannot use the pool effectively either.
fn shouldRunSerial(count: usize, options: Options, worker_count: usize) bool {
    if (options.serial_threshold == 0) return false;
    if (count < options.serial_threshold) return true;
    return plannedChunkCount(count, options, worker_count) <
        plannedLaneCount(options, worker_count);
}

fn serialRange(
    pool: anytype,
    shared: anytype,
    count: usize,
    cancel: ?*CancelToken,
    comptime run: anytype,
) anyerror!void {
    const P = @TypeOf(pool.*);
    const W = P.WorkerType;
    var ctx = try pool.createTempContext();
    defer pool.destroyTempContext(&ctx);
    var temp = W{ .pool = pool, .index = 0, .active = false, .ctx = ctx };
    try checkCancel(cancel);
    try run(&temp, shared, .{ .start = 0, .end = count });
}

fn serialFold(
    pool: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    cancel: ?*CancelToken,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    const P = @TypeOf(pool.*);
    const W = P.WorkerType;
    var ctx = try pool.createTempContext();
    defer pool.destroyTempContext(&ctx);
    var temp = W{ .pool = pool, .index = 0, .active = false, .ctx = ctx };
    var total = identity;
    var i: usize = 0;
    while (i < count) {
        try checkCancel(cancel);
        const block_end = @min(i + cancel_block, count);
        while (i < block_end) : (i += 1) {
            total = combine(total, try map(&temp, shared, i));
        }
    }
    return total;
}

fn serialFoldInfallible(
    pool: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    cancel: ?*CancelToken,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    const P = @TypeOf(pool.*);
    const W = P.WorkerType;
    var ctx = try pool.createTempContext();
    defer pool.destroyTempContext(&ctx);
    var temp = W{ .pool = pool, .index = 0, .active = false, .ctx = ctx };
    var total = identity;
    var i: usize = 0;
    while (i < count) {
        try checkCancel(cancel);
        const block_end = @min(i + cancel_block, count);
        while (i < block_end) : (i += 1) {
            total = combine(total, map(&temp, shared, i));
        }
    }
    return total;
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

test "parallelFold is deterministic and ordered" {
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

    const n = 1000;
    const Map = struct {
        fn map(_: *core.Worker(void), _: void, index: usize) anyerror!u64 {
            return index;
        }
    };
    const Combine = struct {
        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };

    const total = try parallelFold(&pool, u64, {}, n, .{ .min_chunk = 1, .serial_threshold = 0 }, 0, Map.map, Combine.combine);
    const expected = @as(u64, n - 1) * @as(u64, n) / 2;
    try std.testing.expectEqual(expected, total);
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
    try parallelFor(&pool, &sum, 100, .{ .min_chunk = 1 }, Ctx.run);
    try std.testing.expectEqual(@as(u64, 4950), sum);
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

test "parallelFold covers stack and heap future paths" {
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

    // 64 chunks: fits the stack fallback for this Fut size.
    const stack_total = try parallelFold(
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

    // 512 chunks: must fall back to the pool allocator.
    const heap_total = try parallelFold(
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

test "parallelFold is deterministic across worker counts" {
    const io = std.testing.io;
    const n = 2048;
    const Map = struct {
        fn map(_: *core.Worker(void), _: void, index: usize) anyerror!u64 {
            return index *% 3 +% 1;
        }
    };
    const Add = struct {
        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    var expected: u64 = 0;
    for (0..n) |index| expected += index *% 3 +% 1;

    for ([_]usize{ 0, 1, 2, 4 }) |workers| {
        var pool = try core.Pool(void).init(std.testing.allocator, io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .max_execute_states = 256,
            .worker_stack_size = 1 * 1024 * 1024,
        });
        defer pool.deinit();
        try pool.start();

        for (0..10) |_| {
            const total = try parallelFold(
                &pool,
                u64,
                {},
                n,
                .{ .min_chunk = 16, .serial_threshold = 0 },
                0,
                Map.map,
                Add.combine,
            );
            try std.testing.expectEqual(expected, total);
        }
    }
}

test "parallelFoldInfallible matches the fallible fold" {
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

    const n = 4096;
    const Map = struct {
        fn map(_: *core.Worker(void), _: void, index: usize) u64 {
            return index *% 5 +% 2;
        }
    };
    const Add = struct {
        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    var expected: u64 = 0;
    for (0..n) |index| expected += index *% 5 +% 2;

    const total = try parallelFoldInfallible(
        &pool,
        u64,
        {},
        n,
        .{ .min_chunk = 32, .serial_threshold = 0 },
        0,
        Map.map,
        Add.combine,
    );
    try std.testing.expectEqual(expected, total);
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
        parallelFor(&pool, {}, 10_000, .{
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
        parallelFold(&pool, u64, &ctx, 10_000, .{
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
        parallelFoldInfallible(&pool, u64, &ctx, 10_000, .{
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
        parallelFold(&pool, u64, {}, 100, .{
            .min_chunk = 1,
            .serial_threshold = 1000,
            .cancel = &token,
        }, 0, Map.map, Add.combine),
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
