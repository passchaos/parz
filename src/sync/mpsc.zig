//! Bounded multi-producer/single-consumer ring buffer.

const std = @import("std");
const builtin = @import("builtin");

/// Bounded multi-producer/single-consumer ring buffer (Vyukov-style slots).
pub fn MpscQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        const Slot = struct {
            sequence: std.atomic.Value(usize),
            value: T,
        };

        buffer: []Slot,
        mask: usize,
        enqueue_pos: std.atomic.Value(usize) align(std.atomic.cache_line) = .init(0),
        dequeue_pos: usize align(std.atomic.cache_line) = 0,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, requested_capacity: usize) !Self {
            const actual_capacity = std.math.ceilPowerOfTwo(usize, @max(requested_capacity, 1)) catch
                return error.CapacityOverflow;
            const buffer = try allocator.alloc(Slot, actual_capacity);
            for (buffer, 0..) |*slot, index| {
                slot.* = .{ .sequence = .init(index), .value = undefined };
            }
            return .{
                .buffer = buffer,
                .mask = actual_capacity - 1,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
            self.* = undefined;
        }

        pub fn capacity(self: *const Self) usize {
            return self.buffer.len;
        }

        pub fn tryPush(self: *Self, value: T) bool {
            // A one-slot ring needs distinct empty/reserved/ready states:
            // the usual sequence numbers coincide for "published at pos"
            // and "free for pos + 1" when capacity is one.
            if (self.mask == 0) {
                const slot = &self.buffer[0];
                if (slot.sequence.cmpxchgStrong(0, 1, .acquire, .monotonic) != null) return false;
                slot.value = value;
                slot.sequence.store(2, .release);
                return true;
            }
            var pos = self.enqueue_pos.load(.monotonic);
            while (true) {
                const slot = &self.buffer[pos & self.mask];
                const seq = slot.sequence.load(.acquire);
                const dif = @as(isize, @bitCast(seq -% pos));
                if (dif == 0) {
                    if (self.enqueue_pos.cmpxchgWeak(
                        pos,
                        pos +% 1,
                        .monotonic,
                        .monotonic,
                    )) |actual| {
                        pos = actual;
                        continue;
                    }
                    slot.value = value;
                    slot.sequence.store(pos +% 1, .release);
                    return true;
                }
                if (dif < 0) return false;
                pos = self.enqueue_pos.load(.monotonic);
            }
        }

        /// Reserve and publish an available prefix with one enqueue CAS for
        /// capacities >= 4. Tiny queues use at most two scalar operations.
        /// Concurrent producers may reserve later prefixes while an earlier
        /// producer is still publishing. FIFO follows reservation order; the
        /// consumer stops at the first unpublished slot. Input must not alias
        /// queue storage. No memory is allocated.
        pub inline fn tryPushSlice(self: *Self, values: []const T) usize {
            if (values.len == 0) return 0;
            if (values.len == 1 or self.mask == 0)
                return @intFromBool(self.tryPush(values[0]));
            if (self.mask == 1) {
                if (!self.tryPush(values[0])) return 0;
                return 1 + @as(usize, @intFromBool(self.tryPush(values[1])));
            }
            return self.pushSliceBatch(values);
        }

        noinline fn pushSliceBatch(self: *Self, values: []const T) usize {
            const limit = @min(values.len, self.buffer.len);
            var pos = self.enqueue_pos.load(.monotonic);
            retry: while (true) {
                var count: usize = 0;
                while (count < limit) : (count += 1) {
                    const position = pos +% count;
                    const sequence = self.buffer[position & self.mask].sequence.load(.acquire);
                    const difference = @as(isize, @bitCast(sequence -% position));
                    if (difference < 0) break;
                    if (difference > 0) {
                        pos = self.enqueue_pos.load(.monotonic);
                        continue :retry;
                    }
                }
                if (count == 0) return 0;
                if (self.enqueue_pos.cmpxchgWeak(pos, pos +% count, .monotonic, .monotonic)) |actual| {
                    pos = actual;
                    continue;
                }
                // The successful CAS owns every slot in this prefix. Each
                // slot retains its own release/acquire publication protocol.
                for (values[0..count], 0..) |value, offset| {
                    const position = pos +% offset;
                    const slot = &self.buffer[position & self.mask];
                    slot.value = value;
                    slot.sequence.store(position +% 1, .release);
                }
                return count;
            }
        }

        /// Single consumer only. The consumer position is a plain field, so
        /// it does not share a cache line with the producers' enqueue position.
        pub fn tryPop(self: *Self) ?T {
            if (self.mask == 0) {
                const slot = &self.buffer[0];
                if (slot.sequence.load(.acquire) != 2) return null;
                const value = slot.value;
                slot.sequence.store(0, .release);
                return value;
            }
            const pos = self.dequeue_pos;
            const slot = &self.buffer[pos & self.mask];
            if (slot.sequence.load(.acquire) != pos +% 1) return null;
            const value = slot.value;
            self.dequeue_pos = pos +% 1;
            slot.sequence.store(pos +% self.buffer.len, .release);
            return value;
        }

        /// Copy a ready prefix, stopping at the first unpublished slot.
        /// Single consumer only. Output must not alias queue storage; its
        /// unused suffix is left untouched. At most capacity items are copied
        /// per call, with no allocation. Larger queues update the consumer
        /// position once; one- and two-slot queues use scalar operations.
        pub inline fn tryPopSlice(self: *Self, output: []T) usize {
            if (output.len == 0) return 0;
            if (output.len == 1 or self.mask == 0) {
                output[0] = self.tryPop() orelse return 0;
                return 1;
            }
            if (self.mask == 1) {
                output[0] = self.tryPop() orelse return 0;
                output[1] = self.tryPop() orelse return 1;
                return 2;
            }
            return self.popSliceBatch(output);
        }

        noinline fn popSliceBatch(self: *Self, output: []T) usize {
            const limit = @min(output.len, self.buffer.len);
            const pos = self.dequeue_pos;
            var count: usize = 0;
            while (count < limit) : (count += 1) {
                const position = pos +% count;
                const slot = &self.buffer[position & self.mask];
                if (slot.sequence.load(.acquire) != position +% 1) break;
                output[count] = slot.value;
                slot.sequence.store(position +% self.buffer.len, .release);
            }
            self.dequeue_pos = pos +% count;
            return count;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const mpsc_producers = 4;
const mpsc_per_producer = 25_000;
test "mpsc queue: singleton rejects pushes until the value is consumed" {
    for ([_]usize{ 0, 1 }) |requested| {
        var queue = try MpscQueue(u32).init(std.testing.allocator, requested);
        defer queue.deinit();
        try std.testing.expectEqual(@as(usize, 1), queue.capacity());
        for (0..10) |index| {
            try std.testing.expect(queue.tryPop() == null);
            try std.testing.expect(queue.tryPush(@intCast(index)));
            try std.testing.expect(!queue.tryPush(99));
            try std.testing.expectEqual(@as(u32, @intCast(index)), queue.tryPop().?);
            try std.testing.expect(queue.tryPop() == null);
        }
    }
}

test "mpsc queue: single-threaded order and bounds" {
    var queue = try MpscQueue(u32).init(std.testing.allocator, 4);
    defer queue.deinit();

    try std.testing.expect(queue.tryPop() == null);
    for (0..4) |index| try std.testing.expect(queue.tryPush(@intCast(index)));
    try std.testing.expect(!queue.tryPush(99));
    for (0..4) |index| try std.testing.expectEqual(@as(u32, @intCast(index)), queue.tryPop().?);
    try std.testing.expect(queue.tryPop() == null);
}

fn seedMpscPosition(queue: anytype, position: usize) void {
    if (queue.capacity() == 1) return;
    queue.enqueue_pos.store(position, .monotonic);
    queue.dequeue_pos = position;
    for (0..queue.capacity()) |offset| {
        const next = position +% offset;
        queue.buffer[next & queue.mask].sequence.store(next, .monotonic);
    }
}

test "mpsc queue: mixed slice and scalar prefixes preserve FIFO across counter wrap" {
    for ([_]usize{ 0, 1, 2, 3, 8, 64 }) |capacity| {
        var queue = try MpscQueue(u64).init(std.testing.allocator, capacity);
        defer queue.deinit();
        seedMpscPosition(&queue, std.math.maxInt(usize) - 27);
        var reference: [64]u64 = undefined;
        var head: usize = 0;
        var tail: usize = 0;
        var count: usize = 0;
        var next: u64 = 0;
        var random = std.Random.DefaultPrng.init(0xb471c + capacity);
        for (0..3000) |step| {
            if (random.random().boolean()) {
                var values: [71]u64 = undefined;
                const length = random.random().uintLessThan(usize, values.len + 1);
                for (values[0..length], 0..) |*value, offset| value.* = next + offset;
                const pushed = if (step % 3 == 0 and length != 0)
                    @as(usize, @intFromBool(queue.tryPush(values[0])))
                else
                    queue.tryPushSlice(values[0..length]);
                const requested = if (step % 3 == 0 and length != 0) 1 else length;
                try std.testing.expectEqual(@min(requested, queue.capacity() - count), pushed);
                for (values[0..pushed]) |value| {
                    reference[tail % reference.len] = value;
                    tail += 1;
                    count += 1;
                }
                next += pushed;
            } else {
                var output: [73]u64 = @splat(std.math.maxInt(u64));
                const length = random.random().uintLessThan(usize, output.len + 1);
                const popped = if (step % 3 == 0 and length != 0) blk: {
                    output[0] = queue.tryPop() orelse break :blk @as(usize, 0);
                    break :blk @as(usize, 1);
                } else queue.tryPopSlice(output[0..length]);
                const requested = if (step % 3 == 0 and length != 0) 1 else length;
                try std.testing.expectEqual(@min(requested, count), popped);
                for (output[0..popped]) |value| {
                    try std.testing.expectEqual(reference[head % reference.len], value);
                    head += 1;
                    count -= 1;
                }
                for (output[popped..]) |value| try std.testing.expectEqual(std.math.maxInt(u64), value);
            }
        }
        while (count != 0) : (count -= 1) {
            try std.testing.expectEqual(reference[head % reference.len], queue.tryPop().?);
            head += 1;
        }
        try std.testing.expectEqual(@as(?u64, null), queue.tryPop());
        try std.testing.expect(queue.tryPush(123));
        try std.testing.expectEqual(@as(?u64, 123), queue.tryPop());
    }
}

test "mpsc queue: ready batches cannot skip an earlier reserved slot" {
    var queue = try MpscQueue(u64).init(std.testing.allocator, 8);
    defer queue.deinit();
    // Pause a producer after reserving slot zero, before its publication.
    queue.enqueue_pos.store(1, .monotonic);
    try std.testing.expectEqual(@as(usize, 3), queue.tryPushSlice(&.{ 11, 12, 13 }));
    var output: [8]u64 = @splat(99);
    try std.testing.expectEqual(@as(usize, 0), queue.tryPopSlice(&output));
    try std.testing.expectEqual(@as(?u64, null), queue.tryPop());
    for (output) |value| try std.testing.expectEqual(@as(u64, 99), value);
    queue.buffer[0].value = 10;
    queue.buffer[0].sequence.store(1, .release);
    try std.testing.expectEqual(@as(usize, 4), queue.tryPopSlice(&output));
    try std.testing.expectEqualSlices(u64, &.{ 10, 11, 12, 13, 99, 99, 99, 99 }, &output);
    try std.testing.expectEqual(@as(usize, 8), queue.tryPushSlice(&.{ 20, 21, 22, 23, 24, 25, 26, 27, 28 }));
    try std.testing.expectEqual(@as(usize, 8), queue.tryPopSlice(&output));
    try std.testing.expectEqualSlices(u64, &.{ 20, 21, 22, 23, 24, 25, 26, 27 }, &output);
}

test "mpsc queue: slice transfers retain aligned payloads and empty elements" {
    const Packet = struct {
        id: u64 align(64),
        bytes: [43]u8,
    };
    var queue = try MpscQueue(Packet).init(std.testing.allocator, 4);
    defer queue.deinit();
    const input = [_]Packet{ .{ .id = 5, .bytes = @splat(5) }, .{ .id = 7, .bytes = @splat(7) } };
    for (0..5) |_| {
        try std.testing.expectEqual(input.len, queue.tryPushSlice(&input));
        var output: [2]Packet = undefined;
        try std.testing.expectEqual(input.len, queue.tryPopSlice(&output));
        for (input, output) |expected, actual| {
            try std.testing.expectEqual(expected.id, actual.id);
            try std.testing.expectEqualSlices(u8, &expected.bytes, &actual.bytes);
        }
    }
    var empty = try MpscQueue(void).init(std.testing.allocator, 2);
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 2), empty.tryPushSlice(&.{ {}, {}, {} }));
    var output: [3]void = undefined;
    try std.testing.expectEqual(@as(usize, 2), empty.tryPopSlice(&output));
    try std.testing.expectEqual(@as(usize, 0), empty.tryPopSlice(&output));
}

test "mpsc queue: concurrent scalar and batch producers retain every value and producer order" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const producers = 4;
    const per_producer = 2000;
    const State = struct {
        queue: *MpscQueue(u64),
        start: std.atomic.Value(bool) = .init(false),

        fn produce(self: *@This(), id: usize) void {
            while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
            var next: usize = 0;
            while (next < per_producer) {
                var input: [31]u64 = undefined;
                const length = @min(1 + (next + id * 7) % input.len, per_producer - next);
                for (input[0..length], 0..) |*value, offset| value.* = id * per_producer + next + offset;
                const pushed = if (next % 7 == 0)
                    @as(usize, @intFromBool(self.queue.tryPush(input[0])))
                else
                    self.queue.tryPushSlice(input[0..length]);
                next += pushed;
                if (pushed == 0) std.atomic.spinLoopHint();
            }
        }
    };
    for ([_]usize{ 1, 2, 8, 1024 }) |capacity| {
        for (0..2) |_| {
            var queue = try MpscQueue(u64).init(std.testing.allocator, capacity);
            defer queue.deinit();
            seedMpscPosition(&queue, std.math.maxInt(usize) - 127);
            var state = State{ .queue = &queue };
            var threads: [producers]std.Thread = undefined;
            var spawned: usize = 0;
            defer for (threads[0..spawned]) |thread| thread.join();
            // Release any already spawned producers on a spawn failure too.
            defer state.start.store(true, .release);
            for (&threads, 0..) |*thread, id| {
                thread.* = std.Thread.spawn(.{}, State.produce, .{ &state, id }) catch |err| {
                    state.start.store(true, .release);
                    var drained: usize = 0;
                    while (drained < spawned * per_producer) {
                        if (queue.tryPop() != null) drained += 1 else std.atomic.spinLoopHint();
                    }
                    return err;
                };
                spawned += 1;
            }
            state.start.store(true, .release);
            var next: [producers]usize = @splat(0);
            var received: usize = 0;
            var checksum: u64 = 0;
            var bad_order = false;
            while (received < producers * per_producer) {
                var output: [37]u64 = undefined;
                const popped = if (received % 5 == 0) blk: {
                    output[0] = queue.tryPop() orelse break :blk @as(usize, 0);
                    break :blk @as(usize, 1);
                } else queue.tryPopSlice(&output);
                for (output[0..popped]) |value| {
                    const id = value / per_producer;
                    if (id < producers) {
                        bad_order = bad_order or value % per_producer != next[id];
                        next[id] += 1;
                    } else bad_order = true;
                    checksum += value;
                    received += 1;
                }
                if (popped == 0) std.atomic.spinLoopHint();
            }
            try std.testing.expect(!bad_order);
            for (next) |count| try std.testing.expectEqual(@as(usize, per_producer), count);
            const total = producers * per_producer;
            try std.testing.expectEqual(@as(u64, total * (total - 1) / 2), checksum);
            try std.testing.expectEqual(@as(?u64, null), queue.tryPop());
        }
    }
}

test "mpsc queue: singleton concurrent producers preserve every value and producer order" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const producers = 4;
    const count = 1000;
    const Producer = struct {
        fn run(q: *MpscQueue(u32), producer: u32) void {
            for (0..count) |index| {
                const value = producer * count + @as(u32, @intCast(index));
                while (!q.tryPush(value)) std.atomic.spinLoopHint();
            }
        }
    };
    for (0..3) |_| {
        var queue = try MpscQueue(u32).init(std.testing.allocator, 1);
        defer queue.deinit();
        var threads: [producers]std.Thread = undefined;
        for (&threads, 0..) |*thread, producer| {
            thread.* = try std.Thread.spawn(.{}, Producer.run, .{ &queue, @as(u32, @intCast(producer)) });
        }
        // Drain and join before assertions so failures cannot leave producers
        // using queue storage after the test returns.
        var received: [producers * count]u32 = undefined;
        for (&received) |*value| {
            while (true) {
                if (queue.tryPop()) |item| {
                    value.* = item;
                    break;
                }
                std.atomic.spinLoopHint();
            }
        }
        for (threads) |thread| thread.join();
        var next = [_]u32{0} ** producers;
        for (received) |value| {
            try std.testing.expect(value < producers * count);
            const producer = value / count;
            try std.testing.expectEqual(next[producer], value % count);
            next[producer] += 1;
        }
        for (next) |total| try std.testing.expectEqual(@as(u32, count), total);
        try std.testing.expect(queue.tryPop() == null);
    }
}

test "mpsc queue: threaded producers and consumer" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const producers = mpsc_producers;
    const total = mpsc_producers * mpsc_per_producer;
    var queue = try MpscQueue(u32).init(std.testing.allocator, 1024);
    defer queue.deinit();

    const Producer = struct {
        fn run(q: *MpscQueue(u32), base: u32) void {
            var index: u32 = 0;
            while (index < mpsc_per_producer) {
                if (q.tryPush(base + index)) {
                    index += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    var threads: [producers]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{ &queue, @as(u32, @intCast(index * mpsc_per_producer)) });
    }
    var seen = try std.testing.allocator.alloc(bool, total);
    defer std.testing.allocator.free(seen);
    @memset(seen, false);

    var received: usize = 0;
    while (received < total) {
        if (queue.tryPop()) |value| {
            try std.testing.expect(value < total);
            try std.testing.expect(!seen[@intCast(value)]);
            seen[@intCast(value)] = true;
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    for (threads) |thread| thread.join();
}
