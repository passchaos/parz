//! Controlled idle/held-caller interval for external /proc wake accounting.
const std = @import("std");
const parz = @import("parz");
const affinity = @import("affinity.zig");

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const lanes = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 8;
    const cpu = if (args.next()) |a| try std.fmt.parseInt(usize, a, 10) else 31;
    const mode = args.next() orelse "idle";
    const held = !std.mem.eql(u8, mode, "idle");
    const parking = if (args.next()) |a| std.mem.eql(u8, a, "park") else false;
    if (lanes == 0) return error.InvalidArguments;
    var options = parz.Options(void){
        .workers = if (lanes > 1) lanes - 1 else 0,
        .max_workers = if (lanes == 1) 0 else 64,
        .max_callers = 1,
        .pin_workers = true,
    };
    if (comptime @hasField(parz.Options(void), "park_idle_heartbeat")) options.park_idle_heartbeat = parking;
    var pool = try parz.Pool(void).init(init.gpa, init.io, options);
    defer pool.deinit();
    try pool.start();
    try affinity.pinCaller(&pool, cpu);
    const caller: ?*parz.Worker(void) = if (held) blk: {
        if (comptime @hasDecl(@TypeOf(pool), "claimFlatCaller")) {
            if (std.mem.eql(u8, mode, "flat-held")) break :blk pool.claimFlatCaller() orelse return error.NoCallerSlot;
        }
        break :blk pool.claimCaller() orelse return error.NoCallerSlot;
    } else null;
    defer if (caller) |w| pool.releaseCaller(w);
    try init.io.sleep(std.Io.Duration.fromNanoseconds(100 * std.time.ns_per_ms), .awake);
    var parked: ?bool = null;
    if (comptime @hasField(@TypeOf(pool), "heartbeat_parked")) {
        pool.mutex.lockUncancelable(init.io);
        parked = pool.heartbeat_parked;
        pool.mutex.unlock(init.io);
    }
    std.debug.print("ready workers={d} mode={s} parking={} parked={any}\n", .{ pool.spawned_background, mode, parking, parked });
    try init.io.sleep(std.Io.Duration.fromNanoseconds(3 * std.time.ns_per_s), .awake);
}
