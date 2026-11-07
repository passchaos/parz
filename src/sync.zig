//! Standalone synchronization primitives.
//!
//! This module is intentionally independent of the scheduler. Queues and the
//! stack are non-blocking; semaphores and wait groups use `std.Io` for
//! blocking. All containers are bounded and allocate only in `init`.

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
    };
}

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
    };
}

/// Multi-producer/single-consumer Treiber stack. Nodes are caller-owned.
///
/// With one consumer, ABA cannot occur: producers only push, and the consumer
/// is the only thread that removes a node, so a head pointer cannot be popped
/// and re-pushed between the consumer's load and store.
pub fn TreiberStack(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            next: ?*Node = null,
            value: T,
        };

        head: std.atomic.Value(usize) = .init(0),
        count: std.atomic.Value(usize) = .init(0),

        pub fn push(self: *Self, node: *Node) void {
            // Reserve the count before publishing the node. A consumer can
            // pop immediately after the head CAS, so accounting afterwards
            // would allow its decrement to wrap through zero.
            _ = self.count.fetchAdd(1, .monotonic);
            var old = self.head.load(.monotonic);
            while (true) {
                node.next = if (old == 0) null else @as(*Node, @ptrFromInt(old));
                if (self.head.cmpxchgWeak(
                    old,
                    @intFromPtr(node),
                    .release,
                    .monotonic,
                ) == null) {
                    return;
                }
                old = self.head.load(.monotonic);
            }
        }

        /// Single consumer only.
        pub fn pop(self: *Self) ?*Node {
            var old = self.head.load(.acquire);
            while (old != 0) {
                const node: *Node = @ptrFromInt(old);
                const next: usize = if (node.next) |n| @intFromPtr(n) else 0;
                if (self.head.cmpxchgWeak(old, next, .acq_rel, .acquire) == null) {
                    _ = self.count.fetchSub(1, .monotonic);
                    return node;
                }
                old = self.head.load(.acquire);
            }
            return null;
        }

        /// Includes pushes being published; exact when quiescent.
        pub fn len(self: *const Self) usize {
            return self.count.load(.monotonic);
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.head.load(.acquire) == 0;
        }
    };
}

/// Counting semaphore. `wait` may be cancelled by the supplied `std.Io`.
pub const Semaphore = struct {
    inner: std.Io.Semaphore = .{},

    pub fn wait(self: *Semaphore, io: std.Io) std.Io.Cancelable!void {
        try self.inner.wait(io);
    }

    pub fn waitUncancelable(self: *Semaphore, io: std.Io) void {
        self.inner.waitUncancelable(io);
    }

    pub fn post(self: *Semaphore, io: std.Io) void {
        self.inner.post(io);
    }
};

/// Wait for a set of tasks to finish. `add` before starting them; each task
/// calls `done` exactly once.
pub const WaitGroup = struct {
    mutex: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    count: usize = 0,

    pub fn add(self: *WaitGroup, io: std.Io, n: usize) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        self.count += n;
    }

    pub fn done(self: *WaitGroup, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        std.debug.assert(self.count > 0);
        self.count -= 1;
        if (self.count == 0) self.cond.broadcast(io);
    }

    pub fn wait(self: *WaitGroup, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        while (self.count != 0) self.cond.waitUncancelable(io, &self.mutex);
    }
};

// ---------------------------------------------------------------------------
// Tests

const spsc_count = 100_000;
const mpsc_producers = 4;
const mpsc_per_producer = 25_000;
const stack_producers = 4;
const stack_per_producer = 10_000;

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

test "treiber stack: single-threaded order" {
    var stack = TreiberStack(u32){};
    var nodes: [4]TreiberStack(u32).Node = undefined;
    for (&nodes, 0..) |*node, index| {
        node.* = .{ .value = @intCast(index) };
        stack.push(node);
    }
    try std.testing.expectEqual(@as(usize, 4), stack.len());
    var expected: u32 = 3;
    while (stack.pop()) |node| {
        try std.testing.expectEqual(expected, node.value);
        expected -%= 1;
    }
    try std.testing.expect(stack.isEmpty());
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

test "treiber stack: concurrent length does not underflow" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const total = 20_000;
    const Stack = TreiberStack(u32);
    const State = struct {
        stack: Stack = .{},
        nodes: []Stack.Node,
        done: std.atomic.Value(bool) = .init(false),
        sum: u64 = 0,

        fn produce(self: *@This()) void {
            for (self.nodes, 0..) |*node, index| {
                node.* = .{ .value = @intCast(index) };
                self.stack.push(node);
                if (index % 8 == 0) std.atomic.spinLoopHint();
            }
        }
        fn consume(self: *@This()) void {
            var received: usize = 0;
            while (received < total) {
                if (self.stack.pop()) |node| {
                    self.sum += node.value;
                    received += 1;
                } else std.atomic.spinLoopHint();
            }
            self.done.store(true, .release);
        }
    };
    const nodes = try std.testing.allocator.alloc(Stack.Node, total);
    defer std.testing.allocator.free(nodes);
    for (0..5) |_| {
        var state = State{ .nodes = nodes };
        const producer = try std.Thread.spawn(.{}, State.produce, .{&state});
        const consumer = try std.Thread.spawn(.{}, State.consume, .{&state});
        var underflow = false;
        while (!state.done.load(.acquire)) {
            if (state.stack.len() > total) underflow = true;
            std.atomic.spinLoopHint();
        }
        producer.join();
        consumer.join();
        try std.testing.expect(!underflow);
        try std.testing.expectEqual(@as(usize, 0), state.stack.len());
        try std.testing.expectEqual(@as(u64, total) * (total - 1) / 2, state.sum);
    }
}

test "treiber stack: threaded producers and consumer" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const producers = stack_producers;
    const total = stack_producers * stack_per_producer;
    var stack = TreiberStack(u32){};
    const nodes = try std.testing.allocator.alloc(TreiberStack(u32).Node, total);
    defer std.testing.allocator.free(nodes);

    const Producer = struct {
        fn run(s: *TreiberStack(u32), slice: []TreiberStack(u32).Node, base: u32) void {
            for (slice, 0..) |*node, index| {
                node.* = .{ .value = base + @as(u32, @intCast(index)) };
                s.push(node);
            }
        }
    };

    var threads: [producers]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| {
        const base = @as(u32, @intCast(index * stack_per_producer));
        const slice = nodes[index * stack_per_producer ..][0..stack_per_producer];
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{ &stack, slice, base });
    }

    var seen = try std.testing.allocator.alloc(bool, total);
    defer std.testing.allocator.free(seen);
    @memset(seen, false);

    var received: usize = 0;
    while (received < total) {
        if (stack.pop()) |node| {
            try std.testing.expect(node.value < total);
            try std.testing.expect(!seen[@intCast(node.value)]);
            seen[@intCast(node.value)] = true;
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    for (threads) |thread| thread.join();
    try std.testing.expect(stack.isEmpty());
}

test "semaphore wakes a waiter" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = std.testing.io;
    var semaphore = Semaphore{};
    const Worker = struct {
        fn run(sem: *Semaphore) void {
            sem.waitUncancelable(std.testing.io);
        }
    };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&semaphore});
    semaphore.post(io);
    thread.join();
}

test "wait group waits for all members" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = std.testing.io;
    const members = 4;
    var group = WaitGroup{};
    group.add(io, members);
    const Worker = struct {
        fn run(wg: *WaitGroup) void {
            wg.done(std.testing.io);
        }
    };
    var threads: [members]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Worker.run, .{&group});
    group.wait(io);
    for (threads) |thread| thread.join();
}

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
