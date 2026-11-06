//! Optional NUMA allocation, independent of the scheduler and sync module.
//! Linux allocations receive a VMA policy before any user first-touch. Other
//! targets use the provided fallback allocator. Allocation provenance stays
//! fixed for the allocator's lifetime, including when mbind is unavailable.
const std = @import("std");
const builtin = @import("builtin");

pub const Policy = enum(usize) {
    preferred = 1,
    bind = 2,
    interleave = 3,
    local = 4,
};

pub const Options = struct {
    policy: Policy = .local,
    /// Copied during init. Local policy requires no nodes; preferred requires
    /// one, while bind/interleave accept any nonempty set of u16 node IDs.
    nodes: []const u16 = &.{},
    /// Fail allocation when the policy cannot be installed. On unsupported
    /// platforms init returns UnsupportedPlatform instead of using fallback.
    require_policy: bool = false,
};

pub const Stats = struct {
    native_supported: bool,
    live_allocations: usize,
    policy_applied: usize,
    policy_fallbacks: usize,
    policy_failures: usize,
    /// Most recently observed Linux errno; zero if no failure was observed.
    last_errno: u16,
};

pub const NumaAllocator = struct {
    const Self = @This();
    const Allocator = std.mem.Allocator;
    const Alignment = std.mem.Alignment;
    const native = builtin.os.tag == .linux;

    fallback: Allocator,
    policy: Policy,
    require_policy: bool,
    node_mask: []usize,
    maxnode: usize,
    live: std.atomic.Value(usize) = .init(0),
    applied: std.atomic.Value(usize) = .init(0),
    fallbacks: std.atomic.Value(usize) = .init(0),
    failures: std.atomic.Value(usize) = .init(0),
    last_errno: std.atomic.Value(u16) = .init(0),

    pub fn init(fallback: Allocator, options: Options) !Self {
        switch (options.policy) {
            .local => if (options.nodes.len != 0) return error.InvalidNodes,
            .preferred => if (options.nodes.len != 1) return error.InvalidNodes,
            .bind, .interleave => if (options.nodes.len == 0) return error.InvalidNodes,
        }
        if (!native and options.require_policy) return error.UnsupportedPlatform;
        var maxnode: usize = 0;
        for (options.nodes) |node| maxnode = @max(maxnode, @as(usize, node) + 1);
        const mask: []usize = if (native and maxnode != 0)
            try fallback.alloc(usize, (maxnode + @bitSizeOf(usize) - 1) / @bitSizeOf(usize))
        else
            &.{};
        @memset(mask, 0);
        if (native) for (options.nodes) |node| {
            mask[node / @bitSizeOf(usize)] |= @as(usize, 1) << @intCast(node % @bitSizeOf(usize));
        };
        return .{ .fallback = fallback, .policy = options.policy, .require_policy = options.require_policy, .node_mask = mask, .maxnode = maxnode };
    }

    /// All allocations and users of allocator() must have finished. The
    /// instance must remain at the same address while its interface is used.
    pub fn deinit(self: *Self) void {
        std.debug.assert(self.live.load(.monotonic) == 0);
        self.fallback.free(self.node_mask);
        self.* = undefined;
    }

    /// Safe to share across lanes when fallback is thread-safe. It also backs
    /// the init-time node mask. Use an arena on top for fine-grained objects.
    pub fn allocator(self: *Self) Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }

    /// Individual counters are approximate while other lanes allocate/free.
    pub fn stats(self: *const Self) Stats {
        return .{ .native_supported = native, .live_allocations = self.live.load(.monotonic), .policy_applied = self.applied.load(.monotonic), .policy_fallbacks = self.fallbacks.load(.monotonic), .policy_failures = self.failures.load(.monotonic), .last_errno = self.last_errno.load(.monotonic) };
    }

    fn backend(self: *Self) Allocator {
        return if (native) std.heap.page_allocator else self.fallback;
    }

    fn validSize(len: usize, alignment: Alignment) bool {
        if (!native) return true;
        const page = std.heap.pageSize();
        if (len >= std.math.maxInt(usize) - page) return false;
        const rounded = std.mem.alignForward(usize, len, page);
        _ = std.math.add(usize, rounded, alignment.toByteUnits() -| page) catch return false;
        return true;
    }

    fn bindMapping(self: *Self, memory: []u8) bool {
        if (comptime !native) return false;
        const rc = std.os.linux.syscall6(.mbind, @intFromPtr(memory.ptr), memory.len, @intFromEnum(self.policy), if (self.node_mask.len == 0) 0 else @intFromPtr(self.node_mask.ptr), self.maxnode, 0);
        const signed: isize = @bitCast(rc);
        if (signed < 0 and signed >= -4095) {
            self.last_errno.store(@intCast(-signed), .monotonic);
            return false;
        }
        return signed == 0;
    }

    fn alloc(raw: *anyopaque, len: usize, alignment: Alignment, ra: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(raw));
        if (!validSize(len, alignment)) return null;
        const ptr = self.backend().rawAlloc(len, alignment, ra) orelse return null;
        if (native and self.bindMapping(ptr[0..len])) {
            _ = self.applied.fetchAdd(1, .monotonic);
        } else if (self.require_policy) {
            self.backend().rawFree(ptr[0..len], alignment, ra);
            _ = self.failures.fetchAdd(1, .monotonic);
            return null;
        } else {
            _ = self.fallbacks.fetchAdd(1, .monotonic);
        }
        _ = self.live.fetchAdd(1, .monotonic);
        return ptr;
    }

    fn resize(raw: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) bool {
        const self: *Self = @ptrCast(@alignCast(raw));
        if (!validSize(new_len, alignment)) return false;
        // Linux VMA policy persists through shrinking and mremap. Never
        // rebind after relocation: failure could not restore the old pointer.
        return self.backend().rawResize(memory, alignment, new_len, ra);
    }

    fn remap(raw: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ra: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(raw));
        if (!validSize(new_len, alignment)) return null;
        return self.backend().rawRemap(memory, alignment, new_len, ra);
    }

    fn free(raw: *anyopaque, memory: []u8, alignment: Alignment, ra: usize) void {
        const self: *Self = @ptrCast(@alignCast(raw));
        self.backend().rawFree(memory, alignment, ra);
        _ = self.live.fetchSub(1, .monotonic);
    }
};

test "numa allocator validates policy node sets and copies wide masks" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.InvalidNodes, NumaAllocator.init(a, .{ .nodes = &.{0} }));
    try std.testing.expectError(error.InvalidNodes, NumaAllocator.init(a, .{ .policy = .preferred }));
    try std.testing.expectError(error.InvalidNodes, NumaAllocator.init(a, .{ .policy = .preferred, .nodes = &.{ 0, 1 } }));
    try std.testing.expectError(error.InvalidNodes, NumaAllocator.init(a, .{ .policy = .bind }));
    var numa = try NumaAllocator.init(a, .{ .policy = .interleave, .nodes = &.{ 0, 63, 64, 65535 } });
    defer numa.deinit();
    if (builtin.os.tag == .linux) {
        try std.testing.expectEqual(@as(usize, 65536), numa.maxnode);
        for ([_]u16{ 0, 63, 64, 65535 }) |node| {
            try std.testing.expect(numa.node_mask[node / @bitSizeOf(usize)] & (@as(usize, 1) << @intCast(node % @bitSizeOf(usize))) != 0);
        }
    }
}

test "numa allocator preserves contents alignment and failed reallocations" {
    var numa = try NumaAllocator.init(std.testing.allocator, .{});
    defer numa.deinit();
    const a = numa.allocator();
    var bytes = try a.alloc(u8, 9000);
    @memset(bytes, 0x6d);
    bytes = try a.realloc(bytes, 25000);
    for (bytes[0..9000]) |byte| try std.testing.expectEqual(@as(u8, 0x6d), byte);
    @memset(bytes, 0xa7);
    if (a.resize(bytes, 100)) bytes = bytes[0..100];
    for (bytes) |byte| try std.testing.expectEqual(@as(u8, 0xa7), byte);
    if (builtin.os.tag == .linux) try std.testing.expectError(error.OutOfMemory, a.realloc(bytes, std.math.maxInt(usize)));
    for (bytes) |byte| try std.testing.expectEqual(@as(u8, 0xa7), byte);
    a.free(bytes);
    const aligned = try a.alignedAlloc(u8, .fromByteUnits(65536), 17000);
    try std.testing.expect(@intFromPtr(aligned.ptr) % 65536 == 0);
    @memset(aligned, 0x35);
    a.free(aligned);
    try std.testing.expectEqual(@as(usize, 0), numa.stats().live_allocations);
    try std.testing.expect(numa.stats().policy_applied + numa.stats().policy_fallbacks >= 2);
}

test "numa required policy either applies or reports allocation failure" {
    if (builtin.os.tag != .linux) {
        try std.testing.expectError(error.UnsupportedPlatform, NumaAllocator.init(std.testing.allocator, .{ .require_policy = true }));
        return;
    }
    var numa = try NumaAllocator.init(std.testing.allocator, .{ .policy = .preferred, .nodes = &.{0}, .require_policy = true });
    defer numa.deinit();
    const a = numa.allocator();
    if (a.alloc(u8, 4096)) |memory| {
        @memset(memory, 0x42);
        a.free(memory);
        try std.testing.expectEqual(@as(usize, 1), numa.stats().policy_applied);
    } else |err| {
        try std.testing.expectEqual(error.OutOfMemory, err);
        try std.testing.expect(numa.stats().policy_failures == 1 and numa.stats().last_errno != 0);
    }
    try std.testing.expectEqual(@as(usize, 0), numa.stats().live_allocations);
}

test "numa allocator handles every policy and init-time allocation failure" {
    for ([_]Policy{ .local, .preferred, .bind, .interleave }) |policy| {
        var numa = try NumaAllocator.init(std.testing.allocator, .{
            .policy = policy,
            .nodes = if (policy == .local) &.{} else &.{0},
        });
        defer numa.deinit();
        const a = numa.allocator();
        const memory = try a.alloc(u64, 1024);
        @memset(memory, 0x0123456789abcdef);
        for (memory) |value| try std.testing.expectEqual(@as(u64, 0x0123456789abcdef), value);
        a.free(memory);
        const status = numa.stats();
        try std.testing.expectEqual(@as(usize, 0), status.live_allocations);
        try std.testing.expectEqual(@as(usize, 1), status.policy_applied + status.policy_fallbacks);
    }
    if (builtin.os.tag == .linux) {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
        try std.testing.expectError(error.OutOfMemory, NumaAllocator.init(failing.allocator(), .{
            .policy = .bind,
            .nodes = &.{ 0, 65535 },
        }));
    }
}

test "numa VMA policy survives reallocating an anonymous mapping" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    var numa = try NumaAllocator.init(std.testing.allocator, .{ .require_policy = true });
    defer numa.deinit();
    const a = numa.allocator();
    var memory = a.alloc(u8, 4096) catch return error.SkipZigTest;
    defer a.free(memory);
    @memset(memory, 0x7b);
    for ([_]usize{ 4096, 65536, 8192 }) |length| {
        memory = try a.realloc(memory, length);
        var mode: c_int = -1;
        const rc = std.os.linux.syscall5(.get_mempolicy, @intFromPtr(&mode), 0, 0, @intFromPtr(memory.ptr), 2);
        if (@as(isize, @bitCast(rc)) < 0) return error.SkipZigTest;
        try std.testing.expectEqual(@as(c_int, @intCast(@intFromEnum(Policy.local))), mode);
        for (memory[0..@min(memory.len, 4096)]) |value| try std.testing.expectEqual(@as(u8, 0x7b), value);
    }
}
