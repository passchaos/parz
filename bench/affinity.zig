//! Optional fixed caller placement for paired scheduler benchmarks.
const std = @import("std");
const builtin = @import("builtin");

pub fn pinCaller(pool: anytype, cpu: usize) !void {
    if (comptime builtin.os.tag != .linux) return error.AffinityUnsupported;
    for (pool.pinned_cpus[0..pool.spawned_background]) |worker_cpu| {
        if (cpu == worker_cpu) return error.CallerCpuUsedByWorker;
    }
    const allowed = try std.posix.sched_getaffinity(0);
    const bits = @bitSizeOf(@TypeOf(allowed[0]));
    if (cpu >= allowed.len * bits) return error.InvalidCpu;
    const bit = @as(@TypeOf(allowed[0]), 1) << @intCast(cpu % bits);
    if (allowed[cpu / bits] & bit == 0) return error.CallerCpuOutsideAllowedSet;
    var selected = std.mem.zeroes(std.os.linux.cpu_set_t);
    selected[cpu / bits] = bit;
    try std.os.linux.sched_setaffinity(0, &selected);
}

/// Explicit benchmark-only placement; library defaults never pin heartbeat.
pub fn pinHeartbeat(pool: anytype, cpu: usize) !void {
    if (comptime builtin.os.tag != .linux or builtin.link_libc) return error.AffinityUnsupported;
    for (pool.pinned_cpus[0..pool.spawned_background]) |worker_cpu| {
        if (cpu == worker_cpu) return error.HeartbeatCpuUsedByWorker;
    }
    const caller_set = try std.posix.sched_getaffinity(0);
    const bits = @bitSizeOf(@TypeOf(caller_set[0]));
    if (cpu >= caller_set.len * bits) return error.InvalidCpu;
    const bit = @as(@TypeOf(caller_set[0]), 1) << @intCast(cpu % bits);
    if (caller_set[cpu / bits] & bit != 0) return error.HeartbeatCpuUsedByCaller;
    var selected = std.mem.zeroes(std.os.linux.cpu_set_t);
    selected[cpu / bits] = bit;
    const thread = pool.heartbeat_thread orelse return error.NoHeartbeatThread;
    try std.os.linux.sched_setaffinity(thread.getHandle(), &selected);
}
