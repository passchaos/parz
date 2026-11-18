//! Periodic lane pacing and explicit idle power/metadata controls.

const std = @import("std");
const builtin = @import("builtin");
const Pool = @import("pool.zig").Pool;
const Worker = @import("../core.zig").Worker;
const Task = @import("../core.zig").Task;
const Future = @import("../core.zig").Future;

/// Periodically mark every active worker as ready to share one batch
/// of local work. Small fork/join trees finish before the first
/// heartbeat, so they never pay thread-wakeup cost.
pub fn Heartbeat(comptime P: type) type {
    return struct {
        pub fn run(self: *P) void {
            var interval = self.options.heartbeat_interval_ns;
            var observed_epoch: usize = 0;
            var idle_since: ?std.Io.Clock.Timestamp = null;
            while (true) {
                self.io.sleep(
                    std.Io.Duration.fromNanoseconds(@max(interval, 1)),
                    .awake,
                ) catch |err| switch (err) {
                    error.Canceled => return,
                };
                if (self.is_stopping.load(.acquire)) return;
                // This shortcut is opt-in: repeated cumulative cold-scan comparisons
                // regressed, so defaults retain the original periodic metadata path.
                if (self.options.skip_idle_heartbeat_metadata and !self.options.park_idle_heartbeat and
                    !self.has_callers.load(.acquire) and
                    self.idle_workers.load(.monotonic) >= self.spawned_background)
                {
                    interval = self.options.idle_heartbeat_interval_ns;
                    continue;
                }
                // `active` is atomic, so the default periodic path publishes
                // flags without taking the pool mutex. Parking still needs the
                // mutex for its demand/park state.
                const parking = self.options.park_idle_heartbeat;
                if (parking) {
                    self.mutex.lockUncancelable(self.io);
                    if (observed_epoch != self.caller_epoch.load(.monotonic)) {
                        observed_epoch = self.caller_epoch.load(.monotonic);
                        idle_since = null;
                    }
                    while (!self.is_stopping.load(.monotonic)) {
                        if (self.heartbeat_demand.load(.monotonic)) {
                            if (self.active_callers.load(.monotonic) != 0 or self.idle_workers.load(.monotonic) < self.spawned_background) {
                                idle_since = null;
                                break;
                            }
                            if (idle_since == null) idle_since = std.Io.Clock.Timestamp.now(self.io, .awake);
                            if (idle_since.?.untilNow(self.io).raw.toNanoseconds() <
                                @max(self.options.idle_heartbeat_grace_ns, 0)) break;
                            self.heartbeat_demand.store(false, .monotonic);
                        }
                        self.heartbeat_parked = true;
                        self.heartbeat_ready.waitUncancelable(self.io, &self.mutex);
                        self.heartbeat_parked = false;
                        idle_since = null;
                        observed_epoch = self.caller_epoch.load(.monotonic);
                    }
                    if (self.is_stopping.load(.monotonic)) {
                        self.mutex.unlock(self.io);
                        return;
                    }
                }
                for (self.workers[0..self.worker_count]) |w| {
                    if (w.active.load(.monotonic)) w.heartbeat.store(true, .monotonic);
                }
                const idle = self.idle_workers.load(.monotonic);
                interval = if (idle >= self.spawned_background)
                    self.options.idle_heartbeat_interval_ns
                else
                    self.options.heartbeat_interval_ns;
                if (parking) self.mutex.unlock(self.io);
            }
        }
    };
}

test "heartbeat thread entry has a static pool parameter" {
    inline for (.{ void, struct { value: u64 = 0 } }) |Ctx| {
        const Entry = @typeInfo(@TypeOf(Heartbeat(Pool(Ctx)).run)).@"fn";
        try std.testing.expect(!Entry.is_generic);
        try std.testing.expect(Entry.params[0].type.? == *Pool(Ctx));
        try std.testing.expect(Entry.return_type.? == void);
    }
}

test "heartbeat parks with no callers wakes held callers and shuts down from park" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const Wait = struct {
        fn parked(pool: *Pool(void), expected: bool) !void {
            for (0..20000) |_| {
                pool.mutex.lockUncancelable(pool.io);
                const matches = pool.heartbeat_parked == expected;
                pool.mutex.unlock(pool.io);
                if (matches) return;
                try pool.io.sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_us), .awake);
            }
            return error.HeartbeatStateTimeout;
        }
        fn flag(worker: *Worker(void)) !void {
            for (0..20000) |_| {
                if (worker.heartbeat.load(.monotonic)) return;
                try worker.pool.io.sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_us), .awake);
            }
            return error.HeartbeatFlagTimeout;
        }
        fn leaf(_: *Task(void), value: u64) u64 {
            return value;
        }
    };
    for (1..5) |workers| {
        var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 2,
            .park_idle_heartbeat = true,
        });
        defer pool.deinit();
        try pool.start();
        if (pool.heartbeat_thread == null) continue;
        for (0..5) |_| {
            try Wait.parked(&pool, true);
            const first = pool.claimCaller().?;
            const second = pool.claimCaller().?;
            try std.testing.expectEqual(@as(usize, 2), pool.active_callers.load(.monotonic));
            try Wait.flag(first);
            try Wait.flag(second);
            try Wait.parked(&pool, false);
            pool.releaseCaller(first);
            try std.testing.expectEqual(@as(usize, 1), pool.active_callers.load(.monotonic));
            second.heartbeat.store(false, .monotonic);
            try Wait.flag(second);
            var task = second.begin();
            var future: Future(void, u64, u64) = undefined;
            future.initFork(&task, Wait.leaf, 19);
            try std.testing.expectEqual(@as(u64, 19), future.joinOrCall(&task, Wait.leaf));
            pool.releaseCaller(second);
            try std.testing.expectEqual(@as(usize, 0), pool.active_callers.load(.monotonic));
        }
        try Wait.parked(&pool, true);
        // The deferred deinit must wake a heartbeat blocked on its condition.
    }
}

test "explicit idle shortcut skips worker writes and resumes periodic flags for callers" {
    if (builtin.single_threaded) return error.SkipZigTest;
    var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 1,
        .skip_idle_heartbeat_metadata = true,
    });
    defer pool.deinit();
    try pool.start();
    if (pool.heartbeat_thread == null) return;
    try pool.io.sleep(std.Io.Duration.fromNanoseconds(2 * std.time.ns_per_ms), .awake);
    for (pool.background_storage[0..pool.spawned_background]) |*worker| {
        try std.testing.expect(!worker.heartbeat.load(.monotonic));
    }
    const caller = pool.claimCaller().?;
    var flagged = false;
    for (0..20000) |_| {
        if (caller.heartbeat.load(.monotonic)) {
            flagged = true;
            break;
        }
        try pool.io.sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_us), .awake);
    }
    pool.releaseCaller(caller);
    try std.testing.expect(flagged);
    try std.testing.expect(!pool.heartbeat_parked);
}

test "default heartbeat preserves periodic idle lane flags" {
    if (builtin.single_threaded) return error.SkipZigTest;
    var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 1,
    });
    defer pool.deinit();
    try pool.start();
    try std.testing.expect(!pool.options.skip_idle_heartbeat_metadata);
    if (pool.heartbeat_thread == null) return;
    var flagged = false;
    for (0..20000) |_| {
        if (pool.background_storage[0].heartbeat.load(.monotonic)) {
            flagged = true;
            break;
        }
        try pool.io.sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_us), .awake);
    }
    try std.testing.expect(flagged);
    try std.testing.expect(!pool.heartbeat_parked);
}

test "flat callers keep heartbeat parked until recursive begin requests pacing" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const Run = struct {
        fn parked(pool: *Pool(void)) !void {
            for (0..20000) |_| {
                pool.mutex.lockUncancelable(pool.io);
                const value = pool.heartbeat_parked and !pool.heartbeat_demand.load(.monotonic);
                pool.mutex.unlock(pool.io);
                if (value) return;
                try pool.io.sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_us), .awake);
            }
            return error.HeartbeatStateTimeout;
        }
        fn map(_: *Worker(void), _: void, i: usize) u64 {
            return i;
        }
        fn add(a: u64, b: u64) u64 {
            return a + b;
        }
        fn leaf(_: *Task(void), value: u64) u64 {
            return value;
        }
    };
    for (1..5) |workers| {
        var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .park_idle_heartbeat = true,
        });
        defer pool.deinit();
        try pool.start();
        if (pool.heartbeat_thread == null) continue;
        for (0..3) |_| {
            const caller = pool.claimFlatCaller().?;
            try Run.parked(&pool);
            try std.testing.expect(!pool.heartbeat_demand.load(.monotonic));
            try std.testing.expectEqual(@as(u64, 8386560), try @import("../parallel.zig").parallelFoldInfallible(caller, u64, {}, 4096, .{
                .serial_threshold = 0,
                .max_chunks = 9,
                .chunks_per_worker = 9,
            }, 0, Run.map, Run.add));
            try std.testing.expect(!pool.heartbeat_demand.load(.monotonic));
            var task = caller.begin();
            try std.testing.expect(pool.heartbeat_demand.load(.monotonic));
            var future: Future(void, u64, u64) = undefined;
            future.initFork(&task, Run.leaf, 31);
            try std.testing.expectEqual(@as(u64, 31), future.joinOrCall(&task, Run.leaf));
            pool.releaseCaller(caller);
            try Run.parked(&pool);
        }
    }
}
