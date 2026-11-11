//! Fixed-input single-consumer lookup comparison: all shards vs known producers.
const std = @import("std");
const parz = @import("parz");
const timing = @import("timing.zig");

fn run(comptime shards: usize, init: std.process.Init, count: usize, cpu: usize) !void {
    const Q = parz.sync.ShardedMpscQueue(u64, shards);
    var queue = try Q.init(init.gpa, 4);
    defer queue.deinit();
    var mask = std.mem.zeroes(std.os.linux.cpu_set_t);
    if (cpu >= mask.len * @bitSizeOf(usize)) return error.InvalidCpu;
    mask[cpu / @bitSizeOf(usize)] = @as(usize, 1) << @intCast(cpu % @bitSizeOf(usize));
    try std.os.linux.sched_setaffinity(0, &mask);
    const active = [_]usize{ 1, shards - 1 };
    const Run = struct {
        q: *Q,
        active: []const usize,
        count: usize,
        fn full(self: *@This()) !u64 {
            var sum: u64 = 0;
            for (0..self.count) |i| {
                if (!self.q.tryPush(self.active[i % 2], i)) return error.UnexpectedFull;
                const value = self.q.tryPop() orelse return error.UnexpectedEmpty;
                if (value != i) return error.FifoMismatch;
                sum +%= value;
            }
            return sum;
        }
        fn selected(self: *@This()) !u64 {
            if (comptime !@hasDecl(Q, "consumer")) return self.full();
            var view = try self.q.consumer(&.{ 1, shards - 1 });
            var sum: u64 = 0;
            for (0..self.count) |i| {
                if (!self.q.tryPush(self.active[i % 2], i)) return error.UnexpectedFull;
                const value = view.tryPop() orelse return error.UnexpectedEmpty;
                if (value != i) return error.FifoMismatch;
                sum +%= value;
            }
            return sum;
        }
    };
    var context = Run{ .q = &queue, .active = &active, .count = count };
    const expected: u64 = @intCast(@as(u128, count) * (count - 1) / 2);
    const times = try timing.paired(u64, init.gpa, init.io, 9, expected, &context, Run.full, Run.selected);
    std.debug.print("sharded-sparse shards={d} active=2 count={d} cpu={d} checksum={d} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median mode=single-consumer-lookup\n", .{
        shards, count, cpu, expected, times.serial_ns, times.parallel_ns, times.speedup(),
    });
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const shards = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 128;
    const count = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 100000;
    const cpu = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 31;
    if (count == 0) return error.InvalidArguments;
    switch (shards) {
        4 => try run(4, init, count, cpu),
        128 => try run(128, init, count, cpu),
        else => return error.InvalidArguments,
    }
}
