//! Bounded single-producer/single-consumer ring buffer.

const std = @import("std");
const builtin = @import("builtin");

/// Bounded single-producer/single-consumer ring buffer. Each endpoint caches
/// its peer's position, refreshing it only at a possible full/empty boundary.
pub fn SpscQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        const Cursor = struct {
            position: std.atomic.Value(usize) = .init(0),
            // Only this cursor's owner reads or writes the cached peer value.
            cached_peer: usize = 0,
            // Fill the line: immutable buffer metadata must not occupy the
            // producer's line and make every consumer access contend with it.
            _padding: [std.atomic.cache_line - 2 * @sizeOf(usize)]u8 = undefined,
        };

        comptime {
            std.debug.assert(@sizeOf(Cursor) == std.atomic.cache_line);
        }

        buffer: []T,
        mask: usize,
        consumer: Cursor align(std.atomic.cache_line) = .{},
        producer: Cursor align(std.atomic.cache_line) = .{},
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, requested_capacity: usize) !Self {
            const actual_capacity = std.math.ceilPowerOfTwo(usize, @max(requested_capacity, 1)) catch
                return error.CapacityOverflow;
            const buffer = try allocator.alloc(T, actual_capacity);
            return .{ .buffer = buffer, .mask = actual_capacity - 1, .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
            self.* = undefined;
        }

        pub fn capacity(self: *const Self) usize {
            return self.buffer.len;
        }

        /// Approximate during concurrent updates, always bounded by capacity.
        /// Exact when quiescent. Reading the released head first also observes
        /// the tail publication that allowed the consumer to reach that head.
        pub fn len(self: *const Self) usize {
            const head = self.consumer.position.load(.acquire);
            const tail = self.producer.position.load(.acquire);
            return @min(tail -% head, self.buffer.len);
        }

        pub fn tryPush(self: *Self, value: T) bool {
            const tail = self.producer.position.load(.monotonic);
            // A cached head is conservative: only an acquired newer head
            // authorizes reuse of additional slots, including across wrap.
            if (tail -% self.producer.cached_peer >= self.buffer.len) {
                self.producer.cached_peer = self.consumer.position.load(.acquire);
                if (tail -% self.producer.cached_peer >= self.buffer.len) return false;
            }
            self.buffer[tail & self.mask] = value;
            self.producer.position.store(tail +% 1, .release);
            return true;
        }

        pub fn tryPop(self: *Self) ?T {
            const head = self.consumer.position.load(.monotonic);
            // The cached tail authorizes only slots from an earlier acquire.
            if (head == self.consumer.cached_peer) {
                self.consumer.cached_peer = self.producer.position.load(.acquire);
                if (head == self.consumer.cached_peer) return null;
            }
            const value = self.buffer[head & self.mask];
            self.consumer.position.store(head +% 1, .release);
            return value;
        }

        /// Copy the available prefix, returning its length. The input must
        /// not alias queue storage. Producer-only; one release publishes the
        /// whole batch, and no memory is allocated.
        pub inline fn tryPushSlice(self: *Self, values: []const T) usize {
            if (values.len == 0) return 0;
            if (values.len == 1 or self.mask == 0)
                return @intFromBool(self.tryPush(values[0]));
            return self.pushSliceBatch(values);
        }

        noinline fn pushSliceBatch(self: *Self, values: []const T) usize {
            const tail = self.producer.position.load(.monotonic);
            var free = self.buffer.len - (tail -% self.producer.cached_peer);
            if (free < values.len) {
                self.producer.cached_peer = self.consumer.position.load(.acquire);
                free = self.buffer.len - (tail -% self.producer.cached_peer);
            }
            const count = @min(values.len, free);
            if (count == 0) return 0;
            const index = tail & self.mask;
            const first = @min(count, self.buffer.len - index);
            if (@sizeOf(T) <= @sizeOf(usize) and count <= 8) {
                for (values[0..count], 0..) |value, offset| self.buffer[(index + offset) & self.mask] = value;
            } else {
                @memcpy(self.buffer[index..][0..first], values[0..first]);
                @memcpy(self.buffer[0 .. count - first], values[first..count]);
            }
            self.producer.position.store(tail +% count, .release);
            return count;
        }

        /// Copy the queued prefix into output, returning its length. Output
        /// must not alias queue storage. Consumer-only; one release frees the
        /// whole batch. The unused output suffix is left untouched.
        pub inline fn tryPopSlice(self: *Self, output: []T) usize {
            if (output.len == 0) return 0;
            if (output.len == 1 or self.mask == 0) {
                output[0] = self.tryPop() orelse return 0;
                return 1;
            }
            return self.popSliceBatch(output);
        }

        noinline fn popSliceBatch(self: *Self, output: []T) usize {
            const head = self.consumer.position.load(.monotonic);
            var ready = self.consumer.cached_peer -% head;
            if (ready < output.len) {
                self.consumer.cached_peer = self.producer.position.load(.acquire);
                ready = self.consumer.cached_peer -% head;
            }
            const count = @min(output.len, ready);
            if (count == 0) return 0;
            const index = head & self.mask;
            const first = @min(count, self.buffer.len - index);
            if (@sizeOf(T) <= @sizeOf(usize) and count <= 8) {
                for (output[0..count], 0..) |*value, offset| value.* = self.buffer[(index + offset) & self.mask];
            } else {
                @memcpy(output[0..first], self.buffer[index..][0..first]);
                @memcpy(output[first..count], self.buffer[0 .. count - first]);
            }
            self.consumer.position.store(head +% count, .release);
            return count;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const spsc_count = 100_000;
test "spsc queue: single-threaded order and bounds" {
    var queue = try SpscQueue(u32).init(std.testing.allocator, 4);
    defer queue.deinit();

    try std.testing.expectEqual(@as(usize, 4), queue.capacity());
    try std.testing.expect(queue.tryPop() == null);
    for (0..4) |index| try std.testing.expect(queue.tryPush(@intCast(index)));
    try std.testing.expect(!queue.tryPush(99));
    try std.testing.expectEqual(@as(usize, 4), queue.len());
    for (0..4) |index| try std.testing.expectEqual(@as(u32, @intCast(index)), queue.tryPop().?);
    try std.testing.expect(queue.tryPop() == null);
}

test "spsc queue: capacity boundaries and cached cursors survive wraparound" {
    for ([_]usize{ 0, 1, 2, 3, 8, 1024 }) |requested| {
        var queue = try SpscQueue(u32).init(std.testing.allocator, requested);
        defer queue.deinit();
        const origin = std.math.maxInt(usize) - 5;
        queue.consumer = .{ .position = .init(origin), .cached_peer = origin };
        queue.producer = .{ .position = .init(origin), .cached_peer = origin };
        var next_push: u32 = 0;
        var next_pop: u32 = 0;
        var count: usize = 0;
        var random = std.Random.DefaultPrng.init(0x73707363);
        // Always cross the integer boundary, including for singleton queues.
        for (0..16) |_| {
            for (0..queue.capacity()) |_| {
                try std.testing.expect(queue.tryPush(next_push));
                next_push += 1;
            }
            try std.testing.expect(!queue.tryPush(next_push));
            try std.testing.expectEqual(queue.capacity(), queue.len());
            for (0..queue.capacity()) |_| {
                try std.testing.expectEqual(next_pop, queue.tryPop().?);
                next_pop += 1;
            }
            try std.testing.expect(queue.tryPop() == null);
        }
        // Partial fills/drains exercise refreshes with unread cached slots.
        for (0..5000) |_| {
            if (random.random().boolean()) {
                const pushed = queue.tryPush(next_push);
                try std.testing.expectEqual(count < queue.capacity(), pushed);
                if (pushed) {
                    next_push += 1;
                    count += 1;
                }
            } else {
                const value = queue.tryPop();
                try std.testing.expectEqual(count > 0, value != null);
                if (value) |actual| {
                    try std.testing.expectEqual(next_pop, actual);
                    next_pop += 1;
                    count -= 1;
                }
            }
            try std.testing.expectEqual(count, queue.len());
        }
        while (queue.tryPop()) |value| {
            try std.testing.expectEqual(next_pop, value);
            next_pop += 1;
        }
        try std.testing.expectEqual(next_push, next_pop);
        try std.testing.expectEqual(@as(usize, 0), queue.len());
    }
}

test "spsc queue: mixed slice and scalar transfers match FIFO through wrap" {
    for ([_]usize{ 0, 1, 2, 3, 8, 64 }) |requested| {
        var queue = try SpscQueue(u32).init(std.testing.allocator, requested);
        defer queue.deinit();
        const origin = std.math.maxInt(usize) - 5;
        queue.consumer = .{ .position = .init(origin), .cached_peer = origin };
        queue.producer = .{ .position = .init(origin), .cached_peer = origin };
        var next_push: u32 = 0;
        var next_pop: u32 = 0;
        var count: usize = 0;
        var random = std.Random.DefaultPrng.init(0x6261746368);
        for (0..5000) |_| {
            const length = random.random().uintLessThan(usize, 18);
            if (random.random().boolean()) {
                var input: [17]u32 = undefined;
                for (input[0..length], 0..) |*item, offset| item.* = next_push + @as(u32, @intCast(offset));
                const pushed = if (length == 1) @intFromBool(queue.tryPush(next_push)) else queue.tryPushSlice(input[0..length]);
                try std.testing.expectEqual(@min(length, queue.capacity() - count), pushed);
                next_push += @intCast(pushed);
                count += pushed;
            } else {
                var output = [_]u32{std.math.maxInt(u32)} ** 17;
                const popped: usize = if (length == 1) blk: {
                    output[0] = queue.tryPop() orelse break :blk 0;
                    break :blk 1;
                } else queue.tryPopSlice(output[0..length]);
                try std.testing.expectEqual(@min(length, count), popped);
                for (output[0..popped]) |value| {
                    try std.testing.expectEqual(next_pop, value);
                    next_pop += 1;
                }
                for (output[popped..]) |value| try std.testing.expectEqual(std.math.maxInt(u32), value);
                count -= popped;
            }
            try std.testing.expectEqual(count, queue.len());
        }
        while (queue.tryPop()) |value| {
            try std.testing.expectEqual(next_pop, value);
            next_pop += 1;
        }
        try std.testing.expectEqual(next_push, next_pop);
    }
}

test "spsc queue: slice transfers support empty elements" {
    var queue = try SpscQueue(void).init(std.testing.allocator, 4);
    defer queue.deinit();
    const input = [_]void{ {}, {}, {}, {}, {} };
    var output: [5]void = undefined;
    try std.testing.expectEqual(@as(usize, 4), queue.tryPushSlice(&input));
    try std.testing.expectEqual(@as(usize, 0), queue.tryPushSlice(&input));
    try std.testing.expectEqual(@as(usize, 4), queue.tryPopSlice(&output));
    try std.testing.expectEqual(@as(usize, 0), queue.tryPopSlice(&output));
}

test "spsc queue: concurrent mixed batch transfer and length observer" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const total = 50_000;
    const State = struct {
        queue: SpscQueue(u32),
        done: std.atomic.Value(bool) = .init(false),
        bad_order: bool = false,
        checksum: u64 = 0,

        fn produce(self: *@This()) void {
            var next: u32 = 0;
            var input: [31]u32 = undefined;
            while (next < total) {
                if (next % 5 == 0) {
                    if (self.queue.tryPush(next)) next += 1 else std.atomic.spinLoopHint();
                } else {
                    const length = @min(input.len, total - next);
                    for (input[0..length], 0..) |*item, offset| item.* = next + @as(u32, @intCast(offset));
                    const pushed = self.queue.tryPushSlice(input[0..length]);
                    next += @intCast(pushed);
                    if (pushed == 0) std.atomic.spinLoopHint();
                }
            }
        }
        fn consume(self: *@This()) void {
            var next: u32 = 0;
            var output: [7]u32 = undefined;
            while (next < total) {
                const length: usize = if (next % 5 == 0) 1 else @min(output.len, total - next);
                const popped = self.queue.tryPopSlice(output[0..length]);
                for (output[0..popped]) |value| {
                    self.bad_order = self.bad_order or value != next;
                    self.checksum += value;
                    next += 1;
                }
                if (popped == 0) std.atomic.spinLoopHint();
            }
            self.done.store(true, .release);
        }
    };
    for ([_]usize{ 1, 2, 8, 64, 1024 }) |capacity| {
        for (0..2) |_| {
            var state = State{ .queue = try SpscQueue(u32).init(std.testing.allocator, capacity) };
            defer state.queue.deinit();
            const origin = std.math.maxInt(usize) - 5;
            state.queue.consumer = .{ .position = .init(origin), .cached_peer = origin };
            state.queue.producer = .{ .position = .init(origin), .cached_peer = origin };
            const producer = try std.Thread.spawn(.{}, State.produce, .{&state});
            const consumer = try std.Thread.spawn(.{}, State.consume, .{&state});
            var too_large = false;
            while (!state.done.load(.acquire)) {
                too_large = too_large or state.queue.len() > state.queue.capacity();
                std.atomic.spinLoopHint();
            }
            producer.join();
            consumer.join();
            try std.testing.expect(!too_large);
            try std.testing.expect(!state.bad_order);
            try std.testing.expectEqual(@as(u64, total) * (total - 1) / 2, state.checksum);
            try std.testing.expectEqual(@as(usize, 0), state.queue.len());
        }
    }
}

test "spsc queue: concurrent observer length stays within capacity" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const State = struct {
        queue: SpscQueue(u32),
        done: std.atomic.Value(bool) = .init(false),
        bad_value: std.atomic.Value(bool) = .init(false),

        fn produce(self: *@This()) void {
            for (0..100_000) |index| {
                while (!self.queue.tryPush(@intCast(index))) std.atomic.spinLoopHint();
            }
        }
        fn consume(self: *@This()) void {
            var received: u32 = 0;
            while (received < 100_000) {
                if (self.queue.tryPop()) |value| {
                    if (value != received) self.bad_value.store(true, .monotonic);
                    received += 1;
                } else std.atomic.spinLoopHint();
            }
            self.done.store(true, .release);
        }
    };
    for ([_]usize{ 1, 16 }) |capacity| {
        var state = State{ .queue = try SpscQueue(u32).init(std.testing.allocator, capacity) };
        defer state.queue.deinit();
        const producer = try std.Thread.spawn(.{}, State.produce, .{&state});
        const consumer = try std.Thread.spawn(.{}, State.consume, .{&state});
        var exceeded = false;
        while (!state.done.load(.acquire)) {
            if (state.queue.len() > state.queue.capacity()) exceeded = true;
            std.atomic.spinLoopHint();
        }
        producer.join();
        consumer.join();
        try std.testing.expect(!exceeded);
        try std.testing.expect(!state.bad_value.load(.monotonic));
        try std.testing.expectEqual(@as(usize, 0), state.queue.len());
    }
}

test "spsc queue: repeated threaded FIFO across capacities and counter wrap" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const Producer = struct {
        fn run(q: *SpscQueue(u32)) void {
            var index: u32 = 0;
            while (index < spsc_count) {
                if (q.tryPush(index)) {
                    index += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };
    for ([_]usize{ 1, 2, 16, 1024 }) |capacity| {
        for (0..2) |_| {
            var queue = try SpscQueue(u32).init(std.testing.allocator, capacity);
            defer queue.deinit();
            const origin = std.math.maxInt(usize) - 5;
            queue.consumer = .{ .position = .init(origin), .cached_peer = origin };
            queue.producer = .{ .position = .init(origin), .cached_peer = origin };
            const thread = try std.Thread.spawn(.{}, Producer.run, .{&queue});
            var received: u32 = 0;
            var bad_order = false;
            var checksum: u64 = 0;
            while (received < spsc_count) {
                if (queue.tryPop()) |value| {
                    bad_order = bad_order or value != received;
                    checksum += value;
                    received += 1;
                } else std.atomic.spinLoopHint();
            }
            thread.join();
            try std.testing.expect(!bad_order);
            try std.testing.expectEqual(@as(u64, spsc_count) * (spsc_count - 1) / 2, checksum);
            try std.testing.expectEqual(@as(usize, 0), queue.len());
        }
    }
}
