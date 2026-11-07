//! Linux CPU affinity and NUMA placement helpers.
//!
//! These functions are best-effort: unsupported targets return an empty CPU
//! list or a no-op, and affinity/policy failures never fail pool startup. They
//! are kept separate from the scheduler so `core.zig` only contains scheduling
//! logic.

const std = @import("std");
const builtin = @import("builtin");

/// Build a CPU list with one logical CPU per physical core (best effort).
/// On Linux, read the SMT sibling list from sysfs; fall back to the allowed
/// affinity set when sysfs is unavailable.
pub fn pinnedCpuList(allocator: std.mem.Allocator, io: std.Io) ![]u32 {
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

    var selected = std.ArrayList(u32).empty;
    defer selected.deinit(allocator);
    var path_buf: [128]u8 = undefined;
    for (allowed.items) |cpu| {
        const path = std.fmt.bufPrint(
            &path_buf,
            "/sys/devices/system/cpu/cpu{d}/topology/thread_siblings_list",
            .{cpu},
        ) catch {
            try selected.append(allocator, cpu);
            continue;
        };
        const content = std.Io.Dir.cwd().readFileAlloc(
            io,
            path,
            allocator,
            .limited(64),
        ) catch {
            try selected.append(allocator, cpu);
            continue;
        };
        defer allocator.free(content);

        if (!hasEarlierAllowedSibling(allowed.items, cpu, content)) try selected.append(allocator, cpu);
    }

    if (selected.items.len == 0) return try allowed.toOwnedSlice(allocator);
    return try selected.toOwnedSlice(allocator);
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
