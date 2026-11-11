//! Bounded blocking multi-producer/multi-consumer queue.

const std = @import("std");
const builtin = @import("builtin");

/// Bounded blocking multi-producer/multi-consumer queue. `put` and `get`
/// wait on `std.Io` conditions; `tryPut`/`tryGet` are non-blocking.
pub fn BlockingQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: []T,
        mask: usize,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,
        mutex: std.Io.Mutex = .init,
        not_empty: std.Io.Condition = .init,
        not_full: std.Io.Condition = .init,
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

        pub fn len(self: *Self, io: std.Io) usize {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            return self.count;
        }

        pub fn tryPut(self: *Self, io: std.Io, value: T) bool {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            if (self.count == self.buffer.len) return false;
            self.buffer[self.tail] = value;
            self.tail = (self.tail + 1) & self.mask;
            self.count += 1;
            self.not_empty.signal(io);
            return true;
        }

        /// Non-blocking partial batch put. The input must not alias queue
        /// storage. Returns the accepted prefix and locks only once.
        pub fn tryPutSlice(self: *Self, io: std.Io, values: []const T) usize {
            if (values.len == 0) return 0;
            if (values.len == 1 or self.mask == 0)
                return @intFromBool(self.tryPut(io, values[0]));
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            return self.putSliceLocked(io, values);
        }

        pub fn put(self: *Self, io: std.Io, value: T) std.Io.Cancelable!void {
            try self.mutex.lock(io);
            defer self.mutex.unlock(io);
            while (self.count == self.buffer.len) {
                try self.not_full.wait(io, &self.mutex);
            }
            self.buffer[self.tail] = value;
            self.tail = (self.tail + 1) & self.mask;
            self.count += 1;
            self.not_empty.signal(io);
        }

        /// Wait for at least one free slot, then put the available input
        /// prefix. Returning a count makes partial progress explicit if a
        /// caller loops and a later wait is cancelled.
        pub fn putSlice(self: *Self, io: std.Io, values: []const T) std.Io.Cancelable!usize {
            if (values.len == 0) return 0;
            if (values.len == 1 or self.mask == 0) {
                try self.put(io, values[0]);
                return 1;
            }
            try self.mutex.lock(io);
            defer self.mutex.unlock(io);
            while (self.count == self.buffer.len) {
                try self.not_full.wait(io, &self.mutex);
            }
            return self.putSliceLocked(io, values);
        }

        pub fn tryGet(self: *Self, io: std.Io) ?T {
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            if (self.count == 0) return null;
            const value = self.buffer[self.head];
            self.head = (self.head + 1) & self.mask;
            self.count -= 1;
            self.not_full.signal(io);
            return value;
        }

        /// Non-blocking partial batch get. The unused output suffix is left
        /// untouched. Returns the copied prefix and locks only once.
        pub fn tryGetSlice(self: *Self, io: std.Io, output: []T) usize {
            if (output.len == 0) return 0;
            if (output.len == 1 or self.mask == 0) {
                output[0] = self.tryGet(io) orelse return 0;
                return 1;
            }
            self.mutex.lockUncancelable(io);
            defer self.mutex.unlock(io);
            return self.getSliceLocked(io, output);
        }

        pub fn get(self: *Self, io: std.Io) std.Io.Cancelable!T {
            try self.mutex.lock(io);
            defer self.mutex.unlock(io);
            while (self.count == 0) {
                try self.not_empty.wait(io, &self.mutex);
            }
            const value = self.buffer[self.head];
            self.head = (self.head + 1) & self.mask;
            self.count -= 1;
            self.not_full.signal(io);
            return value;
        }

        /// Wait for at least one queued value, then copy the available output
        /// prefix. The unused suffix is left untouched.
        pub fn getSlice(self: *Self, io: std.Io, output: []T) std.Io.Cancelable!usize {
            if (output.len == 0) return 0;
            if (output.len == 1 or self.mask == 0) {
                output[0] = try self.get(io);
                return 1;
            }
            try self.mutex.lock(io);
            defer self.mutex.unlock(io);
            while (self.count == 0) {
                try self.not_empty.wait(io, &self.mutex);
            }
            return self.getSliceLocked(io, output);
        }

        fn putSliceLocked(self: *Self, io: std.Io, values: []const T) usize {
            const count = @min(values.len, self.buffer.len - self.count);
            if (count == 0) return 0;
            const first = @min(count, self.buffer.len - self.tail);
            @memcpy(self.buffer[self.tail..][0..first], values[0..first]);
            @memcpy(self.buffer[0 .. count - first], values[first..count]);
            self.tail = (self.tail + count) & self.mask;
            self.count += count;
            if (count == 1) self.not_empty.signal(io) else self.not_empty.broadcast(io);
            return count;
        }

        fn getSliceLocked(self: *Self, io: std.Io, output: []T) usize {
            const count = @min(output.len, self.count);
            if (count == 0) return 0;
            const first = @min(count, self.buffer.len - self.head);
            @memcpy(output[0..first], self.buffer[self.head..][0..first]);
            @memcpy(output[first..count], self.buffer[0 .. count - first]);
            self.head = (self.head + count) & self.mask;
            self.count -= count;
            if (count == 1) self.not_full.signal(io) else self.not_full.broadcast(io);
            return count;
        }
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "blocking queue: single-threaded order and bounds" {
    const io = std.testing.io;
    var queue = try BlockingQueue(u32).init(std.testing.allocator, 4);
    defer queue.deinit();

    try std.testing.expect(queue.tryGet(io) == null);
    for (0..4) |index| try std.testing.expect(queue.tryPut(io, @intCast(index)));
    try std.testing.expect(!queue.tryPut(io, 99));
    try std.testing.expectEqual(@as(usize, 4), queue.len(io));
    for (0..4) |index| try std.testing.expectEqual(@as(u32, @intCast(index)), queue.tryGet(io).?);
    try std.testing.expect(queue.tryGet(io) == null);
}

test "blocking queue cancelled waits remove registration and preserve mutex reuse" {
    const Stub = struct {
        fn cancel(_: ?*anyopaque, _: *const u32, _: u32, _: std.Io.Timeout) std.Io.Cancelable!void {
            return error.Canceled;
        }
    };
    var vtable = std.testing.io.vtable.*;
    vtable.futexWait = Stub.cancel;
    const io = std.Io{ .userdata = std.testing.io.userdata, .vtable = &vtable };
    var queue = try BlockingQueue(u32).init(std.testing.allocator, 1);
    defer queue.deinit();
    var output: [2]u32 = undefined;
    try std.testing.expectError(error.Canceled, queue.get(io));
    try std.testing.expectError(error.Canceled, queue.getSlice(io, &output));
    try std.testing.expectEqual(@as(u16, 0), queue.not_empty.state.load(.monotonic).waiters);
    try queue.put(std.testing.io, 1);
    try std.testing.expectError(error.Canceled, queue.put(io, 2));
    try std.testing.expectError(error.Canceled, queue.putSlice(io, &.{ 2, 3 }));
    try std.testing.expectEqual(@as(u16, 0), queue.not_full.state.load(.monotonic).waiters);
    try std.testing.expectEqual(@as(u32, 1), try queue.get(std.testing.io));
    try queue.put(std.testing.io, 4);
    try std.testing.expectEqual(@as(u32, 4), try queue.get(std.testing.io));
}

test "blocking batch wakes every blocked reader and writer without stranding" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const Q = BlockingQueue(u32);
    const Run = struct {
        fn reader(q: *Q, out: *u32) void {
            out.* = q.get(std.testing.io) catch unreachable;
        }
        fn writer(q: *Q, value: u32) void {
            q.put(std.testing.io, value) catch unreachable;
        }
        fn wait(q: *Q, readers: bool) !void {
            for (0..20000) |_| {
                q.mutex.lockUncancelable(std.testing.io);
                const count = if (readers) q.not_empty.state.load(.monotonic).waiters else q.not_full.state.load(.monotonic).waiters;
                q.mutex.unlock(std.testing.io);
                if (count == 2) return;
                try std.testing.io.sleep(std.Io.Duration.fromMilliseconds(1), .awake);
            }
            return error.WaiterTimeout;
        }
    };
    var q = try Q.init(std.testing.allocator, 2);
    defer q.deinit();
    var output: [2]u32 = undefined;
    const a = try std.Thread.spawn(.{}, Run.reader, .{ &q, &output[0] });
    const b = try std.Thread.spawn(.{}, Run.reader, .{ &q, &output[1] });
    try Run.wait(&q, true);
    try std.testing.expectEqual(@as(usize, 2), try q.putSlice(std.testing.io, &.{ 1, 2 }));
    a.join();
    b.join();
    try std.testing.expectEqual(@as(u32, 3), output[0] + output[1]);
    try std.testing.expectEqual(@as(u16, 0), q.not_empty.state.load(.monotonic).waiters);
    try std.testing.expectEqual(@as(usize, 2), try q.putSlice(std.testing.io, &.{ 3, 4 }));
    const c = try std.Thread.spawn(.{}, Run.writer, .{ &q, @as(u32, 5) });
    const d = try std.Thread.spawn(.{}, Run.writer, .{ &q, @as(u32, 6) });
    try Run.wait(&q, false);
    try std.testing.expectEqual(@as(usize, 2), try q.getSlice(std.testing.io, &output));
    c.join();
    d.join();
    try std.testing.expectEqual(@as(u16, 0), q.not_full.state.load(.monotonic).waiters);
    try std.testing.expectEqual(@as(usize, 2), try q.getSlice(std.testing.io, &output));
    try std.testing.expectEqual(@as(u32, 11), output[0] + output[1]);
}

test "blocking queue: mixed slice transfers handle partial prefixes and wrap" {
    const io = std.testing.io;
    var queue = try BlockingQueue(u32).init(std.testing.allocator, 4);
    defer queue.deinit();

    const input = [_]u32{ 0, 1, 2, 3, 4, 5, 6 };
    var empty: [0]u32 = .{};
    try std.testing.expectEqual(@as(usize, 0), queue.tryPutSlice(io, input[0..0]));
    try std.testing.expectEqual(@as(usize, 0), queue.tryGetSlice(io, &empty));
    try std.testing.expectEqual(@as(usize, 4), queue.tryPutSlice(io, &input));
    try std.testing.expectEqual(@as(usize, 0), queue.tryPutSlice(io, input[4..]));

    var first = [_]u32{std.math.maxInt(u32)} ** 4;
    try std.testing.expectEqual(@as(usize, 3), queue.tryGetSlice(io, first[0..3]));
    try std.testing.expectEqualSlices(u32, input[0..3], first[0..3]);
    try std.testing.expectEqual(std.math.maxInt(u32), first[3]);
    try std.testing.expectEqual(@as(usize, 2), queue.tryPutSlice(io, input[4..6]));

    var wrapped = [_]u32{std.math.maxInt(u32)} ** 5;
    try std.testing.expectEqual(@as(usize, 3), queue.tryGetSlice(io, &wrapped));
    try std.testing.expectEqualSlices(u32, &.{ 3, 4, 5 }, wrapped[0..3]);
    for (wrapped[3..]) |value| try std.testing.expectEqual(std.math.maxInt(u32), value);

    try std.testing.expect(queue.tryPut(io, 6));
    try std.testing.expectEqual(@as(usize, 1), try queue.getSlice(io, wrapped[0..2]));
    try std.testing.expectEqual(@as(u32, 6), wrapped[0]);
    try std.testing.expectEqual(@as(usize, 0), queue.len(io));
}

test "blocking queue: threaded producers and consumers" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const producers = 2;
    const consumers = 2;
    const per_producer = 10_000;
    const total = producers * per_producer;
    const per_consumer = total / consumers;

    var queue = try BlockingQueue(u32).init(std.testing.allocator, 128);
    defer queue.deinit();

    const seen = try std.testing.allocator.alloc(std.atomic.Value(bool), total);
    defer std.testing.allocator.free(seen);
    for (seen) |*slot| slot.* = .init(false);

    const Producer = struct {
        fn run(q: *BlockingQueue(u32), base: u32) void {
            for (0..per_producer) |index| {
                q.put(std.testing.io, base + @as(u32, @intCast(index))) catch unreachable;
            }
        }
    };
    const Consumer = struct {
        fn run(q: *BlockingQueue(u32), flags: []std.atomic.Value(bool)) void {
            for (0..per_consumer) |_| {
                const value = q.get(std.testing.io) catch unreachable;
                std.debug.assert(value < total);
                std.debug.assert(!flags[value].swap(true, .monotonic));
            }
        }
    };

    var producer_threads: [producers]std.Thread = undefined;
    for (&producer_threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{
            &queue,
            @as(u32, @intCast(index * per_producer)),
        });
    }
    var consumer_threads: [consumers]std.Thread = undefined;
    for (&consumer_threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Consumer.run, .{ &queue, seen });
    }
    for (producer_threads) |thread| thread.join();
    for (consumer_threads) |thread| thread.join();

    for (seen) |slot| try std.testing.expect(slot.load(.monotonic));
}

test "blocking queue: threaded batch producers and consumers" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const producers = 2;
    const consumers = 2;
    const per_producer = 20_000;
    const total = producers * per_producer;
    const per_consumer = total / consumers;

    var queue = try BlockingQueue(u32).init(std.testing.allocator, 128);
    defer queue.deinit();
    const seen = try std.testing.allocator.alloc(std.atomic.Value(bool), total);
    defer std.testing.allocator.free(seen);
    for (seen) |*slot| slot.* = .init(false);

    const Producer = struct {
        fn run(q: *BlockingQueue(u32), base: u32) void {
            var next: usize = 0;
            var values: [17]u32 = undefined;
            while (next < per_producer) {
                const length = @min(values.len, per_producer - next);
                for (values[0..length], 0..) |*value, offset| value.* = base + @as(u32, @intCast(next + offset));
                next += q.putSlice(std.testing.io, values[0..length]) catch unreachable;
            }
        }
    };
    const Consumer = struct {
        fn run(q: *BlockingQueue(u32), flags: []std.atomic.Value(bool)) void {
            var received: usize = 0;
            var values: [13]u32 = undefined;
            while (received < per_consumer) {
                const length = @min(values.len, per_consumer - received);
                const count = q.getSlice(std.testing.io, values[0..length]) catch unreachable;
                for (values[0..count]) |value| {
                    std.debug.assert(value < total);
                    std.debug.assert(!flags[value].swap(true, .monotonic));
                }
                received += count;
            }
        }
    };

    var producer_threads: [producers]std.Thread = undefined;
    for (&producer_threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{
            &queue,
            @as(u32, @intCast(index * per_producer)),
        });
    }
    var consumer_threads: [consumers]std.Thread = undefined;
    for (&consumer_threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Consumer.run, .{ &queue, seen });
    }
    for (producer_threads) |thread| thread.join();
    for (consumer_threads) |thread| thread.join();

    for (seen) |slot| try std.testing.expect(slot.load(.monotonic));
    try std.testing.expectEqual(@as(usize, 0), queue.len(std.testing.io));
}
