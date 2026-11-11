const std = @import("std");
const parz = @import("parz");
const timing = @import("timing.zig");
const affinity = @import("affinity.zig");

const State = struct {
    out: []u64,
    cols: usize,
};

fn serialFill(state: State, rows: usize) void {
    for (0..rows) |row| {
        for (0..state.cols) |col| {
            const value = row *% state.cols +% col;
            state.out[row * state.cols + col] = value;
        }
    }
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

const Run = struct {
    pool: *parz.Pool(void),
    state: State,
    rows: usize,
    fn serial(self: *@This()) !u64 {
        serialFill(self.state, self.rows);
        return parallelChecksum(self.state, self.rows);
    }
    fn parallel(self: *@This()) !u64 {
        try parz.parallelFor2D(self.pool, self.state, self.rows, self.state.cols, .{ .min_chunk = 4096 }, cell);
        return parallelChecksum(self.state, self.rows);
    }
    fn cell(_: *parz.Worker(void), state: State, row: usize, col: usize) anyerror!void {
        state.out[row * state.cols + col] = row *% state.cols +% col;
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

    const rows = if (argv.items.len > 1)
        try std.fmt.parseInt(usize, argv.items[1], 10)
    else
        4096;
    const cols = if (argv.items.len > 2)
        try std.fmt.parseInt(usize, argv.items[2], 10)
    else
        4096;
    const lanes = if (argv.items.len > 3) try std.fmt.parseInt(usize, argv.items[3], 10) else 0;
    const cpu = if (argv.items.len > 4) try std.fmt.parseInt(usize, argv.items[4], 10) else null;
    const rounds = if (argv.items.len > 5) try std.fmt.parseInt(usize, argv.items[5], 10) else 9;
    const count = try std.math.mul(usize, rows, cols);
    if (count == 0) return;
    const out = try allocator.alloc(u64, count);
    defer allocator.free(out);
    const state = State{ .out = out, .cols = cols };

    var pool = try parz.Pool(void).init(allocator, io, .{
        .workers = if (lanes > 1) lanes - 1 else 0,
        .max_workers = if (lanes == 1) 0 else 64,
        .max_callers = 1,
        .max_execute_states = 4096,
        .worker_stack_size = 2 * 1024 * 1024,
        .pin_workers = cpu != null,
    });
    defer pool.deinit();
    try pool.start();
    if (cpu) |selected| try affinity.pinCaller(&pool, selected);
    if (cpu) |selected| std.debug.print("placement caller_cpu={d} worker_cpus={any}\n", .{ selected, pool.pinned_cpus[0..pool.spawned_background] });
    var run = Run{ .pool = &pool, .state = state, .rows = rows };
    const expected: u64 = @truncate(@as(u128, count) * (count - 1) / 2);
    const times = try timing.paired(u64, allocator, io, rounds, expected, &run, Run.serial, Run.parallel);
    std.debug.print(
        "parallel_for_2d rows={d} cols={d} workers={d} checksum={d} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median timing=fill+checksum\n",
        .{ rows, cols, pool.spawned_background, expected, times.serial_ns, times.parallel_ns, times.speedup() },
    );
}
