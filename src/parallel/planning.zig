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

    pub fn init(count: usize, chunks: usize) ChunkCursor {
        std.debug.assert(chunks > 0 and chunks <= count);
        return .{ .size = count / chunks, .extra = count % chunks };
    }

    pub fn next(self: *ChunkCursor) Chunk {
        const end = self.start + self.size + @intFromBool(self.extra > 0);
        const chunk = Chunk{ .start = self.start, .end = end };
        self.start = end;
        self.extra -|= 1;
        return chunk;
    }
};

pub fn plannedLaneCount(options: Options, worker_count: usize) usize {
    const requested_lanes = if (options.max_workers == 0)
        worker_count
    else
        @min(options.max_workers, worker_count);
    return @max(requested_lanes, 1);
}

/// One atomic claim per chunk makes the dynamic cursor the bottleneck only
/// when a caller requests many small chunks. Above that point, claim a few
/// adjacent chunks per cursor update. Small and default chunk plans keep the
/// exact single-claim loop, so their distribution is unchanged.
pub fn dynamicClaimBatch(chunks: usize) usize {
    return @max(1, @min(@as(usize, 8), chunks / 512));
}

pub fn plannedChunkCount(count: usize, options: Options, worker_count: usize) usize {
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
pub fn shouldRunSerial(count: usize, options: Options, worker_count: usize) bool {
    if (options.serial_threshold == 0) return false;
    if (count < options.serial_threshold) return true;
    if (options.estimated_item_ns != 0 and
        count *| options.estimated_item_ns < options.min_parallel_ns) return true;
    return plannedChunkCount(count, options, worker_count) <
        plannedLaneCount(options, worker_count);
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
