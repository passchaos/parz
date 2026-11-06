//! Flat parallel loop / fold APIs on top of the heartbeat scheduler.
//!
//! These APIs intentionally use direct callbacks instead of a composable
//! Rayon-style iterator. Every chunk owns a disjoint range; results are
//! combined in chunk-index order, so the output does not depend on which
//! worker ran which chunk.

const std = @import("std");
const core = @import("core.zig");
const Job = @import("job.zig").Job;

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

        fn range(w: *W, self: *@This(), chunk: Chunk) anyerror!void {
            var i = chunk.start;
            while (i < chunk.end) : (i += 1) {
                // Call the comptime callback directly so the per-item call is
                // inlined instead of going through a function pointer.
                try run(w, self.shared.*, i);
            }
        }
    };

    var runner = IndexRunner{ .shared = &shared };
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
    };
    const Input = struct {
        runner: *Runner,
        chunk: Chunk,
    };
    const Fut = core.Future(Ctx, Input, anyerror!void);
    const Exec = struct {
        fn exec(t: *T, input: Input) anyerror!void {
            try run(t.worker, input.runner.shared.*, input.chunk);
        }
    };

    var runner = Runner{ .shared = &shared };
    if (shouldRunSerial(count, options, pool.parallelWorkerCount())) {
        return serialRange(pool, shared, count, run);
    }
    const caller = pool.claimCaller() orelse {
        return serialRange(pool, shared, count, run);
    };
    defer pool.releaseCaller(caller);
    var task = caller.begin();

    const chunk_count = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const futures = try pool.allocator.alloc(Fut, chunk_count);
    defer pool.allocator.free(futures);

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
/// caller then combines chunk results in index order.
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
            while (i < input.chunk.end) : (i += 1) {
                // Direct comptime calls: no per-item function pointers.
                acc = combine(acc, try map(t.worker, runner.shared.*, i));
            }
            return acc;
        }
    };

    var runner = Runner{
        .shared = &shared,
        .identity = identity,
    };
    if (shouldRunSerial(count, options, pool.parallelWorkerCount())) {
        return serialFold(pool, T, shared, count, identity, map, combine);
    }
    const caller = pool.claimCaller() orelse {
        return serialFold(pool, T, shared, count, identity, map, combine);
    };
    defer pool.releaseCaller(caller);
    var task = caller.begin();

    const chunk_count = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const futures = try pool.allocator.alloc(Fut, chunk_count);
    defer pool.allocator.free(futures);

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
    comptime run: anytype,
) anyerror!void {
    const P = @TypeOf(pool.*);
    const W = P.WorkerType;
    var ctx = try pool.createTempContext();
    defer pool.destroyTempContext(&ctx);
    var temp = W{ .pool = pool, .index = 0, .active = false, .ctx = ctx };
    try run(&temp, shared, .{ .start = 0, .end = count });
}

fn serialFold(
    pool: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
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
    while (i < count) : (i += 1) {
        total = combine(total, try map(&temp, shared, i));
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
