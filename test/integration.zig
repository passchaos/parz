//! Package-level integration: per-worker scratch, flat loops, deterministic
//! fold, and recursive fork/join in one pool.

test "integration: NUMA allocator backs pool metadata and per-worker arenas" {
    const Arena = struct {
        scratch: std.heap.ArenaAllocator,

        fn init(allocator: std.mem.Allocator, _: usize) !@This() {
            return .{ .scratch = std.heap.ArenaAllocator.init(allocator) };
        }
        fn deinit(_: std.mem.Allocator, self: *@This()) void {
            self.scratch.deinit();
        }
        fn map(w: *parz.Worker(@This()), _: void, index: usize) anyerror!u64 {
            const memory = try w.context().scratch.allocator().alloc(u64, 8);
            @memset(memory, index);
            return memory[7];
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    for (0..4) |workers| {
        var numa = try parz.NumaAllocator.init(std.testing.allocator, .{});
        defer numa.deinit();
        {
            var pool = try parz.Pool(Arena).init(numa.allocator(), std.testing.io, .{
                .workers = workers,
                .max_workers = workers,
                .max_callers = 1,
                .context_init = Arena.init,
                .context_deinit = Arena.deinit,
            });
            defer pool.deinit();
            try pool.start();
            for (0..3) |_| {
                try std.testing.expectEqual(@as(u64, 32640), try parz.parallelFold(
                    &pool,
                    u64,
                    {},
                    256,
                    .{ .serial_threshold = 0, .min_chunk = 16 },
                    0,
                    Arena.map,
                    Arena.add,
                ));
            }
        }
        try std.testing.expectEqual(@as(usize, 0), numa.stats().live_allocations);
        try std.testing.expect(numa.stats().policy_applied + numa.stats().policy_fallbacks > 0);
    }
}

const std = @import("std");
const parz = @import("parz");

test "lazy NUMA lane arenas allocate on their execution lane and reuse retained capacity" {
    const Shared = struct { background: std.atomic.Value(bool) = .init(false), expect_background: bool };
    const LaneArena = struct {
        arena: std.heap.ArenaAllocator,
        constructed: std.Thread.Id,
        allocated: ?std.Thread.Id = null,
        fn init(a: std.mem.Allocator, _: usize) !@This() {
            return .{ .arena = std.heap.ArenaAllocator.init(a), .constructed = std.Thread.getCurrentId() };
        }
        fn deinit(_: std.mem.Allocator, self: *@This()) void {
            self.arena.deinit();
        }
        fn map(w: *parz.Worker(@This()), shared: *Shared, i: usize) anyerror!u64 {
            const lane = w.context();
            if (lane.allocated == null) lane.allocated = std.Thread.getCurrentId();
            if (w.caller_slot == null) shared.background.store(true, .release);
            if (shared.expect_background and w.caller_slot != null) {
                while (!shared.background.load(.acquire)) std.atomic.spinLoopHint();
            }
            const bytes = try lane.arena.allocator().alloc(u64, 8);
            @memset(bytes, i);
            return bytes[7];
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    for (0..4) |workers| {
        var numa = try parz.NumaAllocator.init(std.testing.allocator, .{});
        defer numa.deinit();
        var pool = try parz.Pool(LaneArena).init(numa.allocator(), std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .context_init = LaneArena.init,
            .context_deinit = LaneArena.deinit,
        });
        defer pool.deinit();
        try pool.start();
        for (pool.background_storage) |*w| try std.testing.expect(w.ctx.arena.queryCapacity() == 0);
        for (pool.caller_storage) |*w| try std.testing.expect(w.ctx.arena.queryCapacity() == 0);
        var shared = Shared{ .expect_background = pool.spawned_background != 0 };
        const caller = pool.claimFlatCaller().?;
        defer pool.releaseCaller(caller);
        for (0..2) |_| {
            try std.testing.expectEqual(@as(u64, 8386560), try parz.parallelFold(caller, u64, &shared, 4096, .{
                .serial_threshold = 0,
                .max_chunks = 16,
                .chunks_per_worker = 16,
                .schedule = .static,
            }, 0, LaneArena.map, LaneArena.add));
            for (pool.background_storage[0..pool.spawned_background]) |*w| {
                if (w.ctx.allocated) |thread| try std.testing.expect(thread != w.ctx.constructed);
                _ = w.ctx.arena.reset(.retain_capacity);
            }
            try std.testing.expectEqual(caller.ctx.constructed, caller.ctx.allocated.?);
            _ = caller.ctx.arena.reset(.retain_capacity);
        }
        // Static chunks may run on different lanes on another call. Prove
        // retained reuse on one explicitly owned lane rather than assuming
        // static scheduling binds contexts to chunk indices.
        const reuse = parz.ParallelOptions{ .serial_threshold = 0, .max_workers = 1, .max_chunks = 1 };
        try std.testing.expectEqual(@as(u64, 8386560), try parz.parallelFold(caller, u64, &shared, 4096, reuse, 0, LaneArena.map, LaneArena.add));
        _ = caller.ctx.arena.reset(.retain_capacity);
        const before = numa.stats().policy_applied + numa.stats().policy_fallbacks;
        try std.testing.expectEqual(@as(u64, 8386560), try parz.parallelFold(caller, u64, &shared, 4096, reuse, 0, LaneArena.map, LaneArena.add));
        try std.testing.expectEqual(before, numa.stats().policy_applied + numa.stats().policy_fallbacks);
    }
}

const Lane = struct {
    allocator: std.mem.Allocator,
    scratch: std.ArrayList(u64) = .empty,

    fn init(allocator: std.mem.Allocator, _: usize) !Lane {
        return .{ .allocator = allocator };
    }

    fn deinit(_: std.mem.Allocator, lane: *Lane) void {
        lane.scratch.deinit(lane.allocator);
    }
};

const Node = struct {
    value: u64,
    left: ?*const Node = null,
    right: ?*const Node = null,
};

fn treeSum(task: *parz.Task(Lane), node: *const Node) anyerror!u64 {
    var result = node.value;
    if (node.left) |left| {
        if (node.right) |right| {
            var future = parz.Future(Lane, *const Node, anyerror!u64){};
            future.fork(task, treeSum, right);
            result += try task.call(anyerror!u64, treeSum, left);
            result += if (future.join(task)) |value|
                try value
            else
                try task.call(anyerror!u64, treeSum, right);
            return result;
        }
        result += try task.call(anyerror!u64, treeSum, left);
    }
    if (node.right) |right| result += try task.call(anyerror!u64, treeSum, right);
    return result;
}

test "integration: scratch, flat loops, and fork/join share one pool" {
    const io = std.testing.io;
    var pool = try parz.Pool(Lane).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 2,
        .max_execute_states = 128,
        .worker_stack_size = 1 * 1024 * 1024,
        .context_init = Lane.init,
        .context_deinit = Lane.deinit,
    });
    defer pool.deinit();
    try pool.start();

    const n = 512;
    const data = try std.testing.allocator.alloc(u64, n);
    defer std.testing.allocator.free(data);
    for (data, 0..) |*value, index| value.* = index + 1;

    // Per-lane scratch: each chunk accumulates into its own list, so no two
    // lanes touch the same allocator.
    const Scratch = struct {
        fn run(worker: *parz.Worker(Lane), shared: []const u64, index: usize) anyerror!void {
            try worker.context().scratch.append(worker.context().allocator, shared[index]);
        }
    };
    try parz.parallelFor(&pool, data, data.len, .{ .min_chunk = 8, .serial_threshold = 0 }, Scratch.run);

    var total: u64 = 0;
    for (pool.background_storage) |*worker| {
        const scratch = worker.context().scratch.items;
        total += scratch.len;
        for (scratch) |value| {
            try std.testing.expect(value >= 1 and value <= n);
        }
    }
    for (pool.caller_storage) |*worker| {
        total += worker.context().scratch.items.len;
    }
    try std.testing.expectEqual(@as(u64, n), total);

    // Deterministic fold over the same data.
    const Map = struct {
        fn map(_: *parz.Worker(Lane), shared: []const u64, index: usize) anyerror!u64 {
            return shared[index];
        }
    };
    const Add = struct {
        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    const expected = @as(u64, n) * (@as(u64, n) + 1) / 2;
    const folded = try parz.parallelFold(
        &pool,
        u64,
        data,
        n,
        .{ .min_chunk = 8, .serial_threshold = 0 },
        0,
        Map.map,
        Add.combine,
    );
    try std.testing.expectEqual(expected, folded);

    // Recursive fork/join in the same pool.
    const nodes = try std.testing.allocator.alloc(Node, 1023);
    defer std.testing.allocator.free(nodes);
    for (nodes, 0..) |*node, index| {
        node.value = 1;
        node.left = if (2 * index + 1 < nodes.len) &nodes[2 * index + 1] else null;
        node.right = if (2 * index + 2 < nodes.len) &nodes[2 * index + 2] else null;
    }

    const caller = pool.claimCaller() orelse return error.NoCallerSlot;
    defer pool.releaseCaller(caller);
    var task = caller.begin();
    const sum = try task.call(anyerror!u64, treeSum, &nodes[0]);
    try std.testing.expectEqual(@as(u64, nodes.len), sum);
}

fn treeSumVoid(task: *parz.Task(void), node: *const Node) anyerror!u64 {
    var result = node.value;
    if (node.left) |left| {
        if (node.right) |right| {
            var future = parz.Future(void, *const Node, anyerror!u64){};
            future.fork(task, treeSumVoid, right);
            result += try task.call(anyerror!u64, treeSumVoid, left);
            result += if (future.join(task)) |value|
                try value
            else
                try task.call(anyerror!u64, treeSumVoid, right);
            return result;
        }
        result += try task.call(anyerror!u64, treeSumVoid, left);
    }
    if (node.right) |right| result += try task.call(anyerror!u64, treeSumVoid, right);
    return result;
}

test "integration: fork/join deterministic across worker counts" {
    const io = std.testing.io;
    const nodes = try std.testing.allocator.alloc(Node, 1023);
    defer std.testing.allocator.free(nodes);
    for (nodes, 0..) |*node, index| {
        node.value = @intCast(index + 1);
        node.left = if (2 * index + 1 < nodes.len) &nodes[2 * index + 1] else null;
        node.right = if (2 * index + 2 < nodes.len) &nodes[2 * index + 2] else null;
    }

    const expected = @as(u64, nodes.len) * (nodes.len + 1) / 2;
    for (0..5) |workers| {
        var pool = try parz.Pool(void).init(std.testing.allocator, io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .max_execute_states = 128,
            .worker_stack_size = 1 * 1024 * 1024,
        });
        defer pool.deinit();
        try pool.start();

        for (0..10) |_| {
            const caller = pool.claimCaller() orelse return error.NoCallerSlot;
            var task = caller.begin();
            const sum = try task.call(anyerror!u64, treeSumVoid, &nodes[0]);
            pool.releaseCaller(caller);
            try std.testing.expectEqual(expected, sum);
        }
    }
}
