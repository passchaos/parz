//! Flat parallel loop / fold APIs on top of the heartbeat scheduler.
//!
//! These APIs intentionally use direct callbacks instead of a composable
//! Rayon-style iterator. Every chunk owns a disjoint range; results are
//! combined in chunk-index order, so the output does not depend on which
//! worker ran which chunk.

const std = @import("std");
const builtin = @import("builtin");
const core = @import("core.zig");
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
    /// Minimum number of logical items per chunk, unless the whole input is smaller.
    min_chunk: usize = 1,
    /// Hard upper bound on chunks for one call.
    max_chunks: usize = 4096,
    /// Target chunks per available lane. More chunks improve load balance on
    /// heterogeneous CPUs. Lanes claim chunks dynamically from an index;
    /// this controls granularity rather than the number of jobs to wake.
    chunks_per_worker: usize = 16,
    /// Per-call lane cap, including the caller. 0 uses all available lanes.
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

    const chunks = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const lanes = plannedLaneCount(options, pool.parallelWorkerCount());
    return dispatchRange(pool, &task, Input, &runner, count, chunks, lanes, Exec.exec);
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
    const Exec = struct {
        fn exec(t: *Tm, input: Input) anyerror!T {
            const runner = input.runner;
            var acc = runner.identity;
            var i = input.chunk.start;
            while (i < input.chunk.end) {
                try checkCancel(runner.cancel);
                const block_end = @min(i +| cancel_block, input.chunk.end);
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

    const chunks = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const lanes = plannedLaneCount(options, pool.parallelWorkerCount());
    return dispatchFold(pool, &task, T, Input, &runner, count, chunks, lanes, identity, Exec.exec, combine);
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
    const Exec = struct {
        fn exec(t: *Tm, input: Input) anyerror!T {
            const runner = input.runner;
            var acc = runner.identity;
            var i = input.chunk.start;
            while (i < input.chunk.end) {
                try checkCancel(runner.cancel);
                const block_end = @min(i +| cancel_block, input.chunk.end);
                while (i < block_end) : (i += 1) {
                    acc = combine(acc, map(t.worker, runner.shared.*, i));
                }
            }
            return acc;
        }
    };
    const ExecValue = struct {
        fn exec(t: *Tm, input: Input) T {
            const runner = input.runner;
            var acc = runner.identity;
            var i = input.chunk.start;
            while (i < input.chunk.end) : (i += 1) {
                acc = combine(acc, map(t.worker, runner.shared.*, i));
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

    const chunks = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const lanes = plannedLaneCount(options, pool.parallelWorkerCount());
    if (options.cancel == null) {
        return dispatchFoldValue(pool, &task, T, Input, &runner, count, chunks, lanes, identity, ExecValue.exec, combine);
    }
    return dispatchFold(pool, &task, T, Input, &runner, count, chunks, lanes, identity, Exec.exec, combine);
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

// Keep dispatch storage in one bounded buffer, outside the serial fallback frame.
noinline fn dispatchRange(
    pool: anytype,
    task: anytype,
    comptime Input: type,
    runner: anytype,
    count: usize,
    chunks: usize,
    lanes: usize,
    comptime exec: anytype,
) anyerror!void {
    var fallback = std.heap.stackFallback(4096, pool.allocator);
    const allocator = fallback.get();
    const results = try allocator.alloc(anyerror!void, chunks);
    defer allocator.free(results);
    try runLanes(pool, task, Input, runner, count, lanes, results, allocator, exec);
    for (results) |result| try result;
}

noinline fn dispatchFold(
    pool: anytype,
    task: anytype,
    comptime T: type,
    comptime Input: type,
    runner: anytype,
    count: usize,
    chunks: usize,
    lanes: usize,
    identity: T,
    comptime exec: anytype,
    comptime combine: anytype,
) anyerror!T {
    var fallback = std.heap.stackFallback(4096, pool.allocator);
    const allocator = fallback.get();
    const results = try allocator.alloc(anyerror!T, chunks);
    defer allocator.free(results);
    try runLanes(pool, task, Input, runner, count, lanes, results, allocator, exec);
    var total = identity;
    for (results) |result| total = combine(total, try result);
    return total;
}

/// Without callback errors or cancellation, store only values and use the
/// plain-return chunk callback. Allocation errors still propagate to callers.
noinline fn dispatchFoldValue(
    pool: anytype,
    task: anytype,
    comptime T: type,
    comptime Input: type,
    runner: anytype,
    count: usize,
    chunks: usize,
    lanes: usize,
    identity: T,
    comptime exec: anytype,
    comptime combine: anytype,
) anyerror!T {
    var fallback = std.heap.stackFallback(4096, pool.allocator);
    const allocator = fallback.get();
    const results = try allocator.alloc(T, chunks);
    defer allocator.free(results);
    try runLanes(pool, task, Input, runner, count, lanes, results, allocator, exec);
    var total = identity;
    for (results) |result| total = combine(total, result);
    return total;
}

/// One future per lane bounds the number of simultaneous chunk callbacks.
/// Lanes claim disjoint result slots; all are joined before ordered reduction.
/// The caller's future is the retained local tail and runs before any waits.
fn runLanes(
    pool: anytype,
    task: anytype,
    comptime Input: type,
    runner: anytype,
    count: usize,
    requested_lanes: usize,
    results: anytype,
    allocator: std.mem.Allocator,
    comptime exec: anytype,
) anyerror!void {
    const P = @TypeOf(pool.*);
    const Task = P.TaskType;
    const Runner = @TypeOf(runner);
    const Result = @typeInfo(@TypeOf(results)).pointer.child;
    const lanes = @min(requested_lanes, results.len);
    if (lanes == 1) {
        var cursor = ChunkCursor.init(count, results.len);
        for (results) |*result| result.* = task.call(Result, exec, Input{ .runner = runner, .chunk = cursor.next() });
        return;
    }

    const State = struct {
        runner: Runner,
        results: []Result,
        size: usize,
        extra: usize,
        next: std.atomic.Value(usize) = .init(0),

        fn run(t: *Task, self: *@This()) void {
            while (true) {
                const index = self.next.fetchAdd(1, .monotonic);
                if (index >= self.results.len) return;
                // floor-sized chunks plus a prefix of one-item remainders.
                // For index < chunks, both intermediates remain <= count.
                const start = index * self.size + @min(index, self.extra);
                const chunk = Chunk{ .start = start, .end = start + self.size + @intFromBool(index < self.extra) };
                self.results[index] = t.call(Result, exec, Input{ .runner = self.runner, .chunk = chunk });
            }
        }
    };
    var state = State{ .runner = runner, .results = results, .size = count / results.len, .extra = count % results.len };
    const Fut = core.Future(P.Context, *State, void);
    const futures = try allocator.alloc(Fut, lanes);
    defer allocator.free(futures);
    for (futures) |*future| {
        future.* = .{};
        future.fork(task, State.run, &state);
    }
    pool.kickstart(task.worker, lanes);
    futures[lanes - 1].joinOrCall(task, State.run);
    for (futures[0 .. lanes - 1]) |*future| future.joinOrCall(task, State.run);
}

/// Balanced contiguous partitions. The first `extra` chunks get one more
/// item; every chunk is nonempty and lengths differ by at most one. Advancing
/// a cursor avoids both per-chunk division and overflowing `index * size` or
/// ceil-division intermediates for ranges reaching usize's limit.
const ChunkCursor = struct {
    size: usize,
    extra: usize,
    start: usize = 0,

    fn init(count: usize, chunks: usize) ChunkCursor {
        std.debug.assert(chunks > 0 and chunks <= count);
        return .{ .size = count / chunks, .extra = count % chunks };
    }

    fn next(self: *ChunkCursor) Chunk {
        const end = self.start + self.size + @intFromBool(self.extra > 0);
        const chunk = Chunk{ .start = self.start, .end = end };
        self.start = end;
        self.extra -|= 1;
        return chunk;
    }
};

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
    const by_chunk = @max(count / min_chunk, 1);
    const lanes = plannedLaneCount(options, worker_count);
    const by_lanes = lanes *| @max(options.chunks_per_worker, 1);
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
    var temp = W{ .pool = pool, .index = 0, .active = false, .ctx = try pool.createTempContext() };
    defer pool.destroyTempContext(&temp.ctx);
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
    var temp = W{ .pool = pool, .index = 0, .active = false, .ctx = try pool.createTempContext() };
    defer pool.destroyTempContext(&temp.ctx);
    var total = identity;
    var i: usize = 0;
    while (i < count) {
        try checkCancel(cancel);
        const block_end = @min(i +| cancel_block, count);
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
    var temp = W{ .pool = pool, .index = 0, .active = false, .ctx = try pool.createTempContext() };
    defer pool.destroyTempContext(&temp.ctx);
    var total = identity;
    var i: usize = 0;
    while (i < count) {
        try checkCancel(cancel);
        const block_end = @min(i +| cancel_block, count);
        while (i < block_end) : (i += 1) {
            total = combine(total, map(&temp, shared, i));
        }
    }
    return total;
}

test "parallelForRange partitions uneven counts into nonempty ordered ranges" {
    const Case = struct { count: usize, min_chunk: usize, chunks: usize };
    const Run = struct {
        fn run(_: *core.Worker(void), ranges: *[16]?Chunk, chunk: Chunk) anyerror!void {
            try std.testing.expect(chunk.start < chunk.end);
            try std.testing.expect(chunk.end <= ranges.len);
            ranges[chunk.start] = chunk;
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

        for ([_]Case{
            .{ .count = 10, .min_chunk = 1, .chunks = 6 },
            .{ .count = 13, .min_chunk = 3, .chunks = 4 },
            .{ .count = 3, .min_chunk = 8, .chunks = 1 },
        }) |case| {
            var expected: ?[16]?Chunk = null;
            for (0..5) |_| {
                var ranges = [_]?Chunk{null} ** 16;
                try parallelForRange(&pool, &ranges, case.count, .{
                    .min_chunk = case.min_chunk,
                    .max_chunks = 6,
                    .chunks_per_worker = 6,
                    .serial_threshold = 0,
                }, Run.run);
                var next: usize = 0;
                var chunks: usize = 0;
                var shortest: usize = case.count;
                var longest: usize = 0;
                for (ranges) |range| {
                    if (range) |chunk| {
                        try std.testing.expectEqual(next, chunk.start);
                        const len = chunk.end - chunk.start;
                        try std.testing.expect(len >= @min(case.count, case.min_chunk));
                        shortest = @min(shortest, len);
                        longest = @max(longest, len);
                        next = chunk.end;
                        chunks += 1;
                    }
                }
                try std.testing.expectEqual(case.count, next);
                try std.testing.expectEqual(case.chunks, chunks);
                try std.testing.expect(longest - shortest <= 1);
                if (expected) |previous| {
                    try std.testing.expectEqualDeep(previous, ranges);
                } else {
                    expected = ranges;
                }
            }
        }
    }
}

test "parallelForRange accepts usize limits and saturates lane planning" {
    const Record = struct {
        calls: std.atomic.Value(usize) = .init(0),
        chunks: [7]Chunk = undefined,

        fn run(_: *core.Worker(void), self: *@This(), chunk: Chunk) anyerror!void {
            try std.testing.expect(chunk.start < chunk.end);
            const slot = self.calls.fetchAdd(1, .monotonic);
            try std.testing.expect(slot < self.chunks.len);
            self.chunks[slot] = chunk;
        }

        fn lessThan(_: void, a: Chunk, b: Chunk) bool {
            return a.start < b.start;
        }
    };
    const limit = std.math.maxInt(usize);
    for (0..5) |workers| {
        var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
        });
        defer pool.deinit();
        try pool.start();
        for ([_]usize{ 1, limit / 3, limit }) |min_chunk| {
            var previous: ?[7]Chunk = null;
            for (0..5) |_| {
                var record = Record{};
                try parallelForRange(&pool, &record, limit, .{
                    .min_chunk = min_chunk,
                    .max_workers = @min(workers + 1, 2),
                    .chunks_per_worker = limit,
                    .max_chunks = 7,
                    .serial_threshold = 0,
                }, Record.run);
                const calls = record.calls.load(.monotonic);
                try std.testing.expectEqual(@min(limit / min_chunk, 7), calls);
                std.mem.sort(Chunk, record.chunks[0..calls], {}, Record.lessThan);
                var end: usize = 0;
                for (record.chunks[0..calls]) |chunk| {
                    try std.testing.expectEqual(end, chunk.start);
                    try std.testing.expect(chunk.end - chunk.start >= min_chunk);
                    end = chunk.end;
                }
                try std.testing.expectEqual(limit, end);
                if (previous) |chunks| {
                    try std.testing.expectEqualDeep(chunks[0..calls], record.chunks[0..calls]);
                }
                // Only initialized slots are read on the next run.
                @memset(record.chunks[calls..], .{ .start = 0, .end = 0 });
                previous = record.chunks;
            }
        }
    }
}

test "balanced folds preserve sequence order across worker counts" {
    const Sequence = struct {
        hash: u64 = 0,
        factor: u64 = 1,

        fn map(_: *core.Worker(void), _: void, index: usize) @This() {
            return .{ .hash = index + 1, .factor = 31 };
        }

        fn fallible(w: *core.Worker(void), shared: void, index: usize) anyerror!@This() {
            return map(w, shared, index);
        }

        // Associative concatenation; swapping chunks changes the hash.
        fn combine(a: @This(), b: @This()) @This() {
            return .{ .hash = a.hash *% b.factor +% b.hash, .factor = a.factor *% b.factor };
        }
    };
    const options = Options{ .max_chunks = 6, .chunks_per_worker = 6, .serial_threshold = 0 };
    var expected = Sequence{};
    for (0..13) |index| {
        expected = Sequence.combine(expected, .{ .hash = index + 1, .factor = 31 });
    }
    for (0..5) |workers| {
        var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
        });
        defer pool.deinit();
        try pool.start();
        for (0..5) |_| {
            try std.testing.expectEqualDeep(expected, try parallelFold(
                &pool,
                Sequence,
                {},
                13,
                options,
                .{},
                Sequence.fallible,
                Sequence.combine,
            ));
            try std.testing.expectEqualDeep(expected, try parallelFoldInfallible(
                &pool,
                Sequence,
                {},
                13,
                options,
                .{},
                Sequence.map,
                Sequence.combine,
            ));
        }
    }
}

test "parallelForRange enforces worker caps including the caller" {
    const n = 128;
    const State = struct {
        limit: usize,
        caller_index: usize,
        active: std.atomic.Value(usize) = .init(0),
        exceeded: std.atomic.Value(bool) = .init(false),
        caller_ran: std.atomic.Value(bool) = .init(false),
        counts: [n]std.atomic.Value(u32) = [_]std.atomic.Value(u32){.init(0)} ** n,

        fn run(w: *core.Worker(void), self: *@This(), chunk: Chunk) anyerror!void {
            if (self.active.fetchAdd(1, .monotonic) >= self.limit) self.exceeded.store(true, .monotonic);
            defer _ = self.active.fetchSub(1, .monotonic);
            if (w.index == self.caller_index) self.caller_ran.store(true, .monotonic);
            // Keep callbacks overlapping long enough to check admission,
            // without relying on which particular background lane wins.
            try w.pool.io.sleep(std.Io.Duration.fromMilliseconds(1), .awake);
            for (chunk.start..chunk.end) |index| _ = self.counts[index].fetchAdd(1, .monotonic);
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
        for (1..6) |cap| {
            for (0..3) |_| {
                var state = State{ .limit = cap, .caller_index = pool.caller_storage[0].index };
                try parallelForRange(&pool, &state, n, .{
                    .max_workers = cap,
                    .max_chunks = 8,
                    .serial_threshold = 0,
                }, State.run);
                try std.testing.expect(!state.exceeded.load(.monotonic));
                try std.testing.expect(state.caller_ran.load(.monotonic));
                try std.testing.expectEqual(@as(usize, 0), state.active.load(.monotonic));
                for (state.counts) |count| try std.testing.expectEqual(@as(u32, 1), count.load(.monotonic));
            }
        }
    }
}

test "capped folds preserve ordered results and errors across worker counts" {
    const Sequence = struct {
        hash: u64 = 0,
        factor: u64 = 1,

        fn map(_: *core.Worker(void), _: void, index: usize) @This() {
            return .{ .hash = index + 1, .factor = 31 };
        }
        fn fallible(w: *core.Worker(void), shared: void, index: usize) anyerror!@This() {
            return map(w, shared, index);
        }
        fn failing(w: *core.Worker(void), shared: void, index: usize) anyerror!@This() {
            if (index == 3) return error.FirstFailure;
            if (index == 9) return error.SecondFailure;
            return map(w, shared, index);
        }
        fn combine(a: @This(), b: @This()) @This() {
            return .{ .hash = a.hash *% b.factor +% b.hash, .factor = a.factor *% b.factor };
        }
    };
    var expected = Sequence{};
    for (0..13) |index| expected = Sequence.combine(expected, .{ .hash = index + 1, .factor = 31 });
    for (0..5) |workers| {
        for ([_]usize{ 0, 32 }) |states| {
            var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
                .workers = workers,
                .max_workers = workers,
                .max_callers = 1,
                .max_execute_states = states,
            });
            defer pool.deinit();
            try pool.start();
            for (1..6) |cap| {
                const options = Options{ .max_workers = cap, .max_chunks = 6, .serial_threshold = 0 };
                for (0..3) |_| {
                    try std.testing.expectEqualDeep(expected, try parallelFold(
                        &pool,
                        Sequence,
                        {},
                        13,
                        options,
                        .{},
                        Sequence.fallible,
                        Sequence.combine,
                    ));
                    try std.testing.expectEqualDeep(expected, try parallelFoldInfallible(
                        &pool,
                        Sequence,
                        {},
                        13,
                        options,
                        .{},
                        Sequence.map,
                        Sequence.combine,
                    ));
                    try std.testing.expectError(error.FirstFailure, parallelFold(
                        &pool,
                        Sequence,
                        {},
                        13,
                        options,
                        .{},
                        Sequence.failing,
                        Sequence.combine,
                    ));
                }
            }
        }
    }
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
    try std.testing.expectError(error.OutOfMemory, parallelForRange(&pool, &calls, 4096, .{
        .max_workers = 2,
        .chunks_per_worker = 1024,
        .serial_threshold = 0,
    }, Run.range));
    try std.testing.expectEqual(@as(usize, 0), calls);
    const caller = pool.claimCaller().?;
    pool.releaseCaller(caller);
    // The larger fold result array requires the fallback allocator itself.
    try std.testing.expectError(error.OutOfMemory, parallelFold(
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
    try std.testing.expectEqual(@as(u64, 8386560), try parallelFold(
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
            try parallelFor(w.pool, self, n, .{ .max_workers = 2, .serial_threshold = 0 }, inner);
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
        try parallelFor(&pool, &state, n, .{ .max_workers = 2, .serial_threshold = 0 }, State.outer);
        for (state.counts) |count| try std.testing.expectEqual(@as(u32, n), count.load(.monotonic));
        try std.testing.expectError(error.Cancelled, parallelFor(&pool, &state, n, .{
            .max_workers = 2,
            .max_chunks = 8,
            .serial_threshold = 0,
            .cancel = &state.token,
        }, State.cancelling));
        const caller = pool.claimCaller().?;
        pool.releaseCaller(caller);
    }
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
        try parallelFor(&pool, {}, 8, options, Run.run);
        try std.testing.expectEqual(@as(u64, 28), try parallelFold(
            &pool,
            u64,
            {},
            8,
            options,
            0,
            Run.map,
            Run.combine,
        ));
        try std.testing.expectEqual(@as(u64, 28), try parallelFoldInfallible(
            &pool,
            u64,
            {},
            8,
            options,
            0,
            Run.infallible,
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

    // The larger result array must use the pool allocator fallback.
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

test "uncancelled infallible fold fits 256 u64 results and lane futures on the stack" {
    const Run = struct {
        fn map(_: *core.Worker(void), _: void, index: usize) u64 {
            return index;
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
                const result = try parallelFoldInfallible(&pool, u64, {}, 4096, .{
                    .min_chunk = 1,
                    .max_chunks = 256,
                    .chunks_per_worker = 256,
                    .serial_threshold = 0,
                }, 0, Run.map, Run.add);
                try std.testing.expectEqual(@as(u64, 8386560), result);
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
    try std.testing.expectError(error.OutOfMemory, parallelFoldInfallible(&pool, u64, &calls, 4096, .{
        .min_chunk = 1,
        .max_chunks = 1024,
        .chunks_per_worker = 1024,
        .serial_threshold = 0,
    }, 0, Run.map, Run.add));
    try std.testing.expectEqual(@as(usize, 0), calls.load(.monotonic));
    const caller = pool.claimCaller().?;
    pool.releaseCaller(caller);
    // The value array fits exactly; allocation of lane futures must fail.
    try std.testing.expectError(error.OutOfMemory, parallelFoldInfallible(&pool, Packet, &calls, 64, .{
        .min_chunk = 1,
        .max_chunks = 64,
        .chunks_per_worker = 64,
        .serial_threshold = 0,
    }, .{}, Run.packet, Run.combine));
    try std.testing.expectEqual(@as(usize, 0), calls.load(.monotonic));
    const again = pool.claimCaller().?;
    pool.releaseCaller(again);
    failing.fail_index = std.math.maxInt(usize);
    const result = try parallelFoldInfallible(&pool, Packet, &calls, 64, .{
        .min_chunk = 1,
        .max_chunks = 64,
        .chunks_per_worker = 64,
        .serial_threshold = 0,
    }, .{}, Run.packet, Run.combine);
    try std.testing.expectEqual(@as(usize, 64), calls.load(.monotonic));
    for (result.words) |word| try std.testing.expectEqual(@as(u64, 2016), word);
}

test "infallible value and cancellable folds preserve noncommutative order across lanes" {
    const Sequence = struct {
        hash: u64 = 0,
        power: u64 = 1,
    };
    const base: u64 = 0x100000001b3;
    const Run = struct {
        fn map(_: *core.Worker(void), _: void, index: usize) Sequence {
            return .{ .hash = index + 1, .power = base };
        }
        fn combine(a: Sequence, b: Sequence) Sequence {
            return .{ .hash = a.hash *% b.power +% b.hash, .power = a.power *% b.power };
        }
    };
    var expected = Sequence{};
    for (0..641) |index| {
        expected.hash = expected.hash *% base +% (index + 1);
        expected.power *%= base;
    }
    for (0..5) |workers| {
        var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
        });
        defer pool.deinit();
        try pool.start();
        var token = CancelToken{};
        for (1..6) |cap| {
            for (0..3) |_| {
                for ([_]?*CancelToken{ null, &token }) |cancel| {
                    const result = try parallelFoldInfallible(&pool, Sequence, {}, 641, .{
                        .min_chunk = 3,
                        .max_chunks = 73,
                        .chunks_per_worker = 17,
                        .max_workers = cap,
                        .serial_threshold = 0,
                        .cancel = cancel,
                    }, .{}, Run.map, Run.combine);
                    try std.testing.expectEqual(expected, result);
                }
            }
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
    if (parallelFor(&pool, {}, 1_000_000, .{
        .min_chunk = 1,
        .serial_threshold = 0,
        .cancel = &token,
    }, Ctx.run)) |_| {} else |err| {
        try std.testing.expectEqual(error.Cancelled, err);
    }
    thread.join();
}
