//! Owner-local fork/join protocol: Worker, Task and caller-stack Future.
//!
//! Pool lifecycle and heartbeat pacing live in scheduler/. Keeping the hot
//! lane/task/future types together preserves the direct callback protocol.

const std = @import("std");
const builtin = @import("builtin");
const job_mod = @import("job.zig");
const Job = job_mod.Job;

pub const Options = @import("scheduler/pool_options.zig").Options;
pub const Pool = @import("scheduler/pool.zig").Pool;

/// Worker heartbeat state. `pacing` encodes an enabled adaptive policy while
/// no share was requested, so the hot tick path needs only one atomic load.
pub const heartbeat_idle: u8 = 0;
pub const heartbeat_pacing: u8 = 1;
pub const heartbeat_share: u8 = 2;

pub fn Worker(comptime Ctx: type) type {
    return struct {
        const Self = @This();

        pool: *Pool(Ctx),
        /// Registered lane index. Serial flat fallbacks use pool.worker_count.
        index: usize = 0,
        /// Atomic so the heartbeat can publish flags without the pool mutex.
        /// Mutex-protected readers still see the same value.
        active: std.atomic.Value(bool) = .init(false),
        caller_slot: ?usize = null,
        ctx: Ctx = undefined,
        job_head: Job = Job.head(),
        /// Owner-only tail, shared by every nested task on this lane.
        local_tail: *Job = undefined,
        shared_head: Job = Job.head(),
        shared_tail: *Job = undefined,
        heartbeat: std.atomic.Value(u8) = .init(heartbeat_idle),
        /// Per-lane copy of the pool pacing policy. Keeps the hot tick path
        /// from touching shared pool state when adaptive pacing is disabled.
        pacing_enabled: bool = false,

        pub fn context(self: *Self) *Ctx {
            return &self.ctx;
        }

        pub fn begin(self: *Self) Task(Ctx) {
            if (self.active.load(.monotonic)) self.pool.requestHeartbeat();
            return self.beginFlat();
        }

        /// Internal flat dispatch entry; recursive callbacks use begin().
        pub fn beginFlat(self: *Self) Task(Ctx) {
            if (self.job_head.isTail()) self.local_tail = &self.job_head;
            return .{ .worker = self };
        }

        /// Cheap hot-path check. Only a heartbeat or an explicit kickstart
        /// lets work leave the local list, so tiny workloads stay serial.
        pub inline fn tick(self: *Self) void {
            // Keep the disabled/no-flag path identical to the original tick:
            // one atomic load and return. Adaptive pacing and sharing live in
            // an out-of-line slow path so tiny callbacks do not pay for them.
            const state = self.heartbeat.load(.monotonic);
            if (state == heartbeat_idle) return;
            self.tickSlow(state);
        }

        noinline fn tickSlow(self: *Self, state: u8) void {
            if (state == heartbeat_pacing) {
                // Request pacing only when this lane actually has local work
                // to offer; tiny serial kernels stay quiet.
                if (!self.job_head.isTail() and !self.pool.heartbeat_demand.load(.monotonic))
                    self.pool.requestPacing();
                return;
            }
            self.heartbeat.store(if (self.pacing_enabled) heartbeat_pacing else heartbeat_idle, .monotonic);
            self.maybeShare();
        }

        fn maybeShare(self: *Self) void {
            if (@atomicLoad(?*anyopaque, &self.shared_head.next_or_null, .acquire) != null) return;
            if (self.job_head.isTail()) return;
            const idle = self.pool.idle_workers.load(.monotonic);
            if (idle == 0) return;
            self.pool.shareMany(self, @min(idle, self.pool.options.share_batch));
        }

        /// Internal background-job entry; pool mutex must be unlocked.
        pub fn executeJob(self: *Self, job: *Job) void {
            var task = self.beginFlat();
            job.handler.?(@ptrCast(&task), job);
        }
    };
}

// ---------------------------------------------------------------------------
// Task
// ---------------------------------------------------------------------------

pub fn Task(comptime Ctx: type) type {
    return struct {
        const Self = @This();

        worker: *Worker(Ctx),

        pub inline fn tick(self: *Self) void {
            self.worker.tick();
        }

        pub inline fn call(
            self: *Self,
            comptime R: type,
            comptime func: anytype,
            arg: anytype,
        ) R {
            return callWithContext(Ctx, self.worker, R, func, arg);
        }
    };
}

fn callWithContext(
    comptime Ctx: type,
    worker: *Worker(Ctx),
    comptime R: type,
    comptime func: anytype,
    arg: anytype,
) R {
    var task = Task(Ctx){ .worker = worker };
    task.tick();
    // Error-union returns are passed indirectly by LLVM when forced inline,
    // which costs more than the register-passing win. Let the optimizer decide
    // for those and keep the forced-inline fast path for plain values.
    if (comptime @typeInfo(R) == .error_union) {
        return func(&task, arg);
    }
    return @call(.always_inline, func, .{ &task, arg });
}

/// A single-use fork/join slot. `fork` requires pending storage initialized
/// with `.{}`; `initFork` initializes unused storage directly. Join leaves the
/// job unlinked without resetting it. Keep its address stable while queued.
pub fn Future(comptime Ctx: type, comptime Input: type, comptime Output: type) type {
    return struct {
        const Self = @This();

        const payload_size = @max(@sizeOf(Input), @sizeOf(Output));
        const payload_align = @max(@alignOf(Input), @alignOf(Output));
        job: Job = Job.pending(),
        /// Input and output never live at the same time: the input is consumed
        /// before a background handler writes the output, and local execution
        /// overwrites the input only after copying it.
        payload: [payload_size]u8 align(payload_align) = undefined,

        pub inline fn getInput(self: *const Self) Input {
            var input: Input = undefined;
            @memcpy(std.mem.asBytes(&input), self.payload[0..@sizeOf(Input)]);
            return input;
        }

        pub inline fn setInput(self: *Self, input: Input) void {
            @memcpy(self.payload[0..@sizeOf(Input)], std.mem.asBytes(&input));
        }

        pub inline fn getOutput(self: *const Self) Output {
            var output: Output = undefined;
            @memcpy(std.mem.asBytes(&output), self.payload[0..@sizeOf(Output)]);
            return output;
        }

        pub inline fn setOutput(self: *Self, output: Output) void {
            @memcpy(self.payload[0..@sizeOf(Output)], std.mem.asBytes(&output));
        }

        pub inline fn fork(
            self: *Self,
            task: *Task(Ctx),
            comptime func: anytype,
            input: Input,
        ) void {
            self.setInput(input);
            const Handler = struct {
                fn run(raw_task: *anyopaque, job: *Job) void {
                    const t: *Task(Ctx) = @ptrCast(@alignCast(raw_task));
                    const fut: *Self = @alignCast(@fieldParentPtr("job", job));
                    fut.setOutput(t.call(Output, func, fut.getInput()));
                    const state = job.getExecuteState();
                    state.done.set(state.io);
                }
            };
            self.job.push(&task.worker.local_tail, Handler.run);
        }

        /// Initialize caller-owned storage and append the job directly. The
        /// storage may be undefined, but must not contain an outstanding job.
        /// Keep its address stable until join; never copy an enqueued Future.
        pub inline fn initFork(
            self: *Self,
            task: *Task(Ctx),
            comptime func: anytype,
            input: Input,
        ) void {
            self.job.handler = null;
            self.fork(task, func, input);
        }

        /// Wait for a forked job. Returns null when nobody picked the job up,
        /// which means the caller must execute it.
        pub inline fn join(self: *Self, task: *Task(Ctx)) ?Output {
            if (self.tryJoin(task)) return self.getOutput();
            return null;
        }

        /// Non-copying join: returns true when another lane executed the job
        /// and `result()` is valid. This avoids materializing `?Output`, which
        /// is expensive for large or error-union payloads.
        pub inline fn tryJoin(self: *Self, task: *Task(Ctx)) bool {
            // Sharing retains the owner's current local tail. Every nested
            // task uses that same tail, so matching it proves the job is local.
            // No other lane can read or mutate this job's links yet.
            if (task.worker.local_tail == &self.job) {
                self.job.popWithPrev(
                    &task.worker.local_tail,
                    @ptrCast(@alignCast(self.job.prev_or_null.?)),
                );
                return false;
            }
            // Non-tail jobs may already be shared. Check the handler before
            // examining an uninitialized pending link.
            if (self.job.handler != null) {
                const prev = @atomicLoad(?*anyopaque, &self.job.prev_or_null, .acquire);
                if (prev) |raw| {
                    if (@intFromPtr(raw) & 1 == 0) {
                        self.job.remove(&task.worker.local_tail);
                        return false;
                    }
                }
            }
            switch (self.job.state()) {
                .pending => return false,
                .queued_local => {
                    // The tail was handled above. Only this owner changes
                    // local_tail, so no callback or wait can change it here.
                    self.job.remove(&task.worker.local_tail);
                    return false;
                },
                .queued_shared => {
                    if (task.worker.pool.reclaimShared(task.worker, &self.job)) {
                        return false;
                    }
                    return self.joinExecuting(task);
                },
                .executing => return self.joinExecuting(task),
            }
        }

        pub inline fn result(self: *const Self) Output {
            return self.getOutput();
        }

        fn joinExecuting(self: *Self, task: *Task(Ctx)) bool {
            const worker = task.worker;
            const pool = worker.pool;
            const state = self.job.getExecuteState();
            if (pool.waitForJob(worker, &self.job)) {
                pool.releaseExecuteState(state);
                return true;
            }
            return false;
        }

        /// Join, or execute locally when nobody picked the job up.
        pub inline fn joinOrCall(
            self: *Self,
            task: *Task(Ctx),
            comptime func: anytype,
        ) Output {
            if (self.tryJoin(task)) return self.getOutput();
            return task.call(Output, func, self.getInput());
        }
    };
}

test "future: nested begin preserves outstanding local work on registered and temporary lanes" {
    const F = Future(void, usize, usize);
    const Run = struct {
        fn leaf(_: *Task(void), input: usize) usize {
            return input * 3 + 1;
        }
    };
    for (0..5) |workers| {
        var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .max_execute_states = 16,
        });
        defer pool.deinit();
        try pool.start();
        const caller = pool.claimCaller().?;
        defer pool.releaseCaller(caller);
        var temporary = Worker(void){ .pool = &pool, .ctx = {} };
        for ([_]*Worker(void){ caller, &temporary }) |owner| {
            for (0..10) |index| {
                var task = owner.begin();
                var parent: F = undefined;
                parent.initFork(&task, Run.leaf, index * 17 + 3);
                var nested = owner.begin();
                var child: F = undefined;
                child.initFork(&nested, Run.leaf, index * 7 + 1);
                const child_value = child.joinOrCall(&nested, Run.leaf);
                const parent_value = parent.joinOrCall(&task, Run.leaf);
                try std.testing.expectEqual((index * 7 + 1) * 3 + 1, child_value);
                try std.testing.expectEqual((index * 17 + 3) * 3 + 1, parent_value);
                try std.testing.expect(owner.job_head.isTail());
                try std.testing.expectEqual(&owner.job_head, owner.local_tail);
            }
        }
    }
}

test "future: fork/join tree sum with caller fallback" {
    const io = std.testing.io;
    var pool = try Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 2,
        .max_execute_states = 64,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    const Node = struct {
        value: i64,
        left: ?*const @This() = null,
        right: ?*const @This() = null,
    };

    var leaf1 = Node{ .value = 1 };
    var leaf2 = Node{ .value = 2 };
    var leaf3 = Node{ .value = 3 };
    var leaf4 = Node{ .value = 4 };
    var left = Node{ .value = 5, .left = &leaf1, .right = &leaf2 };
    var right = Node{ .value = 6, .left = &leaf3, .right = &leaf4 };
    var root = Node{ .value = 7, .left = &left, .right = &right };

    const worker = pool.claimCaller() orelse return error.NoCallerSlot;
    defer pool.releaseCaller(worker);
    var task = worker.begin();

    const sumFn = struct {
        fn sum(t: *Task(void), node: *const Node) anyerror!i64 {
            var result = node.value;
            if (node.left) |l| {
                if (node.right) |r| {
                    var fut = Future(void, *const Node, anyerror!i64){};
                    fut.fork(t, sum, r);
                    result += try t.call(anyerror!i64, sum, l);
                    const joined = fut.join(t);
                    const other = if (joined) |value|
                        try value
                    else
                        try t.call(anyerror!i64, sum, r);
                    result += other;
                    return result;
                }
                result += try t.call(anyerror!i64, sum, l);
            }
            if (node.right) |r| {
                result += try t.call(anyerror!i64, sum, r);
            }
            return result;
        }
    }.sum;

    const total = try task.call(anyerror!i64, sumFn, &root);
    try std.testing.expectEqual(@as(i64, 28), total);
}

test "future: pending and error-union joins preserve caller fallback across lanes" {
    const F = Future(void, u64, anyerror!u64);
    const Exec = struct {
        fn run(_: *Task(void), index: u64) anyerror!u64 {
            if (index == 3) return error.ExpectedFailure;
            return index * 7 + 1;
        }
    };
    for (0..5) |workers| {
        var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .max_execute_states = 32,
        });
        defer pool.deinit();
        try pool.start();
        const caller = pool.claimCaller().?;
        defer pool.releaseCaller(caller);
        for (0..10) |_| {
            var task = caller.begin();
            var pending = F{};
            try std.testing.expect(!pending.tryJoin(&task));
            try std.testing.expect(pending.join(&task) == null);
            var plain_pending = Future(void, u64, u64){};
            try std.testing.expect(!plain_pending.tryJoin(&task));

            var futures: [8]F = undefined;
            for (&futures, 0..) |*future, index| {
                future.* = .{};
                future.fork(&task, Exec.run, @intCast(index));
            }
            pool.kickstart(caller, futures.len);
            for (&futures, 0..) |*future, index| {
                const result = future.joinOrCall(&task, Exec.run);
                if (index == 3) {
                    try std.testing.expectError(error.ExpectedFailure, result);
                } else {
                    try std.testing.expectEqual(@as(u64, index * 7 + 1), try result);
                }
            }
        }
    }
}

test "Future shares input and output storage" {
    const F = Future(void, usize, usize);
    try std.testing.expect(@sizeOf(F) <= @sizeOf(Job) + @sizeOf(usize));
}

test "future: initFork accepts undefined storage and reuses joined slots" {
    const Packet = struct { value: u64 align(64), bytes: [23]u8 };
    const Result = error{ExpectedFailure}!Packet;
    const Exec = struct {
        fn run(_: *Task(void), input: *const Packet) Result {
            if (input.value % 4 == 3) return error.ExpectedFailure;
            var output = input.*;
            output.value *%= 7;
            for (&output.bytes) |*byte| byte.* ^= 0x5a;
            return output;
        }
        fn empty(_: *Task(void), _: void) void {}
    };
    const F = Future(void, *const Packet, Result);
    for (0..5) |workers| {
        for ([_]usize{ 0, 16 }) |states| {
            var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
                .workers = workers,
                .max_workers = workers,
                .max_callers = 1,
                .max_execute_states = states,
                .enable_heartbeat = false,
            });
            defer pool.deinit();
            try pool.start();
            const caller = pool.claimCaller().?;
            defer pool.releaseCaller(caller);
            var futures: [8]F = undefined;
            var packets: [8]Packet = undefined;
            for (0..10) |round| {
                var task = caller.begin();
                for (&futures, &packets, 0..) |*future, *packet, index| {
                    packet.* = .{ .value = round + index, .bytes = @splat(@as(u8, @intCast(round + index))) };
                    future.initFork(&task, Exec.run, packet);
                    try std.testing.expectEqual(packet, future.getInput());
                }
                pool.kickstart(caller, futures.len);
                for (&futures, &packets) |*future, *packet| {
                    const result = future.joinOrCall(&task, Exec.run);
                    if (packet.value % 4 == 3) {
                        try std.testing.expectError(error.ExpectedFailure, result);
                    } else {
                        const output = try result;
                        try std.testing.expectEqual(packet.value * 7, output.value);
                        for (output.bytes, packet.bytes) |actual, input| {
                            try std.testing.expectEqual(input ^ 0x5a, actual);
                        }
                    }
                }
                var empty: Future(void, void, void) = undefined;
                empty.initFork(&task, Exec.empty, {});
                empty.joinOrCall(&task, Exec.empty);
                try std.testing.expect(caller.job_head.isTail());
                try std.testing.expectEqual(&caller.job_head, caller.local_tail);
            }
        }
    }
}

test "future: reclaimed parent fallback publishes descendant forks" {
    const Descendants = struct {
        fn leaf(_: *Task(void), _: void) anyerror!bool {
            return true;
        }
        fn run(task: *Task(void), _: void) anyerror!bool {
            var first = Future(void, void, anyerror!bool){};
            var second = Future(void, void, anyerror!bool){};
            first.fork(task, leaf, {});
            second.fork(task, leaf, {});
            task.worker.pool.kickstart(task.worker, 1);
            const offered = first.job.state() != .queued_local;
            _ = try first.joinOrCall(task, leaf);
            _ = try second.joinOrCall(task, leaf);
            return offered;
        }
    };
    const Nested = struct {
        fn leaf(_: *Task(void), _: void) void {}
        fn run(task: *Task(void), _: void) void {
            var retained = Future(void, void, void){};
            retained.fork(task, leaf, {});
            task.worker.pool.kickstart(task.worker, 1);
            retained.joinOrCall(task, leaf);
        }
    };
    for (0..5) |workers| {
        for ([_]usize{ 0, 16 }) |states| {
            var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
                .workers = workers,
                .max_workers = workers,
                .max_callers = 1,
                .max_execute_states = states,
                .enable_heartbeat = false,
            });
            defer pool.deinit();
            try pool.start();
            const caller = pool.claimCaller().?;
            defer pool.releaseCaller(caller);
            for (0..10) |_| {
                var task = caller.begin();
                var parent = Future(void, void, anyerror!bool){};
                parent.fork(&task, Descendants.run, {});
                task.call(void, Nested.run, {});
                if (workers == 0 or states == 0 or builtin.single_threaded)
                    try std.testing.expectEqual(job_mod.JobState.queued_shared, parent.job.state());
                try std.testing.expect(try parent.joinOrCall(&task, Descendants.run));
                try std.testing.expect(caller.job_head.isTail());
                try std.testing.expectEqual(&caller.job_head, caller.local_tail);
            }
        }
    }
}

test "future: tryJoin/result and joinOrCall with a large payload" {
    const io = std.testing.io;
    var pool = try Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 2,
        .max_execute_states = 64,
        .worker_stack_size = 1 * 1024 * 1024,
    });
    defer pool.deinit();
    try pool.start();

    const Big = struct {
        a: u64,
        b: u64,
        c: u64,
        d: u64,
    };
    const produce = struct {
        fn run(_: *Task(void), value: u64) Big {
            return .{ .a = value, .b = value + 1, .c = value + 2, .d = value + 3 };
        }
    }.run;

    const caller = pool.claimCaller() orelse return error.NoCallerSlot;
    defer pool.releaseCaller(caller);
    var task = caller.begin();

    var first = Future(void, u64, Big){};
    first.fork(&task, produce, 42);
    if (first.tryJoin(&task)) {
        const value = first.result();
        try std.testing.expectEqual(@as(u64, 42), value.a);
        try std.testing.expectEqual(@as(u64, 45), value.d);
    } else {
        const value = task.call(Big, produce, 42);
        try std.testing.expectEqual(@as(u64, 42), value.a);
        try std.testing.expectEqual(@as(u64, 45), value.d);
    }

    var second = Future(void, u64, Big){};
    second.fork(&task, produce, 7);
    const value = second.joinOrCall(&task, produce);
    try std.testing.expectEqual(@as(u64, 7), value.a);
    try std.testing.expectEqual(@as(u64, 10), value.d);
}

test {
    _ = @import("scheduler/pool_options.zig");
    _ = @import("scheduler/pool.zig");
    _ = @import("scheduler/context.zig");
    _ = @import("scheduler/heartbeat.zig");
}
