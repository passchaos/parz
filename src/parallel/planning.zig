//! Saturating granularity planning and balanced contiguous partitions.

const std = @import("std");
const types = @import("types.zig");
const Chunk = types.Chunk;
const Options = types.Options;

/// Balanced contiguous partitions. The first `extra` chunks get one more
/// item; every chunk is nonempty and lengths differ by at most one. Advancing
/// a cursor avoids both per-chunk division and overflowing `index * size` or
/// ceil-division intermediates for ranges reaching usize's limit.
pub const ChunkCursor = struct {
    size: usize,
    extra: usize,
    start: usize = 0,

    pub inline fn init(count: usize, chunks: usize) ChunkCursor {
        std.debug.assert(chunks > 0 and chunks <= count);
        return .{ .size = count / chunks, .extra = count % chunks };
    }

    pub inline fn next(self: *ChunkCursor) Chunk {
        const end = self.start + self.size + @intFromBool(self.extra > 0);
        const chunk = Chunk{ .start = self.start, .end = end };
        self.start = end;
        self.extra -|= 1;
        return chunk;
    }
};

pub inline fn plannedLaneCount(options: Options, worker_count: usize) usize {
    const requested_lanes = if (options.max_workers == 0)
        worker_count
    else
        @min(options.max_workers, worker_count);
    return @max(requested_lanes, 1);
}

/// Cap lanes by estimated useful work. A cheap call should not wake lanes
/// that cannot stay busy for a useful interval. Without an item estimate the
/// plan is unchanged, so callers that do not opt in keep the exact old
/// distribution.
pub inline fn plannedLaneCountForWork(count: usize, options: Options, worker_count: usize) usize {
    const lanes = plannedLaneCount(options, worker_count);
    if (options.estimated_item_ns == 0 or options.min_parallel_lane_ns == 0) return lanes;
    const work_ns = count *| options.estimated_item_ns;
    const useful_lanes = @max(work_ns / @max(options.min_parallel_lane_ns, 1), 1);
    return @min(lanes, useful_lanes);
}

/// One atomic claim per chunk makes the dynamic cursor the bottleneck only
/// when a caller requests many small chunks. Above that point, claim a few
/// adjacent chunks per cursor update. Small and default chunk plans keep the
/// exact single-claim loop, so their distribution is unchanged.
pub inline fn dynamicClaimBatch(chunks: usize) usize {
    return @max(1, @min(@as(usize, 8), chunks / 512));
}

pub fn plannedChunkCount(count: usize, options: Options, worker_count: usize) usize {
    if (count == 0) return 0;
    const min_chunk = @max(options.min_chunk, 1);
    const by_chunk = @max(count / min_chunk, 1);
    const lanes = plannedLaneCountForWork(count, options, worker_count);
    const by_lanes = lanes *| @max(options.chunks_per_worker, 1);
    const cap = @max(options.max_chunks, 1);
    return @max(1, @min(@min(by_chunk, by_lanes), cap));
}

/// Small flat calls are dominated by caller-slot setup, future allocation and
/// worker wake-up. Run them on the caller instead. A call that cannot produce
/// at least one chunk per lane cannot use the pool effectively either.
pub fn shouldRunSerial(count: usize, options: Options, worker_count: usize) bool {
    if (options.serial_threshold == 0) return false;
    if (count < options.serial_threshold) return true;
    if (options.estimated_item_ns != 0 and
        count *| options.estimated_item_ns < options.min_parallel_ns) return true;
    return plannedChunkCount(count, options, worker_count) <
        plannedLaneCountForWork(count, options, worker_count);
}

test "cost estimate adds a saturating work guard without changing explicit dispatch" {
    for (1..6) |workers| {
        try std.testing.expect(shouldRunSerial(4096, .{ .estimated_item_ns = 1 }, workers));
        try std.testing.expect(shouldRunSerial(8192, .{ .estimated_item_ns = 1 }, workers));
        try std.testing.expect(!shouldRunSerial(65536, .{ .estimated_item_ns = 1 }, workers));
        try std.testing.expect(!shouldRunSerial(8192, .{ .estimated_item_ns = 100 }, workers));
        try std.testing.expect(!shouldRunSerial(8192, .{}, workers));
        try std.testing.expect(!shouldRunSerial(8192, .{ .estimated_item_ns = std.math.maxInt(usize) }, workers));
        try std.testing.expect(!shouldRunSerial(16, .{ .estimated_item_ns = 1, .serial_threshold = 0 }, workers));
    }
}

test "work estimate caps lanes without changing plans that omit it" {
    for (1..9) |workers| {
        // No estimate: the original lane plan is untouched.
        try std.testing.expectEqual(plannedLaneCount(.{}, workers), plannedLaneCountForWork(65536, .{}, workers));
        try std.testing.expectEqual(plannedLaneCount(.{}, workers), plannedLaneCountForWork(16, .{}, workers));

        // 100us of useful work at 20us per lane needs five lanes, not eight.
        const estimate = Options{ .estimated_item_ns = 1 };
        try std.testing.expectEqual(@min(plannedLaneCount(estimate, workers), 5), plannedLaneCountForWork(100_000, estimate, workers));
        // Explicit max_workers still caps first.
        const capped = Options{ .estimated_item_ns = 1, .max_workers = 2 };
        try std.testing.expectEqual(@min(plannedLaneCount(capped, workers), 2), plannedLaneCountForWork(65536, capped, workers));
        // Disabling the lane floor restores the raw plan.
        const disabled = Options{ .estimated_item_ns = 1, .min_parallel_lane_ns = 0 };
        try std.testing.expectEqual(plannedLaneCount(disabled, workers), plannedLaneCountForWork(65536, disabled, workers));
        // At least one lane is always planned.
        try std.testing.expectEqual(@as(usize, 1), plannedLaneCountForWork(1, .{ .estimated_item_ns = 1 }, workers));
    }
}
