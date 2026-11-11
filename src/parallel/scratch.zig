//! Explicit caller-owned dispatch storage. No allocation and no sharing.
const std = @import("std");

pub const Scratch = struct {
    buffer: std.heap.FixedBufferAllocator,
    busy: bool = false,

    pub fn init(bytes: []u8) Scratch {
        return .{ .buffer = std.heap.FixedBufferAllocator.init(bytes) };
    }

    /// A nested call using this scratch falls back to its own bounded stack.
    /// Concurrent callers must use separate scratch objects.
    pub fn acquire(self: *Scratch) ?std.mem.Allocator {
        if (self.busy) return null;
        self.busy = true;
        self.buffer.reset();
        return self.buffer.allocator();
    }

    pub fn release(self: *Scratch) void {
        std.debug.assert(self.busy);
        self.buffer.reset();
        self.busy = false;
    }
};

pub const Lease = struct {
    scratch: ?*Scratch,
    allocator: std.mem.Allocator,

    pub fn init(requested: ?*Scratch, fallback: std.mem.Allocator) Lease {
        if (requested) |scratch| {
            if (scratch.acquire()) |a| return .{ .scratch = scratch, .allocator = a };
        }
        return .{ .scratch = null, .allocator = fallback };
    }

    pub fn deinit(self: *Lease) void {
        if (self.scratch) |scratch| scratch.release();
    }
};

test "dispatch scratch nested leases do not reset outstanding storage" {
    var bytes: [128]u8 = undefined;
    var scratch = Scratch.init(&bytes);
    const a = scratch.acquire().?;
    const data = try a.alloc(u8, 64);
    @memset(data, 0x5b);
    try std.testing.expect(scratch.acquire() == null);
    for (data) |byte| try std.testing.expectEqual(@as(u8, 0x5b), byte);
    scratch.release();
    const again = scratch.acquire().?;
    try std.testing.expectEqual(data.ptr, (try again.alloc(u8, 64)).ptr);
    scratch.release();
}

test "explicit dispatch scratch handles aligned results order and no heap across lanes" {
    const core = @import("../core.zig");
    const api = @import("../parallel.zig");
    const Packet = struct {
        hash: u64 align(128) = 0,
        factor: u64 = 1,
        fn map(_: *core.Worker(void), _: void, index: usize) @This() {
            return .{ .hash = index + 1, .factor = 31 };
        }
        fn fallible(w: *core.Worker(void), shared: void, i: usize) anyerror!@This() {
            return map(w, shared, i);
        }
        fn combine(a: @This(), b: @This()) @This() {
            return .{ .hash = a.hash *% b.factor +% b.hash, .factor = a.factor *% b.factor };
        }
    };
    var expected = Packet{};
    for (0..256) |i| expected = Packet.combine(expected, .{ .hash = i + 1, .factor = 31 });
    for (0..5) |workers| {
        for ([_]usize{ 0, 16 }) |states| {
            var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
            var pool = try core.Pool(void).init(failing.allocator(), std.testing.io, .{
                .workers = workers,
                .max_workers = workers,
                .max_callers = 1,
                .max_execute_states = states,
            });
            defer pool.deinit();
            try pool.start();
            const allocated = failing.alloc_index;
            failing.fail_index = allocated;
            var bytes: [32768]u8 align(128) = undefined;
            var scratch = Scratch.init(&bytes);
            for ([_]api.Schedule{ .dynamic, .static }) |schedule| {
                for (0..3) |_| {
                    const options = api.Options{ .serial_threshold = 0, .chunks_per_worker = 64, .max_chunks = 64, .schedule = schedule, .scratch = &scratch };
                    try std.testing.expectEqualDeep(expected, try api.parallelFoldInfallible(&pool, Packet, {}, 256, options, .{}, Packet.map, Packet.combine));
                    try std.testing.expectEqualDeep(expected, try api.parallelFold(&pool, Packet, {}, 256, options, .{}, Packet.fallible, Packet.combine));
                    try std.testing.expect(!scratch.busy);
                    try std.testing.expectEqual(@as(usize, 0), scratch.buffer.end_index);
                }
            }
            try std.testing.expectEqual(allocated, failing.alloc_index);
            try std.testing.expect(!failing.has_induced_failure);
        }
    }
}

test "strict dispatch scratch rejects both allocation stages before callbacks and releases slots" {
    const core = @import("../core.zig");
    const api = @import("../parallel.zig");
    const Run = struct {
        fn map(_: *core.Worker(void), calls: *std.atomic.Value(usize), i: usize) u64 {
            _ = calls.fetchAdd(1, .monotonic);
            return i;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
        fn fail(_: *core.Worker(void), _: void, c: api.Chunk) anyerror!void {
            return if (c.start == 0) error.FirstChunk else error.LaterChunk;
        }
    };
    for (0..4) |workers| {
        var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
        });
        defer pool.deinit();
        try pool.start();
        var calls = std.atomic.Value(usize).init(0);
        var bytes: [4096]u8 align(16) = undefined;
        // First buffer cannot fit results. The second fits results exactly,
        // so lane-future allocation fails when there is a background worker.
        for ([_]usize{ 1, 512 }) |length| {
            if (length == 512 and pool.parallelWorkerCount() == 1) continue;
            var scratch = Scratch.init(bytes[0..length]);
            try std.testing.expectError(error.OutOfMemory, api.parallelFoldInfallible(&pool, u64, &calls, 64, .{
                .serial_threshold = 0,
                .chunks_per_worker = 64,
                .max_chunks = 64,
                .scratch = &scratch,
            }, 0, Run.map, Run.add));
            try std.testing.expectEqual(@as(usize, 0), calls.load(.monotonic));
            try std.testing.expect(!scratch.busy);
            try std.testing.expect(!pool.caller_busy[0]);
        }
        var scratch = Scratch.init(&bytes);
        const options = api.Options{ .serial_threshold = 0, .max_chunks = 8, .chunks_per_worker = 8, .scratch = &scratch };
        try std.testing.expectEqual(@as(u64, 2016), try api.parallelFoldInfallible(&pool, u64, &calls, 64, options, 0, Run.map, Run.add));
        try std.testing.expectError(error.FirstChunk, api.parallelForRange(&pool, {}, 64, options, Run.fail));
        try std.testing.expect(!scratch.busy);
        try std.testing.expect(!pool.caller_busy[0]);
    }
}

test "nested scratch calls use independent storage and retain outer results" {
    const core = @import("../core.zig");
    const api = @import("../parallel.zig");
    const Run = struct {
        fn map(_: *core.Worker(void), _: void, i: usize) u64 {
            return i;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
        fn range(w: *core.Worker(void), scratch: *Scratch, c: api.Chunk) anyerror!u64 {
            const inner = try api.parallelFoldInfallible(w, u64, {}, 64, .{
                .serial_threshold = 0,
                .max_chunks = 7,
                .chunks_per_worker = 7,
                .scratch = scratch,
            }, 0, map, add);
            if (inner != 2016) return error.WrongNestedResult;
            return (c.start + c.end - 1) * (c.end - c.start) / 2;
        }
    };
    for (0..5) |workers| {
        var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
        });
        defer pool.deinit();
        try pool.start();
        var bytes: [4096]u8 = undefined;
        var scratch = Scratch.init(&bytes);
        for ([_]api.Schedule{ .dynamic, .static }) |schedule| {
            for (0..5) |_| {
                try std.testing.expectEqual(@as(u64, 32896), try api.parallelFoldRange(&pool, u64, &scratch, 257, .{
                    .serial_threshold = 0,
                    .max_chunks = 9,
                    .chunks_per_worker = 9,
                    .schedule = schedule,
                    .scratch = &scratch,
                }, 0, Run.range, Run.add));
                try std.testing.expect(!scratch.busy);
            }
        }
    }
}

test "cancellation drains scratch callbacks before storage and caller are released" {
    const core = @import("../core.zig");
    const api = @import("../parallel.zig");
    const CancelToken = @import("../cancel.zig").CancelToken;
    const State = struct {
        token: CancelToken = .{},
        live: std.atomic.Value(usize) = .init(0),
        fn map(_: *core.Worker(void), self: *@This(), i: usize) u64 {
            _ = self.live.fetchAdd(1, .monotonic);
            defer _ = self.live.fetchSub(1, .monotonic);
            if (i == 4095) self.token.cancel();
            return i;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
    };
    for (0..5) |workers| {
        var pool = try core.Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
        });
        defer pool.deinit();
        try pool.start();
        var bytes: [8192]u8 = undefined;
        var scratch = Scratch.init(&bytes);
        var state = State{};
        for ([_]api.Schedule{ .dynamic, .static }) |schedule| {
            for (0..3) |_| {
                state.token.reset();
                try std.testing.expectError(error.Cancelled, api.parallelFoldInfallible(&pool, u64, &state, 4096, .{
                    .serial_threshold = 0,
                    .max_chunks = 32,
                    .chunks_per_worker = 32,
                    .schedule = schedule,
                    .scratch = &scratch,
                    .cancel = &state.token,
                }, 0, State.map, State.add));
                try std.testing.expectEqual(@as(usize, 0), state.live.load(.monotonic));
                try std.testing.expect(!scratch.busy);
                try std.testing.expect(!pool.caller_busy[0]);
            }
        }
    }
}
