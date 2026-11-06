//! Frozen SPSC baseline from efeb092, before cached peer positions.
const std = @import("std");

/// Bounded single-producer/single-consumer ring buffer.
pub fn SpscQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: []T,
        mask: usize,
        head: std.atomic.Value(usize) = .init(0),
        tail: std.atomic.Value(usize) = .init(0),
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
            const head = self.head.load(.acquire);
            const tail = self.tail.load(.acquire);
            return @min(tail -% head, self.buffer.len);
        }

        pub fn tryPush(self: *Self, value: T) bool {
            const tail = self.tail.load(.monotonic);
            const head = self.head.load(.acquire);
            if (tail -% head >= self.buffer.len) return false;
            self.buffer[tail & self.mask] = value;
            self.tail.store(tail +% 1, .release);
            return true;
        }

        pub fn tryPop(self: *Self) ?T {
            const head = self.head.load(.monotonic);
            const tail = self.tail.load(.acquire);
            if (head == tail) return null;
            const value = self.buffer[head & self.mask];
            self.head.store(head +% 1, .release);
            return value;
        }
    };
}
