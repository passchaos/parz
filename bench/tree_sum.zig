const std = @import("std");
const parz = @import("parz");
const timing = @import("timing.zig");
const affinity = @import("affinity.zig");

const Node = struct {
    value: i64,
    left: ?*const Node = null,
    right: ?*const Node = null,
};

fn serialSum(node: *const Node) i64 {
    var result = node.value;
    if (node.left) |left| result += serialSum(left);
    if (node.right) |right| result += serialSum(right);
    return result;
}

fn parallelSum(task: *parz.Task(void), node: *const Node) anyerror!i64 {
    var result = node.value;
    if (node.left) |left| {
        if (node.right) |right| {
            var future = parz.Future(void, *const Node, anyerror!i64){};
            future.fork(task, parallelSum, right);
            result += try task.call(anyerror!i64, parallelSum, left);
            const joined = future.join(task);
            const other = if (joined) |value|
                try value
            else
                try task.call(anyerror!i64, parallelSum, right);
            result += other;
            return result;
        }
        result += try task.call(anyerror!i64, parallelSum, left);
    }
    if (node.right) |right| {
        result += try task.call(anyerror!i64, parallelSum, right);
    }
    return result;
}

fn buildTree(allocator: std.mem.Allocator, node_count: usize) ![]Node {
    const nodes = try allocator.alloc(Node, node_count);
    for (nodes, 0..) |*node, index| {
        node.value = 1;
        node.left = if (2 * index + 1 < node_count) &nodes[2 * index + 1] else null;
        node.right = if (2 * index + 2 < node_count) &nodes[2 * index + 2] else null;
    }
    return nodes;
}

const Run = struct {
    root: *const Node,
    caller: *parz.Worker(void),

    fn serial(self: *@This()) !i64 {
        return serialSum(self.root);
    }

    fn parallel(self: *@This()) !i64 {
        var task = self.caller.begin();
        return task.call(anyerror!i64, parallelSum, self.root);
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
        1_000_000;

    const nodes = try buildTree(allocator, node_count);
    defer allocator.free(nodes);
    if (nodes.len == 0) return;

    const heartbeat = if (argv.items.len > 2)
        !std.mem.eql(u8, argv.items[2], "no-heartbeat")
    else
        true;
    const gate = argv.items.len > 3 and std.mem.eql(u8, argv.items[3], "gate");
    const caller_cpu = if (argv.items.len > 4) try std.fmt.parseInt(usize, argv.items[4], 10) else null;

    var pool = try parz.Pool(void).init(allocator, io, .{
        .workers = 0,
        .max_workers = 64,
        .max_callers = 1,
        .max_execute_states = 4096,
        .worker_stack_size = 2 * 1024 * 1024,
        .enable_heartbeat = heartbeat,
        .pin_workers = caller_cpu != null,
    });
    defer pool.deinit();
    try pool.start();
    if (caller_cpu) |cpu| try affinity.pinCaller(&pool, cpu);

    const caller = pool.claimCaller() orelse return error.NoCallerSlot;
    defer pool.releaseCaller(caller);
    var run = Run{ .root = &nodes[0], .caller = caller };
    std.debug.print("tree_sum nodes={d} workers={d} checksum={d}\n", .{ node_count, pool.spawned_background, node_count });
    if (caller_cpu) |cpu| std.debug.print("placement caller_cpu={d} worker_cpus={any}\n", .{ cpu, pool.pinned_cpus[0..pool.spawned_background] });
    const times = try timing.paired(i64, allocator, io, 9, @intCast(node_count), &run, Run.serial, Run.parallel);
    std.debug.print(
        "tree_sum nodes={d} workers={d} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n",
        .{ node_count, pool.spawned_background, times.serial_ns, times.parallel_ns, times.speedup() },
    );
    if (gate and times.speedup() < 0.9) {
        std.debug.print("small-input parity gate failed: speedup={d:.3} < 0.9\n", .{times.speedup()});
        return error.ParityRegression;
    }
}
