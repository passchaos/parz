//! Sharded multi-producer/single-consumer queue.

const std = @import("std");
const builtin = @import("builtin");

const SpscQueue = @import("spsc.zig").SpscQueue;

/// Bounded sharded multi-producer/single-consumer queue. Each producer uses
/// its own SPSC shard, so producers never contend. The consumer round-robins
/// across shards; ordering is FIFO per shard, not globally.
pub fn ShardedMpscQueue(comptime T: type, comptime shard_count: usize) type {
    if (shard_count == 0) @compileError("ShardedMpscQueue needs at least one shard");

    return struct {
        const Self = @This();
        const shard_size = @sizeOf(SpscQueue(T));
        const pad_size = if (shard_size % std.atomic.cache_line == 0)
            0
        else
            std.atomic.cache_line - (shard_size % std.atomic.cache_line);
        const Shard = struct {
            queue: SpscQueue(T),
            _padding: [pad_size]u8 = undefined,
        };

        shards: [shard_count]Shard align(std.atomic.cache_line),
        next: usize = 0,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, capacity_per_shard: usize) !Self {
            var self = Self{
                .shards = undefined,
                .allocator = allocator,
            };
            var initialized: usize = 0;
            errdefer for (self.shards[0..initialized]) |*shard| shard.queue.deinit();
            for (&self.shards) |*shard| {
                shard.queue = try SpscQueue(T).init(allocator, capacity_per_shard);
                initialized += 1;
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            for (&self.shards) |*shard| shard.queue.deinit();
            self.* = undefined;
        }

        pub fn capacity(self: *const Self) usize {
            return self.shards[0].queue.capacity() * shard_count;
        }

        /// Approximate under concurrent producers; exact when quiescent.
        pub fn len(self: *const Self) usize {
            var total: usize = 0;
            for (&self.shards) |*shard| total += shard.queue.len();
            return total;
        }

        pub fn tryPush(self: *Self, shard_index: usize, value: T) bool {
            std.debug.assert(shard_index < shard_count);
            return self.shards[shard_index].queue.tryPush(value);
        }

        /// Producer-owned shard batch push. Returns the accepted prefix and
        /// publishes it with the underlying SPSC queue's single release.
        pub inline fn tryPushSlice(self: *Self, shard_index: usize, values: []const T) usize {
            std.debug.assert(shard_index < shard_count);
            return self.shards[shard_index].queue.tryPushSlice(values);
        }

        /// Single consumer only.
        pub fn tryPop(self: *Self) ?T {
            var checked: usize = 0;
            while (checked < shard_count) : (checked += 1) {
                const index = self.next;
                self.next = (self.next + 1) % shard_count;
                if (self.shards[index].queue.tryPop()) |value| return value;
            }
            return null;
        }

        /// Single-consumer batch pop. Visit each shard at most once, starting
        /// at the round-robin cursor, and fill an output prefix. A full output
        /// advances the cursor to the next shard for call-level fairness.
        pub fn tryPopSlice(self: *Self, output: []T) usize {
            if (output.len == 0) return 0;
            var count: usize = 0;
            var checked: usize = 0;
            while (checked < shard_count and count < output.len) : (checked += 1) {
                const index = self.next;
                self.next = (self.next + 1) % shard_count;
                count += self.shards[index].queue.tryPopSlice(output[count..]);
            }
            return count;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "sharded mpsc queue: single-threaded round robin" {
    var queue = try ShardedMpscQueue(u32, 2).init(std.testing.allocator, 4);
    defer queue.deinit();

    try std.testing.expectEqual(@as(usize, 8), queue.capacity());
    try std.testing.expectEqual(@as(usize, 0), queue.len());
    try std.testing.expect(queue.tryPop() == null);
    try std.testing.expect(queue.tryPush(0, 0));
    try std.testing.expect(queue.tryPush(1, 2));
    try std.testing.expect(queue.tryPush(0, 1));
    try std.testing.expect(queue.tryPush(1, 3));
    try std.testing.expectEqual(@as(usize, 4), queue.len());

    var seen = [_]bool{ false, false, false, false };
    for (0..4) |_| {
        const value = queue.tryPop().?;
        try std.testing.expect(value < 4);
        try std.testing.expect(!seen[value]);
        seen[value] = true;
    }
    try std.testing.expect(queue.tryPop() == null);
}

test "sharded mpsc queue: mixed slice transfers preserve per-shard FIFO through wrap" {
    const shards = 3;
    var queue = try ShardedMpscQueue(u32, shards).init(std.testing.allocator, 4);
    defer queue.deinit();
    const origin = std.math.maxInt(usize) - 2;
    for (&queue.shards) |*shard| {
        shard.queue.consumer = .{ .position = .init(origin), .cached_peer = origin };
        shard.queue.producer = .{ .position = .init(origin), .cached_peer = origin };
    }

    for (0..shards) |shard| {
        const base: u32 = @intCast(shard * 100);
        try std.testing.expect(queue.tryPush(shard, base));
        const values = [_]u32{ base + 1, base + 2, base + 3, base + 4 };
        try std.testing.expectEqual(@as(usize, 3), queue.tryPushSlice(shard, &values));
        try std.testing.expectEqual(@as(usize, 0), queue.tryPushSlice(shard, &values));
    }
    try std.testing.expectEqual(@as(usize, shards * 4), queue.len());

    var positions = [_]u32{0} ** shards;
    var received: usize = 0;
    while (received < shards * 4) {
        var output = [_]u32{std.math.maxInt(u32)} ** 5;
        const count = queue.tryPopSlice(&output);
        try std.testing.expect(count > 0);
        for (output[0..count]) |value| {
            const shard: usize = @intCast(value / 100);
            try std.testing.expect(shard < shards);
            try std.testing.expectEqual(positions[shard], value % 100);
            positions[shard] += 1;
        }
        for (output[count..]) |value| try std.testing.expectEqual(std.math.maxInt(u32), value);
        received += count;
    }
    var one = [_]u32{0};
    var empty: [0]u32 = .{};
    try std.testing.expectEqual(@as(usize, 0), queue.tryPopSlice(&one));
    try std.testing.expectEqual(@as(usize, 0), queue.tryPopSlice(&empty));

    // Mix batch producers with the scalar consumer after the wrapped round.
    for (0..shards) |shard| {
        const base: u32 = @intCast(shard * 100 + 4);
        const values = [_]u32{ base, base + 1, base + 2, base + 3 };
        try std.testing.expectEqual(values.len, queue.tryPushSlice(shard, &values));
    }
    while (queue.tryPop()) |value| {
        const shard: usize = @intCast(value / 100);
        try std.testing.expectEqual(positions[shard], value % 100);
        positions[shard] += 1;
    }
    for (positions) |position| try std.testing.expectEqual(@as(u32, 8), position);
}

test "sharded mpsc queue: initialization failures release completed shards" {
    const shards = 4;
    for (0..shards + 1) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
        if (fail_index < shards) {
            try std.testing.expectError(error.OutOfMemory, ShardedMpscQueue(u32, shards).init(failing.allocator(), 8));
            try std.testing.expect(failing.has_induced_failure);
        } else {
            var queue = try ShardedMpscQueue(u32, shards).init(failing.allocator(), 8);
            defer queue.deinit();
            try std.testing.expect(!failing.has_induced_failure);
        }
    }
}

test "sharded mpsc queue: threaded producers and consumer" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const shard_count = 4;
    const per_producer = 10_000;
    const total = shard_count * per_producer;
    var queue = try ShardedMpscQueue(u32, shard_count).init(std.testing.allocator, 1024);
    defer queue.deinit();

    const Producer = struct {
        fn run(q: *ShardedMpscQueue(u32, shard_count), shard: usize, base: u32) void {
            var offset: usize = 0;
            while (offset < per_producer) {
                if (q.tryPush(shard, base + @as(u32, @intCast(offset)))) {
                    offset += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    var threads: [shard_count]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{
            &queue,
            index,
            @as(u32, @intCast(index * per_producer)),
        });
    }

    var seen = try std.testing.allocator.alloc(bool, total);
    defer std.testing.allocator.free(seen);
    @memset(seen, false);
    var received: usize = 0;
    while (received < total) {
        if (queue.tryPop()) |value| {
            try std.testing.expect(value < total);
            try std.testing.expect(!seen[value]);
            seen[value] = true;
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    for (threads) |thread| thread.join();
}

test "sharded mpsc queue: concurrent mixed scalar and batch transfers" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const shard_count = 4;
    const per_producer = 25_000;
    const total = shard_count * per_producer;
    var queue = try ShardedMpscQueue(u32, shard_count).init(std.testing.allocator, 1024);
    defer queue.deinit();
    const origin = std.math.maxInt(usize) - 5;
    for (&queue.shards) |*shard| {
        shard.queue.consumer = .{ .position = .init(origin), .cached_peer = origin };
        shard.queue.producer = .{ .position = .init(origin), .cached_peer = origin };
    }

    const Producer = struct {
        fn run(q: *ShardedMpscQueue(u32, shard_count), shard: usize) void {
            const base: u32 = @intCast(shard * per_producer);
            var next: usize = 0;
            var values: [31]u32 = undefined;
            while (next < per_producer) {
                if (next % 7 == 0) {
                    if (q.tryPush(shard, base + @as(u32, @intCast(next)))) next += 1 else std.atomic.spinLoopHint();
                } else {
                    const length = @min(values.len, per_producer - next);
                    for (values[0..length], 0..) |*value, offset| value.* = base + @as(u32, @intCast(next + offset));
                    const pushed = q.tryPushSlice(shard, values[0..length]);
                    next += pushed;
                    if (pushed == 0) std.atomic.spinLoopHint();
                }
            }
        }
    };

    var threads: [shard_count]std.Thread = undefined;
    for (&threads, 0..) |*thread, shard| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{ &queue, shard });
    }

    var positions = [_]usize{0} ** shard_count;
    var received: usize = 0;
    var output: [19]u32 = undefined;
    while (received < total) {
        const popped: usize = if (received % 7 == 0) blk: {
            output[0] = queue.tryPop() orelse {
                std.atomic.spinLoopHint();
                break :blk 0;
            };
            break :blk 1;
        } else queue.tryPopSlice(&output);
        for (output[0..popped]) |value| {
            const shard: usize = @intCast(value / per_producer);
            try std.testing.expect(shard < shard_count);
            try std.testing.expectEqual(positions[shard], @as(usize, value % per_producer));
            positions[shard] += 1;
        }
        received += popped;
        if (popped == 0) std.atomic.spinLoopHint();
    }
    for (threads) |thread| thread.join();
    for (positions) |position| try std.testing.expectEqual(@as(usize, per_producer), position);
    try std.testing.expectEqual(@as(usize, 0), queue.len());
}
