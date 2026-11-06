//! Standalone synchronization primitives.
//!
//! This module is intentionally independent of the scheduler. Queues and the
//! stack are non-blocking; semaphores and wait groups use `std.Io` for
//! blocking. All containers are bounded and allocate only in `init`.

const std = @import("std");
const builtin = @import("builtin");

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

        pub fn len(self: *const Self) usize {
            return self.tail.load(.monotonic) -% self.head.load(.acquire);
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
            var pos = self.dequeue_pos;
            while (true) {
                const slot = &self.buffer[pos & self.mask];
                const seq = slot.sequence.load(.acquire);
                const dif = @as(isize, @bitCast(seq -% (pos +% 1)));
                if (dif == 0) {
                    self.dequeue_pos = pos +% 1;
                    const value = slot.value;
                    slot.sequence.store(pos +% self.buffer.len, .release);
                    return value;
                }
                if (dif < 0) return null;
                pos = self.dequeue_pos;
            }
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
            var old = self.head.load(.monotonic);
            while (true) {
                node.next = if (old == 0) null else @as(*Node, @ptrFromInt(old));
                if (self.head.cmpxchgWeak(
                    old,
                    @intFromPtr(node),
                    .release,
                    .monotonic,
                ) == null) {
                    _ = self.count.fetchAdd(1, .monotonic);
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

test "spsc queue: threaded producer and consumer" {
    if (builtin.single_threaded) return error.SkipZigTest;

    var queue = try SpscQueue(u32).init(std.testing.allocator, 1024);
    defer queue.deinit();

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
    const thread = try std.Thread.spawn(.{}, Producer.run, .{&queue});
    var received: u32 = 0;
    while (received < spsc_count) {
        if (queue.tryPop()) |value| {
            std.debug.assert(value == received);
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    thread.join();
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
