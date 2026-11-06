//! Skewed fork/join benchmark: a complete tree with pseudo-random per-node
//! work. Used to check whether heartbeat sharing balances irregular subtrees
//! without work stealing.

const std = @import("std");
const parz = @import("parz");
const timing = @import("timing.zig");

const Node = struct {
    value: u64,
    cost: u32,
    left: ?*const Node = null,
    right: ?*const Node = null,
};

fn spin(cost: u32) u64 {
    var x: u64 = cost;
    var round: u32 = 0;
    const rounds = cost * 8;
    while (round < rounds) : (round += 1) {
        x = (x *% 6364136223846793005) +% 1442695040888963407;
        x ^= x >> 17;
    }
    return x;
}

fn buildTree(allocator: std.mem.Allocator, node_count: usize, skewed: bool) ![]Node {
    const nodes = try allocator.alloc(Node, node_count);
    for (nodes, 0..) |*node, index| {
        // Mixed: fixed pseudo-random work. Skewed: the entire left subtree
        // costs 32 units per node while the right subtree costs one. A random
        // distribution alone averages out across large complete subtrees.
        const mixed = (index *% 2654435761) >> 27;
        const level = std.math.log2_int(usize, index + 1);
        const on_left = level > 0 and ((index + 1) >> @intCast(level - 1)) & 1 == 0;
        node.value = 1;
        node.cost = if (skewed) (if (on_left) 32 else 1) else 1 + @as(u32, @intCast(mixed & 31));
        node.left = if (2 * index + 1 < node_count) &nodes[2 * index + 1] else null;
        node.right = if (2 * index + 2 < node_count) &nodes[2 * index + 2] else null;
    }
    return nodes;
}

fn serialSum(node: *const Node) u64 {
    var result = node.value +% spin(node.cost);
    if (node.left) |left| result +%= serialSum(left);
    if (node.right) |right| result +%= serialSum(right);
    return result;
}

fn parallelSum(task: *parz.Task(void), node: *const Node) anyerror!u64 {
    var result = node.value +% spin(node.cost);
    if (node.left) |left| {
        if (node.right) |right| {
            var future = parz.Future(void, *const Node, anyerror!u64){};
            future.fork(task, parallelSum, right);
            result +%= try task.call(anyerror!u64, parallelSum, left);
            result +%= if (future.join(task)) |value|
                try value
            else
                try task.call(anyerror!u64, parallelSum, right);
            return result;
        }
        result +%= try task.call(anyerror!u64, parallelSum, left);
    }
    if (node.right) |right| {
        result +%= try task.call(anyerror!u64, parallelSum, right);
    }
    return result;
}

const Run = struct {
    root: *const Node,
    caller: *parz.Worker(void),

    fn serial(self: *@This()) !u64 {
        return serialSum(self.root);
    }

    fn parallel(self: *@This()) !u64 {
        var task = self.caller.begin();
        return task.call(anyerror!u64, parallelSum, self.root);
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    while (args.next()) |arg| try argv.append(allocator, arg);

    const node_count = if (argv.items.len > 1)
        try std.fmt.parseInt(usize, argv.items[1], 10)
    else
        200_000;

    const lanes = if (argv.items.len > 2) try std.fmt.parseInt(usize, argv.items[2], 10) else 0;
    const rounds = if (argv.items.len > 3) try std.fmt.parseInt(usize, argv.items[3], 10) else 9;
    const profile = if (argv.items.len > 4) argv.items[4] else "mixed";
    if (!std.mem.eql(u8, profile, "mixed") and !std.mem.eql(u8, profile, "skewed")) return error.InvalidProfile;
    const nodes = try buildTree(allocator, node_count, std.mem.eql(u8, profile, "skewed"));
    defer allocator.free(nodes);
    if (nodes.len == 0) return;

    var pool = try parz.Pool(void).init(allocator, io, .{
        .workers = if (lanes > 1) lanes - 1 else 0,
        .max_workers = if (lanes == 1) 0 else 64,
        .max_callers = 1,
        .max_execute_states = 4096,
        .worker_stack_size = 2 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    // Independent checksum over storage, without relying on either traversal.
    var expected: u64 = 0;
    for (nodes) |node| expected +%= node.value +% spin(node.cost);
    const caller = pool.claimCaller() orelse return error.NoCallerSlot;
    defer pool.releaseCaller(caller);
    var run = Run{ .root = &nodes[0], .caller = caller };
    std.debug.print("irregular_tree nodes={d} workers={d} rounds={d} profile={s} checksum={d}\n", .{
        node_count, pool.spawned_background, rounds, profile, expected,
    });
    const times = try timing.paired(u64, allocator, io, rounds, expected, &run, Run.serial, Run.parallel);
    std.debug.print(
        "irregular_tree nodes={d} workers={d} rounds={d} profile={s} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n",
        .{ node_count, pool.spawned_background, rounds, profile, times.serial_ns, times.parallel_ns, times.speedup() },
    );
}
