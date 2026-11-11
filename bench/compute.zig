const std = @import("std");
const parz = @import("parz");
const timing = @import("timing.zig");
const affinity = @import("affinity.zig");

fn work(index: u64) u64 {
    var x = index +% 0x9e3779b97f4a7c15;
    var round: u32 = 0;
    while (round < 64) : (round += 1) {
        x = (x *% 6364136223846793005) +% 1442695040888963407;
        x ^= x >> 17;
    }
    return x;
}

fn serialSum(count: usize) u64 {
    var total: u64 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) total +%= work(i);
    return total;
}

const Run = struct {
    pool: *parz.Pool(void),
    count: usize,
    fn serial(self: *@This()) !u64 {
        return serialSum(self.count);
    }
    fn parallel(self: *@This()) !u64 {
        return parz.parallelFoldInfallible(self.pool, u64, {}, self.count, .{ .min_chunk = 1024 }, 0, map, add);
    }
    fn map(_: *parz.Worker(void), _: void, index: usize) u64 {
        return work(index);
    }
    fn add(a: u64, b: u64) u64 {
        return a +% b;
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
        1_000_000;
    const pinned = if (argv.items.len > 2)
        std.mem.eql(u8, argv.items[2], "pin")
    else
        false;
    const lanes = if (argv.items.len > 3) try std.fmt.parseInt(usize, argv.items[3], 10) else 0;
    const cpu = if (argv.items.len > 4) try std.fmt.parseInt(usize, argv.items[4], 10) else null;
    const rounds = if (argv.items.len > 5) try std.fmt.parseInt(usize, argv.items[5], 10) else 9;

    var pool = try parz.Pool(void).init(allocator, io, .{
        .workers = if (lanes > 1) lanes - 1 else 0,
        .max_workers = if (lanes == 1) 0 else 64,
        .max_callers = 1,
        .max_execute_states = 4096,
        .worker_stack_size = 2 * 1024 * 1024,
        .pin_workers = pinned or cpu != null,
    });
    defer pool.deinit();
    try pool.start();
    if (cpu) |selected| try affinity.pinCaller(&pool, selected);
    if (cpu) |selected| std.debug.print("placement caller_cpu={d} worker_cpus={any}\n", .{ selected, pool.pinned_cpus[0..pool.spawned_background] });
    var run = Run{ .pool = &pool, .count = count };
    const expected = serialSum(count);
    const times = try timing.paired(u64, allocator, io, rounds, expected, &run, Run.serial, Run.parallel);
    std.debug.print(
        "compute count={d} workers={d} pinned={} checksum={d} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n",
        .{ count, pool.spawned_background, pool.options.pin_workers, expected, times.serial_ns, times.parallel_ns, times.speedup() },
    );
}
