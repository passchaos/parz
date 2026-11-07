//! Counting semaphore and wait group.

const std = @import("std");
const builtin = @import("builtin");

/// Counting semaphore. `wait` may be cancelled by the supplied `std.Io`.
pub const Semaphore = struct {
    inner: std.Io.Semaphore = .{},
    wide_waiters: usize = 0,

    pub fn init(permits: usize) Semaphore {
        return .{ .inner = .{ .permits = permits } };
    }

    pub fn wait(self: *Semaphore, io: std.Io) std.Io.Cancelable!void {
        try self.inner.mutex.lock(io);
        defer self.inner.mutex.unlock(io);
        while (self.inner.permits == 0) try self.inner.cond.wait(io, &self.inner.mutex);
        self.inner.permits -= 1;
        self.wakeAvailable(io);
    }

    pub fn waitUncancelable(self: *Semaphore, io: std.Io) void {
        self.inner.mutex.lockUncancelable(io);
        defer self.inner.mutex.unlock(io);
        while (self.inner.permits == 0) self.inner.cond.waitUncancelable(io, &self.inner.mutex);
        self.inner.permits -= 1;
        self.wakeAvailable(io);
    }

    /// Atomically acquire `permits`, waiting until the complete request is
    /// available. Zero returns immediately.
    pub fn waitMany(self: *Semaphore, io: std.Io, permits: usize) std.Io.Cancelable!void {
        if (permits == 0) return;
        if (permits == 1) return self.wait(io);
        try self.inner.mutex.lock(io);
        defer self.inner.mutex.unlock(io);
        self.wide_waiters += 1;
        var registered = true;
        defer {
            if (registered) self.wide_waiters -= 1;
        }
        while (self.inner.permits < permits) try self.inner.cond.wait(io, &self.inner.mutex);
        self.wide_waiters -= 1;
        registered = false;
        self.inner.permits -= permits;
        self.wakeAvailable(io);
    }

    pub fn waitManyUncancelable(self: *Semaphore, io: std.Io, permits: usize) void {
        if (permits == 0) return;
        if (permits == 1) return self.waitUncancelable(io);
        self.inner.mutex.lockUncancelable(io);
        defer self.inner.mutex.unlock(io);
        self.wide_waiters += 1;
        while (self.inner.permits < permits) self.inner.cond.waitUncancelable(io, &self.inner.mutex);
        self.wide_waiters -= 1;
        self.inner.permits -= permits;
        self.wakeAvailable(io);
    }

    pub fn post(self: *Semaphore, io: std.Io) void {
        self.inner.mutex.lockUncancelable(io);
        defer self.inner.mutex.unlock(io);
        self.inner.permits += 1;
        self.wakeAvailable(io);
    }

    /// Release `permits` with one lock and one initial wake-up. Each waiter
    /// signals the next while permits remain, matching std.Io.Semaphore.
    pub fn postMany(self: *Semaphore, io: std.Io, permits: usize) void {
        if (permits == 0) return;
        if (permits == 1) return self.post(io);
        self.inner.mutex.lockUncancelable(io);
        defer self.inner.mutex.unlock(io);
        self.inner.permits += permits;
        self.wakeAvailable(io);
    }

    fn wakeAvailable(self: *Semaphore, io: std.Io) void {
        if (self.inner.permits == 0) return;
        if (self.wide_waiters == 0) self.inner.cond.signal(io) else self.inner.cond.broadcast(io);
    }
};

/// Wait for a set of tasks to finish. `add` before starting them; each task
/// calls `done` exactly once.
pub const WaitGroup = struct {
    mutex: std.Io.Mutex = .init,
    cond: std.Io.Condition = .init,
    count: usize = 0,

    pub fn add(self: *WaitGroup, io: std.Io, n: usize) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        self.count += n;
    }

    pub inline fn done(self: *WaitGroup, io: std.Io) void {
        self.doneMany(io, 1);
    }

    pub fn doneMany(self: *WaitGroup, io: std.Io, n: usize) void {
        if (n == 0) return;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        std.debug.assert(self.count >= n);
        self.count -= n;
        if (self.count == 0) self.cond.broadcast(io);
    }

    pub fn wait(self: *WaitGroup, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        while (self.count != 0) self.cond.waitUncancelable(io, &self.mutex);
    }

    pub fn waitCancelable(self: *WaitGroup, io: std.Io) std.Io.Cancelable!void {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        while (self.count != 0) try self.cond.wait(io, &self.mutex);
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "semaphore wakes a waiter" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = std.testing.io;
    var semaphore = Semaphore{};
    const Worker = struct {
        fn run(sem: *Semaphore) void {
            sem.waitUncancelable(std.testing.io);
        }
    };
    const thread = try std.Thread.spawn(.{}, Worker.run, .{&semaphore});
    semaphore.post(io);
    thread.join();
}

test "semaphore batch permits wake scalar and batch waiters" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = std.testing.io;
    var semaphore = Semaphore.init(3);
    try semaphore.waitMany(io, 3);
    semaphore.postMany(io, 0);

    const State = struct {
        semaphore: *Semaphore,
        completed: std.atomic.Value(usize) = .init(0),

        fn waitOne(self: *@This()) void {
            self.semaphore.waitUncancelable(std.testing.io);
            _ = self.completed.fetchAdd(1, .release);
        }
        fn waitBatch(self: *@This()) void {
            self.semaphore.waitManyUncancelable(std.testing.io, 4);
            _ = self.completed.fetchAdd(4, .release);
        }
    };
    var state = State{ .semaphore = &semaphore };
    var scalar_waiters: [4]std.Thread = undefined;
    for (&scalar_waiters) |*thread| thread.* = try std.Thread.spawn(.{}, State.waitOne, .{&state});
    semaphore.postMany(io, 4);
    for (scalar_waiters) |thread| thread.join();
    try std.testing.expectEqual(@as(usize, 4), state.completed.load(.acquire));

    const batch_waiter = try std.Thread.spawn(.{}, State.waitBatch, .{&state});
    semaphore.postMany(io, 4);
    batch_waiter.join();
    try std.testing.expectEqual(@as(usize, 8), state.completed.load(.acquire));
    semaphore.waitManyUncancelable(io, 0);
}

test "semaphore mixed permit waiters do not strand available permits" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const State = struct {
        semaphore: Semaphore = .{},
        wide_started: std.atomic.Value(bool) = .init(false),
        scalar_started: std.atomic.Value(bool) = .init(false),

        fn waitWide(self: *@This()) void {
            self.wide_started.store(true, .release);
            self.semaphore.waitManyUncancelable(std.testing.io, 4);
        }
        fn waitScalar(self: *@This()) void {
            self.scalar_started.store(true, .release);
            self.semaphore.waitUncancelable(std.testing.io);
        }
    };
    var state = State{};
    const wide = try std.Thread.spawn(.{}, State.waitWide, .{&state});
    while (!state.wide_started.load(.acquire)) std.atomic.spinLoopHint();
    std.testing.io.sleep(std.Io.Duration.fromMilliseconds(1), .awake) catch unreachable;
    const scalar = try std.Thread.spawn(.{}, State.waitScalar, .{&state});
    while (!state.scalar_started.load(.acquire)) std.atomic.spinLoopHint();
    std.testing.io.sleep(std.Io.Duration.fromMilliseconds(1), .awake) catch unreachable;
    state.semaphore.post(std.testing.io);
    scalar.join();
    state.semaphore.postMany(std.testing.io, 4);
    wide.join();
}

test "wait group waits for all members" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const io = std.testing.io;
    const members = 4;
    var group = WaitGroup{};
    group.add(io, members);
    const Worker = struct {
        fn run(wg: *WaitGroup) void {
            wg.done(std.testing.io);
        }
    };
    var threads: [members]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, Worker.run, .{&group});
    group.wait(io);
    for (threads) |thread| thread.join();
}

test "wait group batch completion wakes cancelable waiters" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const members = 8;
    var group = WaitGroup{};
    group.add(std.testing.io, members);
    const State = struct {
        group: *WaitGroup,
        completed: std.atomic.Value(usize) = .init(0),
        fn run(self: *@This()) void {
            self.group.waitCancelable(std.testing.io) catch unreachable;
            _ = self.completed.fetchAdd(1, .release);
        }
    };
    var state = State{ .group = &group };
    var waiters: [2]std.Thread = undefined;
    for (&waiters) |*thread| thread.* = try std.Thread.spawn(.{}, State.run, .{&state});
    group.doneMany(std.testing.io, 0);
    group.doneMany(std.testing.io, 3);
    group.doneMany(std.testing.io, members - 3);
    for (waiters) |thread| thread.join();
    try std.testing.expectEqual(@as(usize, waiters.len), state.completed.load(.acquire));
    group.wait(std.testing.io);
}
