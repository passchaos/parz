//! Package-level integration: per-worker scratch, flat loops, deterministic
//! fold, and recursive fork/join in one pool.

const std = @import("std");
const parz = @import("parz");

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
    try parz.parallelFor(&pool, data, data.len, .{ .min_chunk = 8 }, Scratch.run);

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
        .{ .min_chunk = 8 },
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
