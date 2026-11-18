//! Linux CPU affinity and NUMA placement helpers.
//!
//! These functions are best-effort: unsupported targets return an empty CPU
//! list or a no-op, and affinity/policy failures never fail pool startup. They
//! are kept separate from the scheduler so `core.zig` only contains scheduling
//! logic.

const std = @import("std");
const builtin = @import("builtin");

/// Placement policy for `pinnedCpuList`. Defaults preserve the original
/// one-logical-CPU-per-physical-core order.
pub const CpuPolicy = struct {
    /// Sort selected CPUs by descending sysfs `cpu_capacity`, so hybrid CPUs
    /// use performance cores before efficiency cores. Missing sysfs data keeps
    /// the original order.
    prefer_performance_cores: bool = false,
    /// Append SMT siblings after every physical core has one logical CPU.
    use_smt_siblings: bool = false,
};

/// Build a CPU list with one logical CPU per physical core (best effort).
/// On Linux, read the SMT sibling list from sysfs; fall back to the allowed
/// affinity set when sysfs is unavailable.
pub fn pinnedCpuList(allocator: std.mem.Allocator, io: std.Io, policy: CpuPolicy) ![]u32 {
    if (comptime builtin.os.tag != .linux) return &.{};

    const affinity = std.posix.sched_getaffinity(0) catch return &.{};
    var allowed = std.ArrayList(u32).empty;
    defer allowed.deinit(allocator);
    for (affinity, 0..) |word, word_index| {
        var bits = word;
        while (bits != 0) {
            const bit = @ctz(bits);
            const cpu: u32 = @intCast(word_index * @bitSizeOf(usize) + bit);
            try allowed.append(allocator, cpu);
            bits &= bits - 1;
        }
    }
    if (allowed.items.len == 0) return &.{};

    const first = try allocator.alloc(bool, allowed.items.len);
    defer allocator.free(first);
    const capacity = try allocator.alloc(u64, allowed.items.len);
    defer allocator.free(capacity);
    @memset(capacity, 0);
    var path_buf: [128]u8 = undefined;
    for (allowed.items, 0..) |cpu, index| {
        first[index] = true;
        const path = std.fmt.bufPrint(
            &path_buf,
            "/sys/devices/system/cpu/cpu{d}/topology/thread_siblings_list",
            .{cpu},
        ) catch continue;
        const content = std.Io.Dir.cwd().readFileAlloc(
            io,
            path,
            allocator,
            .limited(64),
        ) catch continue;
        defer allocator.free(content);
        first[index] = !hasEarlierAllowedSibling(allowed.items, cpu, content);
        if (policy.prefer_performance_cores) {
            capacity[index] = readCpuCapacity(io, allocator, cpu) orelse 0;
        }
    }

    const selected = try allocator.alloc(u32, allowed.items.len);
    errdefer allocator.free(selected);
    const count = buildCpuOrder(allowed.items, first, capacity, policy, selected);
    if (count == 0) return try allowed.toOwnedSlice(allocator);
    if (count != selected.len) return try allocator.realloc(selected, count);
    return selected;
}

/// Pure ordering step, separated so placement policies can be tested without
/// depending on the host topology.
pub fn buildCpuOrder(
    allowed: []const u32,
    first: []const bool,
    capacity: []const u64,
    policy: CpuPolicy,
    out: []u32,
) usize {
    std.debug.assert(allowed.len == first.len and allowed.len == capacity.len);
    var count: usize = 0;
    for (allowed, 0..) |cpu, index| {
        if (first[index]) {
            out[count] = cpu;
            count += 1;
        }
    }
    if (policy.use_smt_siblings) {
        for (allowed, 0..) |cpu, index| {
            if (!first[index]) {
                out[count] = cpu;
                count += 1;
            }
        }
    }
    if (policy.prefer_performance_cores) {
        // Stable insertion sort by descending capacity; CPU lists are tiny.
        var i: usize = 1;
        while (i < count) : (i += 1) {
            const cpu = out[i];
            const cpu_capacity = capacityOf(allowed, capacity, cpu);
            var j = i;
            while (j > 0 and capacityOf(allowed, capacity, out[j - 1]) < cpu_capacity) : (j -= 1) {
                out[j] = out[j - 1];
            }
            out[j] = cpu;
        }
    }
    return count;
}

fn capacityOf(allowed: []const u32, capacity: []const u64, cpu: u32) u64 {
    for (allowed, 0..) |candidate, index| {
        if (candidate == cpu) return capacity[index];
    }
    return 0;
}

fn readCpuCapacity(io: std.Io, allocator: std.mem.Allocator, cpu: u32) ?u64 {
    var path_buf: [128]u8 = undefined;
    const path = std.fmt.bufPrint(
        &path_buf,
        "/sys/devices/system/cpu/cpu{d}/cpu_capacity",
        .{cpu},
    ) catch return null;
    const content = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(32)) catch return null;
    defer allocator.free(content);
    return std.fmt.parseInt(u64, std.mem.trim(u8, content, " \n\r\t"), 10) catch null;
}

/// Sysfs lists all siblings, including CPUs outside the caller's affinity.
/// Pick the first allowed sibling, rather than requiring the absolute first.
fn hasEarlierAllowedSibling(allowed: []const u32, cpu: u32, text: []const u8) bool {
    var groups = std.mem.splitScalar(u8, text, ',');
    while (groups.next()) |group| {
        const range = std.mem.trim(u8, group, " \n\r\t");
        const dash = std.mem.indexOfScalar(u8, range, '-');
        const first = std.fmt.parseInt(u32, if (dash) |offset| range[0..offset] else range, 10) catch return false;
        const last = if (dash) |offset| std.fmt.parseInt(u32, range[offset + 1 ..], 10) catch return false else first;
        if (last < first) return false;
        for (allowed) |other| {
            if (other >= cpu) break;
            if (other >= first and other <= last) return true;
        }
    }
    return false;
}

/// Allowed CPU count, capped by the affinity mask on Linux.
pub fn effectiveCpuCount() usize {
    if (builtin.single_threaded) return 1;
    if (builtin.os.tag == .linux) {
        const affinity = std.posix.sched_getaffinity(0) catch
            return std.Thread.getCpuCount() catch 1;
        return @max(@as(usize, 1), std.posix.CPU_COUNT(affinity));
    }
    return std.Thread.getCpuCount() catch 1;
}

/// Pin the calling thread to `cpu`. No-op outside Linux.
pub fn pinCurrentThread(cpu: u32) void {
    if (comptime builtin.os.tag != .linux) return;
    const word = cpu / @bitSizeOf(usize);
    const bit = cpu % @bitSizeOf(usize);
    var set = std.mem.zeroes(std.os.linux.cpu_set_t);
    set[word] = @as(usize, 1) << @intCast(bit);
    std.os.linux.sched_setaffinity(0, &set) catch {};
}

/// NUMA node the calling thread is currently running on, if known.
pub fn currentNumaNode() ?u16 {
    if (comptime builtin.os.tag != .linux) return null;
    var cpu: u32 = 0;
    var node: u32 = 0;
    const rc = std.os.linux.syscall3(
        .getcpu,
        @intFromPtr(&cpu),
        @intFromPtr(&node),
        0,
    );
    if (@as(isize, @bitCast(rc)) < 0) return null;
    if (node == std.math.maxInt(u32)) return null;
    return @intCast(node);
}

/// Apply `MPOL_PREFERRED` for `node` to the calling thread. No-op outside
/// Linux or when the node cannot be represented.
pub fn applyNumaPreferred(node: u16) void {
    if (comptime builtin.os.tag != .linux) return;
    if (node >= @bitSizeOf(usize)) return;

    var mask: usize = @as(usize, 1) << @intCast(node);
    const MPOL_PREFERRED: usize = 1;
    _ = std.os.linux.syscall3(
        .set_mempolicy,
        MPOL_PREFERRED,
        @intFromPtr(&mask),
        @as(usize, node) + 1,
    );
}

test "affinity: first allowed siblings survive restricted CPU sets" {
    try std.testing.expect(!hasEarlierAllowedSibling(&.{ 1, 2 }, 1, "0-1\n"));
    try std.testing.expect(!hasEarlierAllowedSibling(&.{ 1, 2 }, 2, "2-3\n"));
    try std.testing.expect(hasEarlierAllowedSibling(&.{ 1, 2, 3 }, 3, "2-3\n"));
    try std.testing.expect(!hasEarlierAllowedSibling(&.{ 0, 17, 18 }, 17, "1,17\n"));
    try std.testing.expect(hasEarlierAllowedSibling(&.{ 1, 17 }, 17, "1,17\n"));
    try std.testing.expect(hasEarlierAllowedSibling(&.{ 1, 17, 18 }, 18, "0-3,16-19\n"));
}

test "affinity: topology policies order physical cores, siblings and capacity" {
    const allowed = [_]u32{ 0, 1, 2, 3 };
    const first = [_]bool{ true, false, true, false };
    const capacity = [_]u64{ 100, 50, 200, 60 };
    var out: [4]u32 = undefined;

    try std.testing.expectEqual(@as(usize, 2), buildCpuOrder(&allowed, &first, &capacity, .{}, &out));
    try std.testing.expectEqualSlices(u32, &.{ 0, 2 }, out[0..2]);

    try std.testing.expectEqual(@as(usize, 4), buildCpuOrder(&allowed, &first, &capacity, .{ .use_smt_siblings = true }, &out));
    try std.testing.expectEqualSlices(u32, &.{ 0, 2, 1, 3 }, &out);

    try std.testing.expectEqual(@as(usize, 2), buildCpuOrder(&allowed, &first, &capacity, .{ .prefer_performance_cores = true }, &out));
    try std.testing.expectEqualSlices(u32, &.{ 2, 0 }, out[0..2]);

    try std.testing.expectEqual(@as(usize, 4), buildCpuOrder(&allowed, &first, &capacity, .{
        .prefer_performance_cores = true,
        .use_smt_siblings = true,
    }, &out));
    try std.testing.expectEqualSlices(u32, &.{ 2, 0, 3, 1 }, &out);

    // Unknown capacities (all zero) keep the original stable order.
    const unknown = [_]u64{ 0, 0, 0, 0 };
    try std.testing.expectEqual(@as(usize, 4), buildCpuOrder(&allowed, &first, &unknown, .{
        .prefer_performance_cores = true,
        .use_smt_siblings = true,
    }, &out));
    try std.testing.expectEqualSlices(u32, &.{ 0, 2, 1, 3 }, &out);
}
