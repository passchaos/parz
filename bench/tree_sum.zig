const std = @import("std");
const parz = @import("parz");

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

fn now(io: std.Io) std.Io.Clock.Timestamp {
    return std.Io.Clock.Timestamp.now(io, .awake);
}

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

    var pool = try parz.Pool(void).init(allocator, io, .{
        .workers = 0,
        .max_workers = 64,
        .max_callers = 1,
        .max_execute_states = 4096,
        .worker_stack_size = 2 * 1024 * 1024,
        .enable_heartbeat = heartbeat,
    });
    defer pool.deinit();
    try pool.start();

    const serial_start = now(io);
    const serial_result = serialSum(&nodes[0]);
    const serial_ns = serial_start.untilNow(io).raw.toNanoseconds();

    var parallel_result: i64 = 0;
    var parallel_ns: i96 = std.math.maxInt(i96);
    const repeats = 9;
    const caller = pool.claimCaller() orelse return error.NoCallerSlot;
    defer pool.releaseCaller(caller);
    for (0..repeats) |_| {
        const start = now(io);
        var task = caller.begin();
        parallel_result = try task.call(anyerror!i64, parallelSum, &nodes[0]);
        const elapsed = start.untilNow(io).raw.toNanoseconds();
        if (elapsed < parallel_ns) parallel_ns = elapsed;
    }

    if (serial_result != parallel_result) {
        std.debug.print("mismatch: serial={d} parallel={d}\n", .{ serial_result, parallel_result });
        return error.ChecksumMismatch;
    }

    const serial_per_node = @as(f64, @floatFromInt(serial_ns)) / @as(f64, @floatFromInt(node_count));
    const parallel_per_node = @as(f64, @floatFromInt(parallel_ns)) / @as(f64, @floatFromInt(node_count));
    const speedup = @as(f64, @floatFromInt(serial_ns)) / @as(f64, @floatFromInt(parallel_ns));

    std.debug.print(
        "tree_sum nodes={d} workers={d} serial_ns={d} parallel_ns={d} speedup={d:.2} serial_ns_per_node={d:.4} parallel_ns_per_node={d:.4}\n",
        .{
            node_count,
            pool.spawned_background,
            serial_ns,
            parallel_ns,
            speedup,
            serial_per_node,
            parallel_per_node,
        },
    );
}
