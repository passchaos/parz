const std = @import("std");
const parz = @import("parz");

fn serialSum(data: []const u64) u64 {
    var total: u64 = 0;
    for (data) |value| total += value;
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
        16 * 1024 * 1024;

    const data = try allocator.alloc(u64, count);
    defer allocator.free(data);
    for (data, 0..) |*value, index| value.* = index;

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
    const serial_result = serialSum(data);
    const serial_ns = serial_start.untilNow(io).raw.toNanoseconds();

    const Map = struct {
        fn map(_: *parz.Worker(void), shared: []const u64, index: usize) anyerror!u64 {
            return shared[index];
        }
    };
    const Combine = struct {
        fn combine(a: u64, b: u64) u64 {
            return a + b;
        }
    };

    var parallel_result: u64 = 0;
    var parallel_ns: i96 = std.math.maxInt(i96);
    const repeats = 5;
    for (0..repeats) |_| {
        const start = now(io);
        parallel_result = try parz.parallelFold(
            &pool,
            u64,
            data,
            count,
            .{ .min_chunk = 4096, .chunks_per_worker = 4 },
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
        "parallel_for count={d} workers={d} serial_ns={d} parallel_ns={d} speedup={d:.2}\n",
        .{ count, pool.spawned_background, serial_ns, parallel_ns, speedup },
    );
}
