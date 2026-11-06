const std = @import("std");
const parz = @import("parz");

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

    const count = if (argv.items.len > 1)
        try std.fmt.parseInt(usize, argv.items[1], 10)
    else
        1_000_000;

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
    const serial_result = serialSum(count);
    const serial_ns = serial_start.untilNow(io).raw.toNanoseconds();

    const Map = struct {
        fn map(_: *parz.Worker(void), _: void, index: usize) u64 {
            return work(index);
        }
    };
    const Combine = struct {
        fn combine(a: u64, b: u64) u64 {
            return a +% b;
        }
    };

    var parallel_result: u64 = 0;
    var parallel_ns: i96 = std.math.maxInt(i96);
    const repeats = 5;
    for (0..repeats) |_| {
        const start = now(io);
        parallel_result = try parz.parallelFoldInfallible(
            &pool,
            u64,
            {},
            count,
            .{ .min_chunk = 1024 },
            0,
            Map.map,
            Combine.combine,
        );
        const elapsed = start.untilNow(io).raw.toNanoseconds();
        if (elapsed < parallel_ns) parallel_ns = elapsed;
    }

    if (serial_result != parallel_result) {
        std.debug.print("mismatch: serial={d} parallel={d}\n", .{ serial_result, parallel_result });
        return error.ChecksumMismatch;
    }

    const speedup = @as(f64, @floatFromInt(serial_ns)) / @as(f64, @floatFromInt(parallel_ns));
    std.debug.print(
        "compute count={d} workers={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n",
        .{ count, pool.spawned_background, serial_ns, parallel_ns, speedup },
    );
}
