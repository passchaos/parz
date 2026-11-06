//! Intrusive, branch-reduced job list used by the scheduler.
//!
//! The list layout is derived from judofyr/spice (0BSD, Copyright (c) 2024
//! Magnus Holm). The job is embedded in the caller's stack frame, so `fork`
//! does not allocate. A sentinel head keeps `push` branch-free.
//!
//! The job state is encoded in pointer tags instead of a separate atomic flag:
//! - `prev_or_null` low bit: queued_shared.
//! - `next_or_null` low bit: executing (the rest is *ExecuteState).
//! Both pointers are naturally aligned, so the low bit is free on every target
//! (including wasm). `state()` reads the handler and the two pointers with
//! acquire loads; the transitions publish them with release stores under the
//! pool mutex, so a reader never observes a half-updated execute state.

const std = @import("std");

pub const JobState = enum(u8) {
    pending,
    queued_local,
    queued_shared,
    executing,
};

pub const Handler = *const fn (task: *anyopaque, job: *Job) void;

const tag_bit: usize = 1;

/// Out-of-line state for a job that has been handed to another worker.
pub const ExecuteState = struct {
    io: std.Io,
    done: std.Io.Event = .unset,
    next_free: ?usize = null,
    index: usize = 0,
};

pub const Job = struct {
    handler: ?Handler,
    /// Queued: previous job, low bit set when the job is in a shared list.
    /// Executing: the shared link is retained. Pending: undefined.
    prev_or_null: ?*anyopaque,
    /// Queued: next job. Executing: *ExecuteState with the low bit set.
    /// Pending: undefined.
    next_or_null: ?*anyopaque,

    pub fn head() Job {
        return .{
            .handler = null,
            .prev_or_null = null,
            .next_or_null = null,
        };
    }

    pub fn pending() Job {
        return .{
            .handler = null,
            .prev_or_null = undefined,
            .next_or_null = undefined,
        };
    }

    pub inline fn state(self: *const Job) JobState {
        if (self.handler == null) return .pending;
        const next = @atomicLoad(?*anyopaque, &self.next_or_null, .acquire);
        if (next) |raw| {
            if (@intFromPtr(raw) & tag_bit != 0) return .executing;
        }
        const prev = @atomicLoad(?*anyopaque, &self.prev_or_null, .acquire) orelse
            return .executing;
        return if (@intFromPtr(prev) & tag_bit == 0) .queued_local else .queued_shared;
    }

    pub inline fn isTail(self: *const Job) bool {
        return self.next_or_null == null;
    }

    pub fn getExecuteState(self: *Job) *ExecuteState {
        std.debug.assert(self.state() == .executing);
        const raw = self.next_or_null.?;
        return @ptrFromInt(@intFromPtr(raw) & ~tag_bit);
    }

    pub fn setExecuteState(self: *Job, execute_state: *ExecuteState) void {
        std.debug.assert(self.state() == .queued_shared);
        // Publish the execute state and the executing tag in one store.
        @atomicStore(
            ?*anyopaque,
            &self.next_or_null,
            @ptrFromInt(@intFromPtr(execute_state) | tag_bit),
            .release,
        );
    }

    /// Append a pending job to the local list.
    pub fn push(self: *Job, tail: **Job, handler: Handler) void {
        std.debug.assert(self.state() == .pending);
        self.handler = handler;
        tail.*.next_or_null = @ptrCast(self);
        self.prev_or_null = @ptrCast(tail.*);
        self.next_or_null = null;
        tail.* = self;
    }

    /// Append an already-detached job to a shared list.
    pub fn pushShared(self: *Job, tail: **Job) void {
        self.next_or_null = null;
        @atomicStore(?*anyopaque, &tail.*.next_or_null, @ptrCast(self), .release);
        // The release store publishes the handler, the next link, and the
        // shared tag on the previous pointer.
        @atomicStore(
            ?*anyopaque,
            &self.prev_or_null,
            @ptrFromInt(@intFromPtr(tail.*) | tag_bit),
            .release,
        );
        tail.* = self;
    }

    /// Remove the tail job. The caller must have verified that `self` is the
    /// current tail. The job is left unlinked but not reset: `Future` is
    /// single-use and is reinitialized before it is forked again.
    pub fn pop(self: *Job, tail: **Job) void {
        const prev: *Job = @ptrFromInt(@intFromPtr(self.prev_or_null.?) & ~tag_bit);
        self.popWithPrev(tail, prev);
    }

    /// Unlink a local tail using the previous pointer supplied by the caller.
    /// Local links cannot change on another lane.
    pub inline fn popWithPrev(self: *Job, tail: **Job, prev: *Job) void {
        std.debug.assert(self.state() == .queued_local);
        std.debug.assert(tail.* == self);
        std.debug.assert(self.prev_or_null == @as(?*anyopaque, @ptrCast(prev)));
        prev.next_or_null = null;
        tail.* = prev;
    }

    /// Remove a queued job from a local or shared list. The job is left
    /// unlinked but not reset; see `pop`.
    pub fn remove(self: *Job, tail: **Job) void {
        const raw_prev = self.prev_or_null.?;
        const shared_tag = @intFromPtr(raw_prev) & tag_bit;
        const prev: *Job = @ptrFromInt(@intFromPtr(raw_prev) & ~tag_bit);
        const next: ?*Job = if (self.next_or_null) |raw|
            @ptrFromInt(@intFromPtr(raw) & ~tag_bit)
        else
            null;

        @atomicStore(
            ?*anyopaque,
            &prev.next_or_null,
            if (next) |n| @as(?*anyopaque, @ptrCast(n)) else null,
            .release,
        );
        if (next) |n| {
            @atomicStore(
                ?*anyopaque,
                &n.prev_or_null,
                @ptrFromInt(@intFromPtr(prev) | shared_tag),
                .release,
            );
        } else {
            tail.* = prev;
        }
    }

    /// Remove the head job from a shared list, including when it is the only
    /// element. The job stays `queued_shared` until an execute state is set.
    pub fn popHead(sentinel: *Job, tail: **Job) ?*Job {
        const raw = @atomicLoad(?*anyopaque, &sentinel.next_or_null, .acquire) orelse return null;
        const job: *Job = @ptrCast(@alignCast(raw));
        std.debug.assert(job.state() == .queued_shared);

        const next: ?*Job = if (job.next_or_null) |p|
            @ptrCast(@alignCast(p))
        else
            null;

        @atomicStore(
            ?*anyopaque,
            &sentinel.next_or_null,
            if (next) |n| @as(?*anyopaque, @ptrCast(n)) else null,
            .release,
        );
        if (next) |n| {
            @atomicStore(
                ?*anyopaque,
                &n.prev_or_null,
                @ptrFromInt(@intFromPtr(sentinel) | tag_bit),
                .release,
            );
        } else {
            tail.* = sentinel;
        }
        return job;
    }

    /// Detach the head job from a local list while retaining the owner's tail
    /// job to execute locally. The returned job is still `queued_local` and
    /// must be moved with `pushShared`.
    pub fn shift(self: *Job) ?*Job {
        const raw = self.next_or_null orelse return null;
        const job: *Job = @ptrCast(@alignCast(raw));
        std.debug.assert(job.state() == .queued_local);

        const next_raw = job.next_or_null orelse return null;
        const next: *Job = @ptrCast(@alignCast(next_raw));

        next.prev_or_null = @ptrCast(self);
        self.next_or_null = @ptrCast(next);
        return job;
    }
};

fn noop(_: *anyopaque, _: *Job) void {}

fn count(head: *const Job) usize {
    var n: usize = 0;
    var raw = head.next_or_null;
    while (raw) |p| {
        const job: *Job = @ptrCast(@alignCast(p));
        n += 1;
        raw = job.next_or_null;
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
