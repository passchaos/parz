const std = @import("std");
const parz = @import("parz");
const timing = @import("timing.zig");
const affinity = @import("affinity.zig");

fn serialSum(data: []const u64) u64 {
    var total: u64 = 0;
    for (data) |value| total += value;
    return total;
}

const Run = struct {
    pool: *parz.Pool(void),
    data: []const u64,
    fn serial(self: *@This()) !u64 {
        return serialSum(self.data);
    }
    fn parallel(self: *@This()) !u64 {
        return parz.parallelFoldInfallible(self.pool, u64, self.data, self.data.len, .{ .min_chunk = 4096 }, 0, map, add);
    }
    fn map(_: *parz.Worker(void), data: []const u64, index: usize) u64 {
        return data[index];
    }
    fn add(a: u64, b: u64) u64 {
        return a + b;
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

    const count = if (argv.items.len > 1)
        try std.fmt.parseInt(usize, argv.items[1], 10)
    else
        16 * 1024 * 1024;
    const lanes = if (argv.items.len > 2) try std.fmt.parseInt(usize, argv.items[2], 10) else 0;
    const cpu = if (argv.items.len > 3) try std.fmt.parseInt(usize, argv.items[3], 10) else null;
    const rounds = if (argv.items.len > 4) try std.fmt.parseInt(usize, argv.items[4], 10) else 9;
    if (count == 0) return;

    const data = try allocator.alloc(u64, count);
    defer allocator.free(data);
    for (data, 0..) |*value, index| value.* = index;

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
    var run = Run{ .pool = &pool, .data = data };
    const expected: u64 = @intCast(@as(u128, count) * (count - 1) / 2);
    const times = try timing.paired(u64, allocator, io, rounds, expected, &run, Run.serial, Run.parallel);
    std.debug.print(
        "parallel_for count={d} workers={d} checksum={d} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n",
        .{ count, pool.spawned_background, expected, times.serial_ns, times.parallel_ns, times.speedup() },
    );
}
