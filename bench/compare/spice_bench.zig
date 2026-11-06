const std = @import("std");
const spice = @import("spice");

const Node = struct {
    value: i64,
    left: ?*const Node = null,
    right: ?*const Node = null,
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

fn serialSum(node: *const Node) i64 {
    var result = node.value;
    if (node.left) |left| result += serialSum(left);
    if (node.right) |right| result += serialSum(right);
    return result;
}

fn parallelSum(task: *spice.Task, node: *const Node) i64 {
    var result = node.value;
    if (node.left) |left| {
        if (node.right) |right| {
            var future = spice.Future(*const Node, i64).init();
            future.fork(task, parallelSum, right);
            result += task.call(i64, parallelSum, left);
            result += if (future.join(task)) |value|
                value
            else
                task.call(i64, parallelSum, right);
            return result;
        }
        result += task.call(i64, parallelSum, left);
    }
    if (node.right) |right| {
        result += task.call(i64, parallelSum, right);
    }
    return result;
}

const FlatRange = struct {
    data: []const u64,
    start: usize,
    end: usize,
};

const flat_chunk = 4096;

fn flatSum(task: *spice.Task, range: FlatRange) u64 {
    if (range.end - range.start <= flat_chunk) {
        var total: u64 = 0;
        var i = range.start;
        while (i < range.end) : (i += 1) total +%= range.data[i];
        return total;
    }
    const mid = range.start + (range.end - range.start) / 2;
    var future = spice.Future(FlatRange, u64).init();
    future.fork(task, flatSum, .{ .data = range.data, .start = mid, .end = range.end });
    var total = task.call(u64, flatSum, FlatRange{ .data = range.data, .start = range.start, .end = mid });
    total +%= if (future.join(task)) |value|
        value
    else
        task.call(u64, flatSum, FlatRange{ .data = range.data, .start = mid, .end = range.end });
    return total;
}

const CutInput = struct {
    node: *const Node,
    depth: u8,
};

fn parallelSumCut(task: *spice.Task, input: CutInput) i64 {
    if (input.depth >= 8) return serialSum(input.node);
    var result = input.node.value;
    if (input.node.left) |left| {
        if (input.node.right) |right| {
            var future = spice.Future(CutInput, i64).init();
            future.fork(task, parallelSumCut, .{ .node = right, .depth = input.depth + 1 });
            result += task.call(i64, parallelSumCut, CutInput{ .node = left, .depth = input.depth + 1 });
            result += if (future.join(task)) |value|
                value
            else
                task.call(i64, parallelSumCut, CutInput{ .node = right, .depth = input.depth + 1 });
            return result;
        }
        result += task.call(i64, parallelSumCut, CutInput{ .node = left, .depth = input.depth + 1 });
    }
    if (input.node.right) |right| {
        result += task.call(i64, parallelSumCut, CutInput{ .node = right, .depth = input.depth + 1 });
    }
    return result;
}

const IdxNode = struct {
    value: i64,
    left: i64,
    right: i64,
};

const IdxInput = struct {
    nodes: []const IdxNode,
    index: usize,
};

fn buildIdxTree(allocator: std.mem.Allocator, node_count: usize) ![]IdxNode {
    const nodes = try allocator.alloc(IdxNode, node_count);
    for (nodes, 0..) |*node, index| {
        node.value = 1;
        node.left = if (2 * index + 1 < node_count) @intCast(2 * index + 1) else -1;
        node.right = if (2 * index + 2 < node_count) @intCast(2 * index + 2) else -1;
    }
    return nodes;
}

fn serialSumIdx(nodes: []const IdxNode, index: usize) i64 {
    var result = nodes[index].value;
    if (nodes[index].left >= 0) result += serialSumIdx(nodes, @intCast(nodes[index].left));
    if (nodes[index].right >= 0) result += serialSumIdx(nodes, @intCast(nodes[index].right));
    return result;
}

fn parallelSumIdx(task: *spice.Task, input: IdxInput) i64 {
    var result = input.nodes[input.index].value;
    const left = input.nodes[input.index].left;
    const right = input.nodes[input.index].right;
    if (left >= 0 and right >= 0) {
        var future = spice.Future(IdxInput, i64).init();
        future.fork(task, parallelSumIdx, IdxInput{ .nodes = input.nodes, .index = @intCast(right) });
        result += task.call(i64, parallelSumIdx, IdxInput{ .nodes = input.nodes, .index = @intCast(left) });
        result += if (future.join(task)) |value|
            value
        else
            task.call(i64, parallelSumIdx, IdxInput{ .nodes = input.nodes, .index = @intCast(right) });
        return result;
    }
    if (left >= 0) result += task.call(i64, parallelSumIdx, IdxInput{ .nodes = input.nodes, .index = @intCast(left) });
    if (right >= 0) result += task.call(i64, parallelSumIdx, IdxInput{ .nodes = input.nodes, .index = @intCast(right) });
    return result;
}

const TreeCtx = struct {
    nodes: []const IdxNode,
};

const IdxCtxInput = struct {
    tree: *const TreeCtx,
    index: usize,
};

fn parallelSumCtx(task: *spice.Task, input: IdxCtxInput) i64 {
    const nodes = input.tree.nodes;
    var result = nodes[input.index].value;
    const left = nodes[input.index].left;
    const right = nodes[input.index].right;
    if (left >= 0 and right >= 0) {
        var future = spice.Future(IdxCtxInput, i64).init();
        future.fork(task, parallelSumCtx, .{ .tree = input.tree, .index = @intCast(right) });
        result += task.call(i64, parallelSumCtx, IdxCtxInput{ .tree = input.tree, .index = @intCast(left) });
        result += if (future.join(task)) |value|
            value
        else
            task.call(i64, parallelSumCtx, IdxCtxInput{ .tree = input.tree, .index = @intCast(right) });
        return result;
    }
    if (left >= 0) result += task.call(i64, parallelSumCtx, IdxCtxInput{ .tree = input.tree, .index = @intCast(left) });
    if (right >= 0) result += task.call(i64, parallelSumCtx, IdxCtxInput{ .tree = input.tree, .index = @intCast(right) });
    return result;
}

fn work(index: u64) u64 {
    var x = index +% 0x9e3779b97f4a7c15;
    var round: u32 = 0;
    while (round < 64) : (round += 1) {
        x = (x *% 6364136223846793005) +% 1442695040888963407;
        x ^= x >> 17;
    }
    return x;
}

const ComputeRange = struct {
    start: usize,
    end: usize,
};

const compute_chunk = 1024;

fn computeSum(task: *spice.Task, range: ComputeRange) u64 {
    if (range.end - range.start <= compute_chunk) {
        var total: u64 = 0;
        var i = range.start;
        while (i < range.end) : (i += 1) total +%= work(i);
        return total;
    }
    const mid = range.start + (range.end - range.start) / 2;
    var future = spice.Future(ComputeRange, u64).init();
    future.fork(task, computeSum, .{ .start = mid, .end = range.end });
    var total = task.call(u64, computeSum, ComputeRange{ .start = range.start, .end = mid });
    total +%= if (future.join(task)) |value|
        value
    else
        task.call(u64, computeSum, ComputeRange{ .start = mid, .end = range.end });
    return total;
}

fn serialFlat(data: []const u64) u64 {
    var total: u64 = 0;
    for (data) |value| total +%= value;
    return total;
}

fn serialCompute(count: usize) u64 {
    var total: u64 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) total +%= work(i);
    return total;
}

fn now(io: std.Io) std.Io.Clock.Timestamp {
    return std.Io.Clock.Timestamp.now(io, .awake);
}

fn elapsed(start: std.Io.Clock.Timestamp, io: std.Io) i96 {
    return start.untilNow(io).raw.toNanoseconds();
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer args.deinit();
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    while (args.next()) |arg| try argv.append(allocator, arg);
    if (argv.items.len < 3) {
        std.debug.print("usage: {s} <tree|flat|compute> <count> [lanes]\n", .{argv.items[0]});
        return error.BadArgs;
    }
    const workload = argv.items[1];
    const count = try std.fmt.parseInt(usize, argv.items[2], 10);
    const lanes = if (argv.items.len > 3)
        try std.fmt.parseInt(usize, argv.items[3], 10)
    else
        32;

    var pool = spice.ThreadPool.init(allocator, io);
    pool.start(.{ .background_worker_count = if (lanes == 0) 0 else lanes - 1 });
    defer pool.deinit();

    if (std.mem.eql(u8, workload, "tree-cutoff")) {
        const nodes = try buildTree(allocator, count);
        defer allocator.free(nodes);
        if (nodes.len == 0) return;

        var serial_result: i64 = 0;
        var parallel_result: i64 = 0;
        var serial_best: i96 = std.math.maxInt(i96);
        var parallel_best: i96 = std.math.maxInt(i96);

        for (0..9) |_| {
            var start = now(io);
            serial_result = serialSum(&nodes[0]);
            const t_serial = elapsed(start, io);
            if (t_serial < serial_best) serial_best = t_serial;

            start = now(io);
            parallel_result = pool.call(i64, parallelSumCut, CutInput{ .node = &nodes[0], .depth = 0 });
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("spice tree-cutoff n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    if (std.mem.eql(u8, workload, "tree-ctx")) {
        const nodes = try buildIdxTree(allocator, count);
        defer allocator.free(nodes);
        if (nodes.len == 0) return;
        var ctx = TreeCtx{ .nodes = nodes };

        var serial_result: i64 = 0;
        var parallel_result: i64 = 0;
        var serial_best: i96 = std.math.maxInt(i96);
        var parallel_best: i96 = std.math.maxInt(i96);

        for (0..9) |_| {
            var start = now(io);
            serial_result = serialSumIdx(nodes, 0);
            const t_serial = elapsed(start, io);
            if (t_serial < serial_best) serial_best = t_serial;

            start = now(io);
            parallel_result = pool.call(i64, parallelSumCtx, IdxCtxInput{ .tree = &ctx, .index = 0 });
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("spice tree-ctx n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    if (std.mem.eql(u8, workload, "tree-idx")) {
        const nodes = try buildIdxTree(allocator, count);
        defer allocator.free(nodes);
        if (nodes.len == 0) return;

        var serial_result: i64 = 0;
        var parallel_result: i64 = 0;
        var serial_best: i96 = std.math.maxInt(i96);
        var parallel_best: i96 = std.math.maxInt(i96);

        for (0..9) |_| {
            var start = now(io);
            serial_result = serialSumIdx(nodes, 0);
            const t_serial = elapsed(start, io);
            if (t_serial < serial_best) serial_best = t_serial;

            start = now(io);
            parallel_result = pool.call(i64, parallelSumIdx, IdxInput{ .nodes = nodes, .index = 0 });
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("spice tree-idx n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    if (std.mem.eql(u8, workload, "tree")) {
        const nodes = try buildTree(allocator, count);
        defer allocator.free(nodes);
        if (nodes.len == 0) return;

        var serial_result: i64 = 0;
        var parallel_result: i64 = 0;
        var serial_best: i96 = std.math.maxInt(i96);
        var parallel_best: i96 = std.math.maxInt(i96);

        for (0..9) |_| {
            var start = now(io);
            serial_result = serialSum(&nodes[0]);
            const t_serial = elapsed(start, io);
            if (t_serial < serial_best) serial_best = t_serial;

            start = now(io);
            parallel_result = pool.call(i64, parallelSum, &nodes[0]);
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("spice tree n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    if (std.mem.eql(u8, workload, "flat")) {
        const data = try allocator.alloc(u64, count);
        defer allocator.free(data);
        for (data, 0..) |*value, index| value.* = index;

        var serial_result: u64 = 0;
        var parallel_result: u64 = 0;
        var serial_best: i96 = std.math.maxInt(i96);
        var parallel_best: i96 = std.math.maxInt(i96);

        for (0..7) |_| {
            var start = now(io);
            serial_result = serialFlat(data);
            const t_serial = elapsed(start, io);
            if (t_serial < serial_best) serial_best = t_serial;

            start = now(io);
            parallel_result = pool.call(u64, flatSum, FlatRange{ .data = data, .start = 0, .end = count });
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("spice flat n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    if (std.mem.eql(u8, workload, "compute")) {
        var serial_result: u64 = 0;
        var parallel_result: u64 = 0;
        var serial_best: i96 = std.math.maxInt(i96);
        var parallel_best: i96 = std.math.maxInt(i96);

        for (0..7) |_| {
            var start = now(io);
            serial_result = serialCompute(count);
            const t_serial = elapsed(start, io);
            if (t_serial < serial_best) serial_best = t_serial;

            start = now(io);
            parallel_result = pool.call(u64, computeSum, ComputeRange{ .start = 0, .end = count });
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("spice compute n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    return error.UnknownWorkload;
}
