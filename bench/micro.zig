//! Fork/join overhead micro-benchmark.
//!
//! Compares a plain-value callback against an error-union callback on the same
//! tree so the cost of each API shape stays visible.

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

const Run = struct {
    node: *const Node,
    caller: *parz.Worker(void),

    fn serial(self: *@This()) !i64 {
        return serialSum(self.node);
    }
    fn plain(self: *@This()) !i64 {
        var task = self.caller.begin();
        return task.call(i64, plainParallel, self.node);
    }
    fn fallible(self: *@This()) !i64 {
        var task = self.caller.begin();
        return task.call(anyerror!i64, errParallel, self.node);
    }
};

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

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    _ = args.next();
    const node_count = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 100_000;
    const lanes = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 0;
    const caller_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else null;
    if (node_count == 0) return;
    const nodes = try buildTree(allocator, node_count);
    defer allocator.free(nodes);

    var pool = try parz.Pool(void).init(allocator, io, .{
        .workers = if (lanes > 1) lanes - 1 else 0,
        .max_workers = if (lanes == 1) 0 else 64,
        .max_callers = 1,
        .max_execute_states = 4096,
        .worker_stack_size = 2 * 1024 * 1024,
        .enable_heartbeat = false,
        .pin_workers = caller_cpu != null,
    });
    defer pool.deinit();
    try pool.start();
    if (caller_cpu) |cpu| try affinity.pinCaller(&pool, cpu);
    if (caller_cpu) |cpu| std.debug.print("placement caller_cpu={d} worker_cpus={any}\n", .{ cpu, pool.pinned_cpus[0..pool.spawned_background] });

    const caller = pool.claimCaller() orelse return error.NoCallerSlot;
    defer pool.releaseCaller(caller);

    var run = Run{ .node = &nodes[0], .caller = caller };
    std.debug.print("micro nodes={d} workers={d} checksum={d} callback=plain\n", .{ node_count, pool.spawned_background, node_count });
    const plain = try timing.paired(i64, allocator, io, 9, @intCast(node_count), &run, Run.serial, Run.plain);
    std.debug.print("micro callback=plain serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ plain.serial_ns, plain.parallel_ns, plain.speedup() });
    std.debug.print("micro nodes={d} workers={d} checksum={d} callback=error-union\n", .{ node_count, pool.spawned_background, node_count });
    const fallible = try timing.paired(i64, allocator, io, 9, @intCast(node_count), &run, Run.serial, Run.fallible);
    std.debug.print("micro callback=error-union serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ fallible.serial_ns, fallible.parallel_ns, fallible.speedup() });
}
