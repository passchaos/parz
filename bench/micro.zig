//! Fork/join overhead micro-benchmark.
//!
//! Compares a plain-value callback against an error-union callback on the same
//! tree so the cost of each API shape stays visible.

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

fn plainParallel(task: *parz.Task(void), node: *const Node) i64 {
    var result = node.value;
    if (node.left) |left| {
        if (node.right) |right| {
            var future = parz.Future(void, *const Node, i64){};
            future.fork(task, plainParallel, right);
            result += task.call(i64, plainParallel, left);
            result += if (future.join(task)) |value|
                value
            else
                task.call(i64, plainParallel, right);
            return result;
        }
        result += task.call(i64, plainParallel, left);
    }
    if (node.right) |right| {
        result += task.call(i64, plainParallel, right);
    }
    return result;
}

fn errParallel(task: *parz.Task(void), node: *const Node) anyerror!i64 {
    var result = node.value;
    if (node.left) |left| {
        if (node.right) |right| {
            var future = parz.Future(void, *const Node, anyerror!i64){};
            future.fork(task, errParallel, right);
            result += try task.call(anyerror!i64, errParallel, left);
            result += if (future.join(task)) |value|
                try value
            else
                try task.call(anyerror!i64, errParallel, right);
            return result;
        }
        result += try task.call(anyerror!i64, errParallel, left);
    }
    if (node.right) |right| {
        result += try task.call(anyerror!i64, errParallel, right);
    }
    return result;
}

fn now(io: std.Io) std.Io.Clock.Timestamp {
    return std.Io.Clock.Timestamp.now(io, .awake);
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

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const node_count = 100_000;
    const nodes = try buildTree(allocator, node_count);
    defer allocator.free(nodes);

    var pool = try parz.Pool(void).init(allocator, io, .{
        .workers = 0,
        .max_workers = 64,
        .max_callers = 1,
        .max_execute_states = 4096,
        .worker_stack_size = 2 * 1024 * 1024,
        .enable_heartbeat = false,
    });
    defer pool.deinit();
    try pool.start();

    const caller = pool.claimCaller() orelse return error.NoCallerSlot;
    defer pool.releaseCaller(caller);

    var serial_best: i96 = std.math.maxInt(i96);
    var plain_best: i96 = std.math.maxInt(i96);
    var err_best: i96 = std.math.maxInt(i96);
    var checksum: i64 = 0;

    for (0..9) |_| {
        var start = now(io);
        checksum = serialSum(&nodes[0]);
        const t = start.untilNow(io).raw.toNanoseconds();
        if (t < serial_best) serial_best = t;

        start = now(io);
        var task = caller.begin();
        checksum +%= task.call(i64, plainParallel, &nodes[0]);
        const p = start.untilNow(io).raw.toNanoseconds();
        if (p < plain_best) plain_best = p;

        start = now(io);
        task = caller.begin();
        checksum +%= try task.call(anyerror!i64, errParallel, &nodes[0]);
        const e = start.untilNow(io).raw.toNanoseconds();
        if (e < err_best) err_best = e;
    }

    std.debug.print(
        "checksum={d} serial_ns={d} plain_ns={d} err_ns={d}\n",
        .{ checksum, serial_best, plain_best, err_best },
    );
}
