//! Intrusive, branch-reduced job list used by the scheduler.
//!
//! The list layout is derived from judofyr/spice (0BSD, Copyright (c) 2024
//! Magnus Holm). The job is embedded in the caller's stack frame, so `fork`
//! does not allocate. A sentinel head keeps `push` branch-free.
//!
//! Unlike the original, the job state lives in a small atomic flag. `join` is
//! allowed to read the state without the pool mutex, while a worker may be
//! transitioning a job from "shared" to "executing" under it. The flag makes
//! that transition observable in one step instead of through a pointer
//! encoding with a transient inconsistent window.

const std = @import("std");

pub const JobState = enum(u8) {
    pending,
    queued_local,
    queued_shared,
    executing,
};

/// Out-of-line state for a job that has been handed to another worker.
pub const ExecuteState = struct {
    io: std.Io,
    done: std.Io.Event = .unset,
    next_free: ?usize = null,
    index: usize = 0,
};

pub const Job = struct {
    handler: ?*const fn (task: *anyopaque, job: *Job) void,
    /// Queued: previous job. Executing: null. Pending: undefined.
    prev_or_null: ?*anyopaque,
    /// Queued: next job. Executing: *ExecuteState. Pending: undefined.
    next_or_state: ?*anyopaque,
    state_flag: std.atomic.Value(JobState) = .init(.pending),

    pub fn head() Job {
        return .{
            .handler = undefined,
            .prev_or_null = null,
            .next_or_state = null,
            .state_flag = .init(.pending),
        };
    }

    pub fn pending() Job {
        return .{
            .handler = null,
            .prev_or_null = undefined,
            .next_or_state = undefined,
            .state_flag = .init(.pending),
        };
    }

    pub inline fn state(self: *const Job) JobState {
        return self.state_flag.load(.acquire);
    }

    pub inline fn isTail(self: *const Job) bool {
        return self.next_or_state == null;
    }

    pub fn getExecuteState(self: *Job) *ExecuteState {
        std.debug.assert(self.state() == .executing);
        return @ptrCast(@alignCast(self.next_or_state.?));
    }

    pub fn setExecuteState(self: *Job, execute_state: *ExecuteState) void {
        std.debug.assert(self.state() == .queued_shared);
        self.next_or_state = @ptrCast(execute_state);
        self.state_flag.store(.executing, .release);
    }

    /// Append a pending job to the local list.
    pub fn push(
        self: *Job,
        tail: **Job,
        handler: *const fn (task: *anyopaque, job: *Job) void,
    ) void {
        std.debug.assert(self.state() == .pending);
        self.handler = handler;
        tail.*.next_or_state = @ptrCast(self);
        self.prev_or_null = @ptrCast(tail.*);
        self.next_or_state = null;
        tail.* = self;
        // Local publication only; the pool mutex publishes shared work.
        self.state_flag.store(.queued_local, .monotonic);
    }

    /// Append an already-detached job to a shared list.
    pub fn pushShared(self: *Job, tail: **Job) void {
        self.prev_or_null = @ptrCast(tail.*);
        self.next_or_state = null;
        tail.*.next_or_state = @ptrCast(self);
        tail.* = self;
        self.state_flag.store(.queued_shared, .release);
    }

    /// Remove the tail job. The caller must have verified that `self` is the
    /// current tail.
    pub fn pop(self: *Job, tail: **Job) void {
        std.debug.assert(self.state() == .queued_local);
        std.debug.assert(tail.* == self);
        const prev: *Job = @ptrCast(@alignCast(self.prev_or_null.?));
        prev.next_or_state = null;
        tail.* = prev;
        self.reset();
    }

    /// Remove a queued job from a local or shared list.
    pub fn remove(self: *Job, tail: **Job) void {
        const prev: *Job = @ptrCast(@alignCast(self.prev_or_null.?));
        const next: ?*Job = if (self.next_or_state) |raw|
            @ptrCast(@alignCast(raw))
        else
            null;

        prev.next_or_state = if (next) |n| @ptrCast(n) else null;
        if (next) |n| {
            n.prev_or_null = @ptrCast(prev);
        } else {
            tail.* = prev;
        }
        self.reset();
    }

    /// Remove the head job from a shared list, including when it is the only
    /// element. The job stays `queued_shared` until an execute state is set.
    pub fn popHead(sentinel: *Job, tail: **Job) ?*Job {
        const raw = sentinel.next_or_state orelse return null;
        const job: *Job = @ptrCast(@alignCast(raw));
        std.debug.assert(job.state() == .queued_shared);

        const next: ?*Job = if (job.next_or_state) |p|
            @ptrCast(@alignCast(p))
        else
            null;

        sentinel.next_or_state = if (next) |n| @ptrCast(n) else null;
        if (next) |n| {
            n.prev_or_null = @ptrCast(sentinel);
        } else {
            tail.* = sentinel;
        }

        job.prev_or_null = null;
        job.next_or_state = undefined;
        return job;
    }

    /// Detach the head job from a local list. The tail is retained because the
    /// sentinel cannot repair the caller's tail pointer. The returned job is
    /// still `queued_local` and must be moved with `pushShared`.
    pub fn shift(self: *Job) ?*Job {
        const raw = self.next_or_state orelse return null;
        const job: *Job = @ptrCast(@alignCast(raw));
        std.debug.assert(job.state() == .queued_local);

        const next_raw = job.next_or_state orelse return null;
        const next: *Job = @ptrCast(@alignCast(next_raw));

        next.prev_or_null = @ptrCast(self);
        self.next_or_state = @ptrCast(next);
        job.prev_or_null = null;
        job.next_or_state = undefined;
        return job;
    }

    fn reset(self: *Job) void {
        self.handler = null;
        self.prev_or_null = undefined;
        self.next_or_state = undefined;
        self.state_flag.store(.pending, .monotonic);
    }
};

fn noop(_: *anyopaque, _: *Job) void {}

fn count(head: *const Job) usize {
    var n: usize = 0;
    var raw = head.next_or_state;
    while (raw) |p| {
        const job: *Job = @ptrCast(@alignCast(p));
        n += 1;
        raw = job.next_or_state;
    }
    return n;
}

test "job list: push, shift, and remove preserve order" {
    var head = Job.head();
    var tail: *Job = &head;

    var a = Job.pending();
    var b = Job.pending();
    var c = Job.pending();

    a.push(&tail, noop);
    b.push(&tail, noop);
    c.push(&tail, noop);

    try std.testing.expectEqual(@as(usize, 3), count(&head));

    const first = head.shift().?;
    try std.testing.expectEqual(@as(*Job, &a), first);
    try std.testing.expectEqual(JobState.queued_local, first.state());

    const second = head.shift().?;
    try std.testing.expectEqual(@as(*Job, &b), second);

    // Only the tail remains; shift must refuse to detach it.
    try std.testing.expectEqual(@as(?*Job, null), head.shift());
    try std.testing.expectEqual(@as(*Job, &c), tail);

    c.remove(&tail);
    try std.testing.expectEqual(@as(usize, 0), count(&head));
    try std.testing.expect(head.isTail());
}

test "job list: shared list supports single-element pop" {
    var local_head = Job.head();
    var local_tail: *Job = &local_head;

    var a = Job.pending();
    var b = Job.pending();
    a.push(&local_tail, noop);
    b.push(&local_tail, noop);

    var shared_head = Job.head();
    var shared_tail: *Job = &shared_head;

    // `shift` always retains the local tail, so the first job is detached.
    const detached = local_head.shift().?;
    try std.testing.expectEqual(@as(*Job, &a), detached);
    detached.pushShared(&shared_tail);
    try std.testing.expectEqual(JobState.queued_shared, detached.state());

    const popped = Job.popHead(&shared_head, &shared_tail).?;
    try std.testing.expectEqual(@as(*Job, detached), popped);
    try std.testing.expect(shared_head.isTail());

    var state = ExecuteState{ .io = std.testing.io };
    popped.setExecuteState(&state);
    try std.testing.expectEqual(JobState.executing, popped.state());
    try std.testing.expectEqual(@as(*ExecuteState, &state), popped.getExecuteState());
}

test "job list: remove middle node repairs tail" {
    var head = Job.head();
    var tail: *Job = &head;

    var a = Job.pending();
    var b = Job.pending();
    var c = Job.pending();
    a.push(&tail, noop);
    b.push(&tail, noop);
    c.push(&tail, noop);

    b.remove(&tail);
    try std.testing.expectEqual(@as(usize, 2), count(&head));

    c.remove(&tail);
    try std.testing.expectEqual(@as(*Job, &a), tail);

    a.remove(&tail);
    try std.testing.expect(head.isTail());
}
