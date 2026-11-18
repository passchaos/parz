//! Context initialization and destruction for registered and temporary lanes.

const std = @import("std");
const Pool = @import("pool.zig").Pool;

pub fn initContext(options: anytype, allocator: std.mem.Allocator, index: usize) !@TypeOf(options).Context {
    const Ctx = @TypeOf(options).Context;
    if (comptime Ctx == void) return {};
    const init = options.context_init orelse return error.MissingContextInit;
    return init(allocator, index);
}

pub fn deinitContext(ctx: anytype, allocator: std.mem.Allocator, options: anytype) void {
    const Ctx = @TypeOf(options).Context;
    if (comptime Ctx == void) return;
    if (options.context_deinit) |deinit| deinit(allocator, ctx);
}

var test_context_live = std.atomic.Value(u32).init(0);

test "pool: per-worker context init and deinit" {
    const io = std.testing.io;
    const Ctx = struct { index: usize };

    const Hooks = struct {
        fn init(_: std.mem.Allocator, index: usize) anyerror!Ctx {
            _ = test_context_live.fetchAdd(1, .monotonic);
            return .{ .index = index };
        }
        fn deinit(_: std.mem.Allocator, _: *Ctx) void {
            _ = test_context_live.fetchSub(1, .monotonic);
        }
    };

    _ = test_context_live.swap(0, .monotonic);
    var pool = try Pool(Ctx).init(std.testing.allocator, io, .{
        .workers = 1,
        .max_workers = 1,
        .max_callers = 1,
        .max_execute_states = 8,
        .context_init = Hooks.init,
        .context_deinit = Hooks.deinit,
    });
    try pool.start();

    const expected = pool.background_count + pool.caller_count;
    try std.testing.expectEqual(@as(u32, @intCast(expected)), test_context_live.load(.monotonic));

    const worker = pool.claimCaller() orelse return error.NoCallerSlot;
    try std.testing.expectEqual(pool.background_count, worker.context().index);
    pool.releaseCaller(worker);

    pool.deinit();
    try std.testing.expectEqual(@as(u32, 0), test_context_live.load(.monotonic));
}

test "affinity: context initialization failure releases selected CPU storage" {
    const Context = struct {
        fn init(_: std.mem.Allocator, index: usize) !@This() {
            if (index == 1) return error.ExpectedFailure;
            return .{};
        }
    };
    try std.testing.expectError(error.ExpectedFailure, Pool(Context).init(std.testing.allocator, std.testing.io, .{
        .workers = 2,
        .max_workers = 2,
        .pin_workers = true,
        .context_init = Context.init,
    }));
}
