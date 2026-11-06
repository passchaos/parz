const std = @import("std");
const parz = @import("parz");

const State = struct {
    out: []u64,
    cols: usize,
};

fn serialFill(state: State, rows: usize) u64 {
    var total: u64 = 0;
    for (0..rows) |row| {
        for (0..state.cols) |col| {
            const value = row *% state.cols +% col;
            state.out[row * state.cols + col] = value;
            total +%= value;
        }
    }
    return total;
}

fn parallelChecksum(state: State, rows: usize) u64 {
    var total: u64 = 0;
    for (0..rows) |row| {
        for (0..state.cols) |col| {
            total +%= state.out[row * state.cols + col];
        }
    }
    return total;
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

    const rows = if (argv.items.len > 1)
        try std.fmt.parseInt(usize, argv.items[1], 10)
    else
        4096;
    const cols = if (argv.items.len > 2)
        try std.fmt.parseInt(usize, argv.items[2], 10)
    else
        4096;

    const out = try allocator.alloc(u64, rows * cols);
    defer allocator.free(out);
    const state = State{ .out = out, .cols = cols };

    var pool = try parz.Pool(void).init(allocator, io, .{
        .workers = 0,
        .max_workers = 64,
        .max_callers = 1,
        .max_execute_states = 4096,
        .worker_stack_size = 2 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    const serial_start = now(io);
    const serial_result = serialFill(state, rows);
    const serial_ns = serial_start.untilNow(io).raw.toNanoseconds();

    const Ctx = struct {
        fn run(_: *parz.Worker(void), shared: State, row: usize, col: usize) anyerror!void {
            shared.out[row * shared.cols + col] = row *% shared.cols +% col;
        }
    };

    var parallel_result: u64 = 0;
    var parallel_ns: i96 = std.math.maxInt(i96);
    for (0..5) |_| {
        const start = now(io);
        try parz.parallelFor2D(&pool, state, rows, cols, .{
            .min_chunk = 4096,
            .chunks_per_worker = 16,
        }, Ctx.run);
        const elapsed = start.untilNow(io).raw.toNanoseconds();
        if (elapsed < parallel_ns) parallel_ns = elapsed;
        parallel_result = parallelChecksum(state, rows);
    }

    if (serial_result != parallel_result) {
        std.debug.print("mismatch serial={d} parallel={d}\n", .{
            serial_result, parallel_result,
        });
        return error.ChecksumMismatch;
    }

    const speedup = @as(f64, @floatFromInt(serial_ns)) / @as(f64, @floatFromInt(parallel_ns));
    std.debug.print(
        "parallel_for_2d rows={d} cols={d} workers={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n",
        .{ rows, cols, pool.spawned_background, serial_ns, parallel_ns, speedup },
    );
}
