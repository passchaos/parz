//! Ordered index folds with fallible and plain-value callback paths.

const std = @import("std");
const core = @import("../core.zig");
const types = @import("types.zig");
const Chunk = types.Chunk;
const Schedule = types.Schedule;
const Options = types.Options;
const CancelToken = @import("../cancel.zig").CancelToken;
const executor_mod = @import("executor.zig");
const checkCancel = @import("cancellation.zig").checkCancel;
const planning = @import("planning.zig");
const plannedLaneCountForWork = planning.plannedLaneCountForWork;
const plannedChunkCount = planning.plannedChunkCount;
const shouldRunSerial = planning.shouldRunSerial;
const dispatch = @import("dispatch.zig");
const serial = @import("serial.zig");
const cancel_block = @import("cancellation.zig").cancel_block;
const dispatchFold = dispatch.dispatchFold;
const dispatchFoldValue = dispatch.dispatchFoldValue;
const serialFold = serial.serialFold;
const serialFoldInfallible = serial.serialFoldInfallible;

/// Deterministic ordered fold. Each chunk accumulates with `combine`; the
/// caller then combines chunk results in index order. `map` may fail.
pub fn parallelFold(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    const pool = executor_mod.getPool(executor);
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
            try checkCancel(runner.cancel);
            return acc;
        }
    };

    var runner = Runner{
        .shared = &shared,
        .identity = identity,
        .cancel = options.cancel,
    };
    if (shouldRunSerial(count, options, pool.parallelWorkerCount())) {
        return serialFold(executor, T, shared, count, options.cancel, identity, map, combine);
    }
    const caller = executor_mod.borrowedWorker(executor) orelse (pool.claimFlatCaller() orelse {
        return serialFold(executor, T, shared, count, options.cancel, identity, map, combine);
    });
    defer if (executor_mod.borrowedWorker(executor) == null) pool.releaseCaller(caller);
    var task = caller.beginFlat();

    const chunks = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const lanes = plannedLaneCountForWork(count, options, pool.parallelWorkerCount());
    const result = try dispatchFold(pool, &task, T, Input, &runner, count, chunks, lanes, options.schedule, options.scratch, identity, Exec.exec, combine);
    // Dispatch has already selected any chunk error in index order. Only
    // successful reduction reaches this final cancellation checkpoint.
    try checkCancel(options.cancel);
    return result;
}

/// Deterministic ordered fold for an infallible `map`. The chunk loop has no
/// per-item error-union check.
pub fn parallelFoldInfallible(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    const pool = executor_mod.getPool(executor);
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
            try checkCancel(runner.cancel);
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
        return serialFoldInfallible(executor, T, shared, count, options.cancel, identity, map, combine);
    }
    const caller = executor_mod.borrowedWorker(executor) orelse (pool.claimFlatCaller() orelse {
        return serialFoldInfallible(executor, T, shared, count, options.cancel, identity, map, combine);
    });
    defer if (executor_mod.borrowedWorker(executor) == null) pool.releaseCaller(caller);
    var task = caller.beginFlat();

    const chunks = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const lanes = plannedLaneCountForWork(count, options, pool.parallelWorkerCount());
    if (options.cancel == null) {
        return dispatchFoldValue(pool, &task, T, Input, &runner, count, chunks, lanes, options.schedule, options.scratch, identity, ExecValue.exec, combine);
    }
    const result = try dispatchFold(pool, &task, T, Input, &runner, count, chunks, lanes, options.schedule, options.scratch, identity, Exec.exec, combine);
    try checkCancel(options.cancel);
    return result;
}

pub fn parallelReduce(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    return parallelFold(executor, T, shared, count, options, identity, map, combine);
}

pub fn parallelReduceInfallible(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map: anytype,
    comptime combine: anytype,
) anyerror!T {
    return parallelFoldInfallible(executor, T, shared, count, options, identity, map, combine);
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
        for ([_]Schedule{ .dynamic, .static }) |schedule| {
            const options = Options{ .max_chunks = 6, .chunks_per_worker = 6, .serial_threshold = 0, .schedule = schedule };
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
                for ([_]Schedule{ .dynamic, .static }) |schedule| {
                    const options = Options{ .max_workers = cap, .max_chunks = 6, .serial_threshold = 0, .schedule = schedule };
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
