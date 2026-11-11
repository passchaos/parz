//! Per-object VMA allocation versus lazy lane arena reuse, on one fixed CPU.
const std = @import("std");
const parz = @import("parz");
const timing = @import("timing.zig");

const Run = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    count: usize,
    fn direct(self: *@This()) !u64 {
        var sum: u64 = 0;
        for (0..self.count) |i| {
            const values = try self.allocator.alloc(u64, 8);
            @memset(values, i);
            std.mem.doNotOptimizeAway(values.ptr);
            sum +%= values[7];
            self.allocator.free(values);
        }
        return sum;
    }
    fn retained(self: *@This()) !u64 {
        defer _ = self.arena.reset(.retain_capacity);
        var sum: u64 = 0;
        for (0..self.count) |i| {
            const values = try self.arena.allocator().alloc(u64, 8);
            @memset(values, i);
            std.mem.doNotOptimizeAway(values.ptr);
            sum +%= values[7];
        }
        return sum;
    }
};

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const count = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 4096;
    const cpu = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 31;
    if (count == 0) return error.InvalidArguments;
    var mask = std.mem.zeroes(std.os.linux.cpu_set_t);
    if (cpu >= mask.len * @bitSizeOf(usize)) return error.InvalidCpu;
    mask[cpu / @bitSizeOf(usize)] = @as(usize, 1) << @intCast(cpu % @bitSizeOf(usize));
    try std.os.linux.sched_setaffinity(0, &mask);
    var numa = try parz.NumaAllocator.init(init.gpa, .{});
    defer numa.deinit();
    var run = Run{ .allocator = numa.allocator(), .arena = std.heap.ArenaAllocator.init(numa.allocator()), .count = count };
    defer run.arena.deinit();
    const expected: u64 = @intCast(@as(u128, count) * (count - 1) / 2);
    if (try run.retained() != expected) return error.ChecksumMismatch;
    const before = numa.stats().policy_applied + numa.stats().policy_fallbacks;
    if (try run.retained() != expected) return error.ChecksumMismatch;
    const reuse_allocations = numa.stats().policy_applied + numa.stats().policy_fallbacks - before;
    const times = try timing.paired(u64, init.gpa, init.io, 9, expected, &run, Run.direct, Run.retained);
    const stats = numa.stats();
    std.debug.print("numa-arena count={d} cpu={d} checksum={d} serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median mode=allocation-comparison reuse_allocations={d} policy_applied={d} policy_fallbacks={d} errno={d}\n", .{
        count, cpu, expected, times.serial_ns, times.parallel_ns, times.speedup(), reuse_allocations, stats.policy_applied, stats.policy_fallbacks, stats.last_errno,
    });
}
