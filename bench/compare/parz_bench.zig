const std = @import("std");
const parz = @import("parz");

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

fn parallelSumErr(task: *parz.Task(void), node: *const Node) anyerror!i64 {
    var result = node.value;
    if (node.left) |left| {
        if (node.right) |right| {
            var future = parz.Future(void, *const Node, anyerror!i64){};
            future.fork(task, parallelSumErr, right);
            result += try task.call(anyerror!i64, parallelSumErr, left);
            result += if (future.join(task)) |value|
                try value
            else
                try task.call(anyerror!i64, parallelSumErr, right);
            return result;
        }
        result += try task.call(anyerror!i64, parallelSumErr, left);
    }
    if (node.right) |right| {
        result += try task.call(anyerror!i64, parallelSumErr, right);
    }
    return result;
}

fn parallelSum(task: *parz.Task(void), node: *const Node) i64 {
    var result = node.value;
    if (node.left) |left| {
        if (node.right) |right| {
            var future = parz.Future(void, *const Node, i64){};
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

const FlatCutInput = struct {
    ctx: *const FlatCtx,
    index: usize,
    depth: u8,
};

fn parallelSumFlatCut(task: *parz.Task(void), input: FlatCutInput) i64 {
    const values = input.ctx.values;
    if (input.depth >= flat_cutoff_depth) return serialSumFlat(values, input.index);
    var result = values[input.index];
    const left = 2 * input.index + 1;
    const right = 2 * input.index + 2;
    if (right < values.len) {
        var future = parz.Future(void, FlatCutInput, i64){};
        future.fork(task, parallelSumFlatCut, .{ .ctx = input.ctx, .index = right, .depth = input.depth + 1 });
        result += task.call(i64, parallelSumFlatCut, FlatCutInput{ .ctx = input.ctx, .index = left, .depth = input.depth + 1 });
        result += if (future.join(task)) |value|
            value
        else
            task.call(i64, parallelSumFlatCut, FlatCutInput{ .ctx = input.ctx, .index = right, .depth = input.depth + 1 });
        return result;
    }
    if (left < values.len) result += task.call(i64, parallelSumFlatCut, FlatCutInput{ .ctx = input.ctx, .index = left, .depth = input.depth + 1 });
    return result;
}

var flat_cutoff_depth: u8 = 8;

const FlatCtx = struct {
    values: []const i64,
};

const FlatInput = struct {
    ctx: *const FlatCtx,
    index: usize,
};

fn serialSumFlat(values: []const i64, index: usize) i64 {
    var result = values[index];
    const left = 2 * index + 1;
    const right = 2 * index + 2;
    if (left < values.len) result += serialSumFlat(values, left);
    if (right < values.len) result += serialSumFlat(values, right);
    return result;
}

fn parallelSumFlat(task: *parz.Task(void), input: FlatInput) i64 {
    const values = input.ctx.values;
    var result = values[input.index];
    const left = 2 * input.index + 1;
    const right = 2 * input.index + 2;
    if (right < values.len) {
        var future = parz.Future(void, FlatInput, i64){};
        future.fork(task, parallelSumFlat, .{ .ctx = input.ctx, .index = right });
        result += task.call(i64, parallelSumFlat, FlatInput{ .ctx = input.ctx, .index = left });
        result += if (future.join(task)) |value|
            value
        else
            task.call(i64, parallelSumFlat, FlatInput{ .ctx = input.ctx, .index = right });
        return result;
    }
    if (left < values.len) result += task.call(i64, parallelSumFlat, FlatInput{ .ctx = input.ctx, .index = left });
    return result;
}

const CutInput = struct {
    node: *const Node,
    depth: u8,
};

fn parallelSumCut(task: *parz.Task(void), input: CutInput) i64 {
    if (input.depth >= 8) return serialSum(input.node);
    var result = input.node.value;
    if (input.node.left) |left| {
        if (input.node.right) |right| {
            var future = parz.Future(void, CutInput, i64){};
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

fn parallelSumIdx(task: *parz.Task(void), input: IdxInput) i64 {
    var result = input.nodes[input.index].value;
    const left = input.nodes[input.index].left;
    const right = input.nodes[input.index].right;
    if (left >= 0 and right >= 0) {
        var future = parz.Future(void, IdxInput, i64){};
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

fn parallelSumCtx(task: *parz.Task(void), input: IdxCtxInput) i64 {
    const nodes = input.tree.nodes;
    var result = nodes[input.index].value;
    const left = nodes[input.index].left;
    const right = nodes[input.index].right;
    if (left >= 0 and right >= 0) {
        var future = parz.Future(void, IdxCtxInput, i64){};
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

const FlatMap = struct {
    fn map(_: *parz.Worker(void), data: []const u64, index: usize) anyerror!u64 {
        return data[index];
    }
};

const ComputeMap = struct {
    fn map(_: *parz.Worker(void), _: void, index: usize) anyerror!u64 {
        return work(index);
    }
};

const ChunkSum = struct {
    fn run(_: *parz.Worker(void), total: *std.atomic.Value(u64), chunk: parz.Chunk) anyerror!void {
        var local: u64 = 0;
        var i = chunk.start;
        while (i < chunk.end) : (i += 1) local +%= work(i);
        _ = total.fetchAdd(local, .monotonic);
    }
};

fn add(a: u64, b: u64) u64 {
    return a +% b;
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
    const min_chunk_arg = if (argv.items.len > 4)
        try std.fmt.parseInt(usize, argv.items[4], 10)
    else
        0;
    const chunks_per_worker = if (argv.items.len > 5)
        try std.fmt.parseInt(usize, argv.items[5], 10)
    else
        16;
    const heartbeat = if (argv.items.len > 6)
        !std.mem.eql(u8, argv.items[6], "no-heartbeat")
    else
        true;
    const heartbeat_ns = if (argv.items.len > 7)
        try std.fmt.parseInt(i96, argv.items[7], 10)
    else
        10 * std.time.ns_per_us;

    var pool = try parz.Pool(void).init(allocator, io, .{
        .workers = if (lanes == 0) 1 else lanes - 1,
        .max_workers = if (lanes == 0) 0 else 64,
        .max_callers = 1,
        .max_execute_states = 4096,
        .worker_stack_size = 2 * 1024 * 1024,
        .enable_heartbeat = heartbeat,
        .heartbeat_interval_ns = heartbeat_ns,
    });
    defer pool.deinit();
    try pool.start();

    if (std.mem.eql(u8, workload, "tree-flat-cutoff")) {
        const values = try allocator.alloc(i64, count);
        defer allocator.free(values);
        for (values) |*value| value.* = 1;
        if (values.len == 0) return;
        var ctx = FlatCtx{ .values = values };
        flat_cutoff_depth = if (min_chunk_arg != 0) @intCast(min_chunk_arg) else 8;

        var serial_result: i64 = 0;
        var parallel_result: i64 = 0;
        var serial_best: i96 = std.math.maxInt(i96);
        var parallel_best: i96 = std.math.maxInt(i96);

        for (0..9) |_| {
            var start = now(io);
            serial_result = serialSumFlat(values, 0);
            const t_serial = elapsed(start, io);
            if (t_serial < serial_best) serial_best = t_serial;

            const caller = pool.claimCaller() orelse return error.NoCallerSlot;
            start = now(io);
            var task = caller.begin();
            parallel_result = task.call(i64, parallelSumFlatCut, FlatCutInput{ .ctx = &ctx, .index = 0, .depth = 0 });
            const t_parallel = elapsed(start, io);
            pool.releaseCaller(caller);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz tree-flat-cutoff n={d} depth={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, flat_cutoff_depth, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    if (std.mem.eql(u8, workload, "tree-flat")) {
        const values = try allocator.alloc(i64, count);
        defer allocator.free(values);
        for (values) |*value| value.* = 1;
        if (values.len == 0) return;
        var ctx = FlatCtx{ .values = values };

        var serial_result: i64 = 0;
        var parallel_result: i64 = 0;
        var serial_best: i96 = std.math.maxInt(i96);
        var parallel_best: i96 = std.math.maxInt(i96);

        for (0..9) |_| {
            var start = now(io);
            serial_result = serialSumFlat(values, 0);
            const t_serial = elapsed(start, io);
            if (t_serial < serial_best) serial_best = t_serial;

            const caller = pool.claimCaller() orelse return error.NoCallerSlot;
            start = now(io);
            var task = caller.begin();
            parallel_result = task.call(i64, parallelSumFlat, FlatInput{ .ctx = &ctx, .index = 0 });
            const t_parallel = elapsed(start, io);
            pool.releaseCaller(caller);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz tree-flat n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

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

            const caller = pool.claimCaller() orelse return error.NoCallerSlot;
            start = now(io);
            var task = caller.begin();
            parallel_result = task.call(i64, parallelSumCut, CutInput{ .node = &nodes[0], .depth = 0 });
            const t_parallel = elapsed(start, io);
            pool.releaseCaller(caller);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz tree-cutoff n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
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

            const caller = pool.claimCaller() orelse return error.NoCallerSlot;
            start = now(io);
            var task = caller.begin();
            parallel_result = task.call(i64, parallelSumCtx, IdxCtxInput{ .tree = &ctx, .index = 0 });
            const t_parallel = elapsed(start, io);
            pool.releaseCaller(caller);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz tree-ctx n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
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

            const caller = pool.claimCaller() orelse return error.NoCallerSlot;
            start = now(io);
            var task = caller.begin();
            parallel_result = task.call(i64, parallelSumIdx, IdxInput{ .nodes = nodes, .index = 0 });
            const t_parallel = elapsed(start, io);
            pool.releaseCaller(caller);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz tree-idx n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    if (std.mem.eql(u8, workload, "tree") or std.mem.eql(u8, workload, "tree-err")) {
        const use_err = std.mem.eql(u8, workload, "tree-err");
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

            const caller = pool.claimCaller() orelse return error.NoCallerSlot;
            start = now(io);
            var task = caller.begin();
            parallel_result = if (use_err)
                try task.call(anyerror!i64, parallelSumErr, &nodes[0])
            else
                task.call(i64, parallelSum, &nodes[0]);
            const t_parallel = elapsed(start, io);
            pool.releaseCaller(caller);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz tree n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
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
            parallel_result = try parz.parallelFold(
                &pool,
                u64,
                data,
                count,
                .{ .min_chunk = if (min_chunk_arg != 0) min_chunk_arg else 4096, .chunks_per_worker = chunks_per_worker },
                0,
                FlatMap.map,
                add,
            );
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz flat n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    if (std.mem.eql(u8, workload, "compute-inf")) {
        const ComputeInfMap = struct {
            fn map(_: *parz.Worker(void), _: void, index: usize) u64 {
                return work(index);
            }
        };
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
            parallel_result = try parz.parallelFoldInfallible(
                &pool,
                u64,
                {},
                count,
                .{ .min_chunk = 1024, .chunks_per_worker = 16 },
                0,
                ComputeInfMap.map,
                add,
            );
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz compute-inf n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
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
            parallel_result = try parz.parallelFold(
                &pool,
                u64,
                {},
                count,
                .{ .min_chunk = if (min_chunk_arg != 0) min_chunk_arg else 1024, .chunks_per_worker = chunks_per_worker },
                0,
                ComputeMap.map,
                add,
            );
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz compute n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    if (std.mem.eql(u8, workload, "compute-chunk")) {
        var serial_result: u64 = 0;
        var parallel_result: u64 = 0;
        var serial_best: i96 = std.math.maxInt(i96);
        var parallel_best: i96 = std.math.maxInt(i96);

        for (0..7) |_| {
            var start = now(io);
            serial_result = serialCompute(count);
            const t_serial = elapsed(start, io);
            if (t_serial < serial_best) serial_best = t_serial;

            var total = std.atomic.Value(u64).init(0);
            start = now(io);
            try parz.parallelForRange(
                &pool,
                &total,
                count,
                .{ .min_chunk = if (min_chunk_arg != 0) min_chunk_arg else 1024, .chunks_per_worker = chunks_per_worker },
                ChunkSum.run,
            );
            parallel_result = total.load(.monotonic);
            const t_parallel = elapsed(start, io);
            if (t_parallel < parallel_best) parallel_best = t_parallel;
        }
        if (serial_result != parallel_result) {
            std.debug.print("mismatch serial={d} parallel={d}\n", .{ serial_result, parallel_result });
            return error.ChecksumMismatch;
        }
        const speedup = @as(f64, @floatFromInt(serial_best)) / @as(f64, @floatFromInt(parallel_best));
        std.debug.print("parz compute-chunk n={d} lanes={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n", .{
            count, lanes, serial_best, parallel_best, speedup,
        });
        return;
    }

    return error.UnknownWorkload;
}
