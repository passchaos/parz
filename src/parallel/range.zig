//! Direct range callbacks and deterministic range folds.

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
const dispatchRange = dispatch.dispatchRange;
const dispatchFold = dispatch.dispatchFold;
const dispatchFoldValue = dispatch.dispatchFoldValue;
const serialRange = serial.serialRange;
const serialFoldRange = serial.serialFoldRange;
const serialFoldRangeInfallible = serial.serialFoldRangeInfallible;

/// Parallel loop over half-open ranges. The callback receives one chunk.
pub fn parallelForRange(
    executor: anytype,
    shared: anytype,
    count: usize,
    options: Options,
    comptime run: anytype,
) anyerror!void {
    const pool = executor_mod.getPool(executor);
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
            try checkCancel(input.runner.cancel);
        }
    };

    var runner = Runner{ .shared = &shared, .cancel = options.cancel };
    if (shouldRunSerial(count, options, pool.parallelWorkerCount())) {
        return serialRange(executor, shared, count, options.cancel, run);
    }
    const caller = executor_mod.borrowedWorker(executor) orelse (pool.claimFlatCaller() orelse {
        return serialRange(executor, shared, count, options.cancel, run);
    });
    defer if (executor_mod.borrowedWorker(executor) == null) pool.releaseCaller(caller);
    var task = caller.beginFlat();

    const chunks = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const lanes = plannedLaneCountForWork(count, options, pool.parallelWorkerCount());
    try dispatchRange(pool, &task, Input, &runner, count, chunks, lanes, options.schedule, options.scratch, Exec.exec);
    try checkCancel(options.cancel);
}

/// Deterministic ordered fold over planned ranges. `map_range` is invoked
/// once per nonempty chunk and may fail. It can use a direct inner loop while
/// parz retains chunk-index result and error ordering.
pub fn parallelFoldRange(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map_range: anytype,
    comptime combine: anytype,
) anyerror!T {
    const pool = executor_mod.getPool(executor);
    if (count == 0) return identity;

    const P = @TypeOf(pool.*);
    const Tm = P.TaskType;
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
        fn exec(t: *Tm, input: Input) anyerror!T {
            try checkCancel(input.runner.cancel);
            const result = try map_range(t.worker, input.runner.shared.*, input.chunk);
            try checkCancel(input.runner.cancel);
            return result;
        }
    };

    var runner = Runner{ .shared = &shared, .cancel = options.cancel };
    if (shouldRunSerial(count, options, pool.parallelWorkerCount())) {
        return serialFoldRange(executor, T, shared, count, options.cancel, identity, map_range, combine);
    }
    const caller = executor_mod.borrowedWorker(executor) orelse (pool.claimFlatCaller() orelse {
        return serialFoldRange(executor, T, shared, count, options.cancel, identity, map_range, combine);
    });
    defer if (executor_mod.borrowedWorker(executor) == null) pool.releaseCaller(caller);
    var task = caller.beginFlat();

    const chunks = plannedChunkCount(count, options, pool.parallelWorkerCount());
    const lanes = plannedLaneCountForWork(count, options, pool.parallelWorkerCount());
    const result = try dispatchFold(pool, &task, T, Input, &runner, count, chunks, lanes, options.schedule, options.scratch, identity, Exec.exec, combine);
    try checkCancel(options.cancel);
    return result;
}

/// Infallible range fold. Without a cancellation token, both the range
/// callback and dispatch results use plain values.
pub fn parallelFoldRangeInfallible(
    executor: anytype,
    comptime T: type,
    shared: anytype,
    count: usize,
    options: Options,
    identity: T,
    comptime map_range: anytype,
    comptime combine: anytype,
) anyerror!T {
    const pool = executor_mod.getPool(executor);
    if (count == 0) return identity;

    const P = @TypeOf(pool.*);
    const Tm = P.TaskType;
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
        fn exec(t: *Tm, input: Input) anyerror!T {
            try checkCancel(input.runner.cancel);
            const result = map_range(t.worker, input.runner.shared.*, input.chunk);
            try checkCancel(input.runner.cancel);
            return result;
        }
    };
    const ExecValue = struct {
        fn exec(t: *Tm, input: Input) T {
            return map_range(t.worker, input.runner.shared.*, input.chunk);
        }
    };

    var runner = Runner{ .shared = &shared, .cancel = options.cancel };
    if (shouldRunSerial(count, options, pool.parallelWorkerCount())) {
        return serialFoldRangeInfallible(executor, T, shared, count, options.cancel, identity, map_range, combine);
    }
    const caller = executor_mod.borrowedWorker(executor) orelse (pool.claimFlatCaller() orelse {
        return serialFoldRangeInfallible(executor, T, shared, count, options.cancel, identity, map_range, combine);
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
            for ([_]Schedule{ .dynamic, .static }) |schedule| {
                for (0..3) |_| {
                    var state = State{ .limit = cap, .caller_index = pool.caller_storage[0].index };
                    try parallelForRange(&pool, &state, n, .{
                        .max_workers = cap,
                        .max_chunks = 8,
                        .serial_threshold = 0,
                        .schedule = schedule,
                    }, State.run);
                    try std.testing.expect(!state.exceeded.load(.monotonic));
                    try std.testing.expect(state.caller_ran.load(.monotonic));
                    try std.testing.expectEqual(@as(usize, 0), state.active.load(.monotonic));
                    for (state.counts) |count| try std.testing.expectEqual(@as(u32, 1), count.load(.monotonic));
                }
            }
        }
    }
}

test "range folds preserve deterministic chunk-index order across worker counts" {
    const Sequence = struct {
        hash: u64 = 0,
        factor: u64 = 1,

        fn combine(a: @This(), b: @This()) @This() {
            return .{ .hash = a.hash *% b.factor +% b.hash, .factor = a.factor *% b.factor };
        }
        fn range(_: *core.Worker(void), _: void, chunk: Chunk) @This() {
            var result = @This(){};
            for (chunk.start..chunk.end) |index| {
                result = combine(result, .{ .hash = index + 1, .factor = 31 });
            }
            return result;
        }
        fn fallible(w: *core.Worker(void), shared: void, chunk: Chunk) anyerror!@This() {
            return range(w, shared, chunk);
        }
    };
    const count = 37;
    var expected = Sequence{};
    for (0..count) |index| {
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
            for (0..5) |_| {
                const options = Options{ .min_chunk = 3, .max_chunks = 7, .chunks_per_worker = 3, .serial_threshold = 0, .schedule = schedule };
                try std.testing.expectEqualDeep(expected, try parallelFoldRange(
                    &pool,
                    Sequence,
                    {},
                    count,
                    options,
                    .{},
                    Sequence.fallible,
                    Sequence.combine,
                ));
                try std.testing.expectEqualDeep(expected, try parallelFoldRangeInfallible(
                    &pool,
                    Sequence,
                    {},
                    count,
                    options,
                    .{},
                    Sequence.range,
                    Sequence.combine,
                ));
            }
        }
        const serial_options = Options{ .serial_threshold = count + 1 };
        try std.testing.expectEqualDeep(expected, try parallelFoldRange(&pool, Sequence, {}, count, serial_options, .{}, Sequence.fallible, Sequence.combine));
        try std.testing.expectEqualDeep(expected, try parallelFoldRangeInfallible(&pool, Sequence, {}, count, serial_options, .{}, Sequence.range, Sequence.combine));
    }
}

test "range fold errors are selected by chunk index" {
    const Run = struct {
        fn map(_: *core.Worker(void), _: void, chunk: Chunk) anyerror!u64 {
            if (chunk.start == 0) return error.FirstChunk;
            return error.LaterChunk;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
        fn never(_: *core.Worker(void), _: void, _: Chunk) anyerror!u64 {
            return error.UnexpectedCallback;
        }
        fn neverValue(_: *core.Worker(void), _: void, _: Chunk) u64 {
            @panic("empty range fold callback must not run");
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
        try std.testing.expectEqual(@as(u64, 9), try parallelFoldRange(&pool, u64, {}, 0, .{}, 9, Run.never, Run.add));
        try std.testing.expectEqual(@as(u64, 11), try parallelFoldRangeInfallible(&pool, u64, {}, 0, .{}, 11, Run.neverValue, Run.add));
        for ([_]Schedule{ .dynamic, .static }) |schedule| {
            for (0..5) |_| {
                try std.testing.expectError(error.FirstChunk, parallelFoldRange(
                    &pool,
                    u64,
                    {},
                    64,
                    .{ .min_chunk = 1, .max_chunks = 8, .chunks_per_worker = 8, .serial_threshold = 0, .schedule = schedule },
                    0,
                    Run.map,
                    Run.add,
                ));
            }
        }
    }
}
