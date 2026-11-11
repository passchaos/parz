//! Bounded intrusive index list for shared-job owners. Pool-mutex protected;
//! unrelated to the standalone sync queues or owner-local fork lists.
const std = @import("std");

pub const ReadyOwners = struct {
    const Link = struct { prev: ?usize = null, next: ?usize = null, queued: bool = false };
    links: []Link,
    bits: []usize,
    head: ?usize = null,
    tail: ?usize = null,
    allocator: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator, capacity: usize) !ReadyOwners {
        const links = try a.alloc(Link, capacity);
        errdefer a.free(links);
        const bits = try a.alloc(usize, capacity / @bitSizeOf(usize) + @intFromBool(capacity % @bitSizeOf(usize) != 0));
        @memset(links, .{});
        @memset(bits, 0);
        return .{ .links = links, .bits = bits, .allocator = a };
    }

    pub fn deinit(self: *ReadyOwners) void {
        self.allocator.free(self.links);
        self.allocator.free(self.bits);
        self.* = undefined;
    }

    pub fn contains(self: *const ReadyOwners, index: usize) bool {
        return self.links[index].queued;
    }

    /// Preserve the scheduler's original registered-index priority without
    /// scanning every inactive/empty worker. The bitmap is mutex-protected.
    pub fn firstPriority(self: *const ReadyOwners) ?usize {
        for (self.bits, 0..) |word, index| {
            if (word != 0) return index * @bitSizeOf(usize) + @ctz(word);
        }
        return null;
    }

    pub fn push(self: *ReadyOwners, index: usize) void {
        std.debug.assert(!self.contains(index));
        self.links[index] = .{ .prev = self.tail, .queued = true };
        self.bits[index / @bitSizeOf(usize)] |= @as(usize, 1) << @intCast(index % @bitSizeOf(usize));
        if (self.tail) |tail| self.links[tail].next = index else self.head = index;
        self.tail = index;
    }

    pub fn remove(self: *ReadyOwners, index: usize) void {
        std.debug.assert(self.contains(index));
        const link = self.links[index];
        if (link.prev) |prev| self.links[prev].next = link.next else self.head = link.next;
        if (link.next) |next| self.links[next].prev = link.prev else self.tail = link.prev;
        self.links[index] = .{};
        self.bits[index / @bitSizeOf(usize)] &= ~(@as(usize, 1) << @intCast(index % @bitSizeOf(usize)));
    }

    pub fn pop(self: *ReadyOwners) ?usize {
        const index = self.head orelse return null;
        self.remove(index);
        return index;
    }
};

test "ready owners preserve round robin and arbitrary reclamation order" {
    var ready = try ReadyOwners.init(std.testing.allocator, 8);
    defer ready.deinit();
    for (0..8) |i| ready.push(i);
    ready.remove(3);
    ready.remove(0);
    ready.remove(7);
    const expected = [_]usize{ 1, 2, 4, 5, 6 };
    for (0..10) |_| {
        for (expected) |i| {
            try std.testing.expectEqual(i, ready.pop().?);
            ready.push(i);
        }
    }
    for (expected) |i| try std.testing.expectEqual(i, ready.pop().?);
    try std.testing.expect(ready.pop() == null);
    for (0..8) |i| try std.testing.expect(!ready.contains(i));
    ready.push(7);
    ready.remove(7);
    try std.testing.expect(ready.head == null and ready.tail == null);
}

test "ready owner allocation failure and empty capacity" {
    for (0..2) |fail_index| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
        try std.testing.expectError(error.OutOfMemory, ReadyOwners.init(failing.allocator(), 8));
    }
    var ready = try ReadyOwners.init(std.testing.allocator, 0);
    defer ready.deinit();
    try std.testing.expect(ready.pop() == null);
}

test "ready owner priority bitmap crosses words and retains original index order" {
    var ready = try ReadyOwners.init(std.testing.allocator, 130);
    defer ready.deinit();
    for ([_]usize{ 129, 64, 7, 63, 0 }) |i| ready.push(i);
    for ([_]usize{ 0, 7, 63, 64, 129 }) |i| {
        try std.testing.expectEqual(i, ready.firstPriority().?);
        ready.remove(i);
    }
    try std.testing.expect(ready.firstPriority() == null);
    try std.testing.expect(ready.head == null);
}
