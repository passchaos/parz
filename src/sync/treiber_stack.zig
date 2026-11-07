//! Multi-producer/single-consumer Treiber stack.

const std = @import("std");
const builtin = @import("builtin");

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

        /// Push a contiguous caller-owned node slice with one count update
        /// and one successful head CAS. Equivalent to scalar pushes in slice
        /// order: the last slice element becomes the first item popped.
        pub inline fn pushSlice(self: *Self, nodes: []Node) void {
            if (nodes.len == 0) return;
            if (nodes.len == 1) return self.push(&nodes[0]);
            return self.pushSliceBatch(nodes);
        }

        noinline fn pushSliceBatch(self: *Self, nodes: []Node) void {
            for (nodes[1..], 0..) |*node, previous| node.next = &nodes[previous];
            _ = self.count.fetchAdd(nodes.len, .monotonic);
            var old = self.head.load(.monotonic);
            while (true) {
                nodes[0].next = if (old == 0) null else @as(*Node, @ptrFromInt(old));
                if (self.head.cmpxchgWeak(
                    old,
                    @intFromPtr(&nodes[nodes.len - 1]),
                    .release,
                    .monotonic,
                )) |actual| {
                    old = actual;
                } else return;
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

        /// Pop a stack-order prefix with one successful head CAS. The unused
        /// output suffix is untouched. Single consumer only.
        pub inline fn popSlice(self: *Self, output: []*Node) usize {
            if (output.len == 0) return 0;
            if (output.len == 1) {
                output[0] = self.pop() orelse return 0;
                return 1;
            }
            return self.popSliceBatch(output);
        }

        noinline fn popSliceBatch(self: *Self, output: []*Node) usize {
            var old = self.head.load(.acquire);
            while (old != 0) {
                var next = old;
                var count_popped: usize = 0;
                while (count_popped < output.len and next != 0) : (count_popped += 1) {
                    const node: *Node = @ptrFromInt(next);
                    output[count_popped] = node;
                    next = if (node.next) |successor| @intFromPtr(successor) else 0;
                }
                if (self.head.cmpxchgWeak(old, next, .acq_rel, .acquire)) |actual| {
                    old = actual;
                    continue;
                }
                _ = self.count.fetchSub(count_popped, .monotonic);
                return count_popped;
            }
            return 0;
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const stack_producers = 4;
const stack_per_producer = 10_000;

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

test "treiber stack: mixed slice operations preserve LIFO order" {
    const Stack = TreiberStack(u32);
    var stack = Stack{};
    var nodes: [8]Stack.Node = undefined;
    for (&nodes, 0..) |*node, index| node.* = .{ .value = @intCast(index) };

    stack.pushSlice(nodes[0..4]);
    stack.push(&nodes[4]);
    stack.pushSlice(nodes[5..8]);
    try std.testing.expectEqual(@as(usize, nodes.len), stack.len());

    var output: [6]*Stack.Node = undefined;
    const sentinel = &nodes[0];
    output[5] = sentinel;
    try std.testing.expectEqual(@as(usize, 5), stack.popSlice(output[0..5]));
    try std.testing.expectEqual(sentinel, output[5]);
    try std.testing.expectEqualSlices(u32, &.{ 7, 6, 5, 4, 3 }, &.{ output[0].value, output[1].value, output[2].value, output[3].value, output[4].value });
    try std.testing.expectEqual(@as(u32, 2), stack.pop().?.value);
    try std.testing.expectEqual(@as(u32, 1), stack.pop().?.value);
    try std.testing.expectEqual(@as(u32, 0), stack.pop().?.value);
    try std.testing.expectEqual(@as(usize, 0), stack.popSlice(&output));
    stack.pushSlice(nodes[0..0]);
    try std.testing.expect(stack.isEmpty());
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

test "treiber stack: concurrent mixed scalar and batch producers and consumer" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const producers = 4;
    const per_producer = 25_000;
    const total = producers * per_producer;
    const Stack = TreiberStack(u32);
    const Node = Stack.Node;
    var stack = Stack{};
    const nodes = try std.testing.allocator.alloc(Node, total);
    defer std.testing.allocator.free(nodes);

    const Producer = struct {
        fn run(s: *Stack, slice: []Node, base: u32) void {
            var next: usize = 0;
            while (next < slice.len) {
                if (next % 7 == 0) {
                    slice[next] = .{ .value = base + @as(u32, @intCast(next)) };
                    s.push(&slice[next]);
                    next += 1;
                } else {
                    const length = @min(31, slice.len - next);
                    for (slice[next..][0..length], next..) |*node, index| {
                        node.* = .{ .value = base + @as(u32, @intCast(index)) };
                    }
                    s.pushSlice(slice[next..][0..length]);
                    next += length;
                }
            }
        }
    };

    var threads: [producers]std.Thread = undefined;
    for (&threads, 0..) |*thread, producer| {
        const slice = nodes[producer * per_producer ..][0..per_producer];
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{
            &stack,
            slice,
            @as(u32, @intCast(producer * per_producer)),
        });
    }

    var seen = try std.testing.allocator.alloc(bool, total);
    defer std.testing.allocator.free(seen);
    @memset(seen, false);
    var output: [37]*Node = undefined;
    var received: usize = 0;
    var too_large = false;
    while (received < total) {
        const count: usize = if (received % 7 == 0) blk: {
            output[0] = stack.pop() orelse {
                std.atomic.spinLoopHint();
                break :blk 0;
            };
            break :blk 1;
        } else stack.popSlice(&output);
        for (output[0..count]) |node| {
            try std.testing.expect(node.value < total);
            try std.testing.expect(!seen[node.value]);
            seen[node.value] = true;
        }
        received += count;
        too_large = too_large or stack.len() > total;
        if (count == 0) std.atomic.spinLoopHint();
    }
    for (threads) |thread| thread.join();
    try std.testing.expect(!too_large);
    try std.testing.expectEqual(@as(usize, 0), stack.len());
    try std.testing.expect(stack.isEmpty());
}
