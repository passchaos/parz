//! Policy and lifetime check for the optional NUMA allocator.
const std = @import("std");
const parz = @import("parz");

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const name = args.next() orelse "local";
    const policy = std.meta.stringToEnum(parz.numa.Policy, name) orelse return error.InvalidPolicy;
    const node = if (args.next()) |arg| try std.fmt.parseInt(u16, arg, 10) else 0;
    const require = if (args.next()) |arg| std.mem.eql(u8, arg, "require") else false;
    var numa = try parz.NumaAllocator.init(init.gpa, .{
        .policy = policy,
        .nodes = if (policy == .local) &.{} else &.{node},
        .require_policy = require,
    });
    defer numa.deinit();
    const allocator = numa.allocator();
    const count = 1_000_000;
    if (allocator.alloc(u64, count)) |values| {
        for (values, 0..) |*value, index| value.* = index;
        var checksum: u64 = 0;
        for (values) |value| checksum += value;
        if (checksum != @as(u64, count) * (count - 1) / 2) return error.ChecksumMismatch;
        allocator.free(values);
        const stats = numa.stats();
        std.debug.print("numa policy={s} node={d} native={any} applied={d} fallback={d} failures={d} errno={d} live={d} checksum={d}\n", .{
            name, node, stats.native_supported, stats.policy_applied, stats.policy_fallbacks, stats.policy_failures, stats.last_errno, stats.live_allocations, checksum,
        });
    } else |err| {
        const stats = numa.stats();
        std.debug.print("numa policy={s} node={d} allocation_error={s} failures={d} errno={d} live={d}\n", .{ name, node, @errorName(err), stats.policy_failures, stats.last_errno, stats.live_allocations });
        return err;
    }
}
