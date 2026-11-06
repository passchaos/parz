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
        enqueue_pos: std.atomic.Value(usize) = .init(0),
        dequeue_pos: std.atomic.Value(usize) = .init(0),
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

        /// Single consumer only.
        pub fn tryPop(self: *Self) ?T {
            var pos = self.dequeue_pos.load(.monotonic);
            while (true) {
                const slot = &self.buffer[pos & self.mask];
                const seq = slot.sequence.load(.acquire);
                const dif = @as(isize, @bitCast(seq -% (pos +% 1)));
                if (dif == 0) {
                    self.dequeue_pos.store(pos +% 1, .monotonic);
                    const value = slot.value;
                    slot.sequence.store(pos +% self.buffer.len, .release);
                    return value;
                }
                if (dif < 0) return null;
                pos = self.dequeue_pos.load(.monotonic);
            }
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

test "mpsc queue: single-threaded order and bounds" {
    var queue = try MpscQueue(u32).init(std.testing.allocator, 4);
    defer queue.deinit();

    try std.testing.expect(queue.tryPop() == null);
    for (0..4) |index| try std.testing.expect(queue.tryPush(@intCast(index)));
    try std.testing.expect(!queue.tryPush(99));
    for (0..4) |index| try std.testing.expectEqual(@as(u32, @intCast(index)), queue.tryPop().?);
    try std.testing.expect(queue.tryPop() == null);
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
