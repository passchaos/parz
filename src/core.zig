//! Heartbeat/fork-join scheduler core.
//!
//! Scheduling model (derived from judofyr/spice, 0BSD):
//! - each worker owns a truly local intrusive job list (no atomics on push);
//! - `fork` only appends to that list;
//! - `tick` occasionally hands one queued job to an idle worker;
//! - `join` returns null when nobody picked the job up, and the caller runs it;
//! - user code is never executed while the pool mutex is held.
//!
//! This first slice uses eager tick-driven sharing instead of a dedicated
//! heartbeat thread. A busy worker calls `tick` at every `Task.call` and at
//! every flat-parallel chunk boundary, which is enough to fill idle workers
//! without a timer thread. A dedicated heartbeat mode can be added later
//! without changing the public API.

const std = @import("std");
const builtin = @import("builtin");
const job_mod = @import("job.zig");
const Job = job_mod.Job;
const ExecuteState = job_mod.ExecuteState;

pub fn Options(comptime Ctx: type) type {
    return struct {
        pub const Context = Ctx;

        /// Number of background workers. 0 selects affinity-aware CPU count - 1.
        workers: usize = 0,
        /// Upper bound on background workers.
        max_workers: usize = 64,
        /// Fixed number of caller slots. At least one is always reserved.
        max_callers: usize = 8,
        /// Virtual stack size for background workers.
        worker_stack_size: usize = 2 * 1024 * 1024,
        /// Upper bound on out-of-line execution states. When exhausted, work
        /// stays local and the caller executes it.
        max_execute_states: usize = 1024,
        /// Heartbeat period. A worker only offers queued work to idle lanes
        /// once per period, which keeps tiny fork/join trees at serial cost.
        /// 10us is short enough to fill lanes on medium trees while still
        /// leaving microsecond-scale trees untouched.
        heartbeat_interval_ns: i96 = 10 * std.time.ns_per_us,
        /// Heartbeat period while every background worker is idle. This keeps
        /// an idle pool from waking 100k times per second; the first work
        /// arriving through a caller slot sets its heartbeat flag immediately.
        idle_heartbeat_interval_ns: i96 = 20 * std.time.ns_per_us,
        /// Start a dedicated heartbeat thread. Without it, `tick` never
        /// shares work and only eager `kickstart` paths (flat loops) run in
        /// parallel.
        enable_heartbeat: bool = true,
        /// Pin each background worker to a distinct allowed CPU. Linux only;
        /// a no-op elsewhere. The caller thread is not pinned.
        pin_workers: bool = false,
        /// Prefer allocations on this NUMA node for background workers
        /// (Linux MPOL_PREFERRED). The caller thread is not affected.
        numa_node: ?u16 = null,
        /// When `numa_node` is null, use the node of the CPU the worker is
        /// currently running on (Linux getcpu). Best combined with
        /// `pin_workers = true`.
        auto_numa: bool = false,
        /// Optional per-worker context constructor.
        context_init: ?*const fn (allocator: std.mem.Allocator, index: usize) anyerror!Ctx = null,
        /// Optional per-worker context destructor.
        context_deinit: ?*const fn (allocator: std.mem.Allocator, ctx: *Ctx) void = null,
    };
}

pub fn Pool(comptime Ctx: type) type {
    return struct {
        const Self = @This();

        pub const Context = Ctx;
        pub const OptionsType = Options(Ctx);
        pub const WorkerType = Worker(Ctx);
        pub const TaskType = Task(Ctx);
        pub const FutureType = Future;

        allocator: std.mem.Allocator,
        io: std.Io,
        options: OptionsType,

        mutex: std.Io.Mutex = .init,
        job_ready: std.Io.Condition = .init,
        workers_ready: std.Io.Semaphore = .{},
        idle_workers: std.atomic.Value(usize) = .init(0),
        is_stopping: bool = false,
        started: bool = false,

        background_storage: []Worker(Ctx),
        caller_storage: []Worker(Ctx),
        background_threads: []std.Thread,
        heartbeat_thread: ?std.Thread = null,
        workers: []*Worker(Ctx),
        worker_count: usize = 0,
        background_count: usize = 0,
        spawned_background: usize = 0,
        caller_count: usize = 0,
        caller_busy: []bool,
        pinned_cpus: []u32 = &.{},

        execute_states: []ExecuteState,
        execute_free: ?usize = null,

        pub fn init(
            allocator: std.mem.Allocator,
            io: std.Io,
            options: OptionsType,
        ) !Self {
            if (comptime Ctx != void) {
                if (options.context_init == null) return error.MissingContextInit;
            }

            const requested = if (options.workers == 0)
                effectiveCpuCount() -| 1
            else
                options.workers;
            const background_count = @min(requested, options.max_workers);
            const caller_count = @max(options.max_callers, 1);

            const background_storage = try allocator.alloc(Worker(Ctx), background_count);
            errdefer allocator.free(background_storage);
            const caller_storage = try allocator.alloc(Worker(Ctx), caller_count);
            errdefer allocator.free(caller_storage);
            const background_threads = try allocator.alloc(std.Thread, background_count);
            errdefer allocator.free(background_threads);
            const workers = try allocator.alloc(*Worker(Ctx), background_count + caller_count);
            errdefer allocator.free(workers);
            const caller_busy = try allocator.alloc(bool, caller_count);
            errdefer allocator.free(caller_busy);
            const execute_states = try allocator.alloc(ExecuteState, options.max_execute_states);
            errdefer allocator.free(execute_states);

            var bg_initialized: usize = 0;
            var caller_initialized: usize = 0;
            errdefer {
                for (background_storage[0..bg_initialized]) |*w| {
                    deinitContext(&w.ctx, allocator, options);
                }
                for (caller_storage[0..caller_initialized]) |*w| {
                    deinitContext(&w.ctx, allocator, options);
                }
            }

            for (background_storage, 0..) |*w, i| {
                w.* = .{
                    .pool = undefined,
                    .index = i,
                    .active = true,
                    .ctx = try initContext(options, allocator, i),
                };
                bg_initialized += 1;
            }
            for (caller_storage, 0..) |*w, i| {
                w.* = .{
                    .pool = undefined,
                    .index = background_count + i,
                    .active = false,
                    .caller_slot = i,
                    .ctx = try initContext(options, allocator, background_count + i),
                };
                caller_initialized += 1;
            }
            @memset(caller_busy, false);

            for (execute_states, 0..) |*state, i| {
                state.* = .{ .io = io, .index = i };
                state.next_free = if (i + 1 < execute_states.len) i + 1 else null;
            }

            return .{
                .allocator = allocator,
                .io = io,
                .options = options,
                .background_storage = background_storage,
                .caller_storage = caller_storage,
                .background_threads = background_threads,
                .workers = workers,
                .background_count = background_count,
                .caller_count = caller_count,
                .caller_busy = caller_busy,
                .execute_states = execute_states,
                .execute_free = if (execute_states.len != 0) 0 else null,
            };
        }

        /// Spawn background workers. The pool must not move after this call.
        pub fn start(self: *Self) !void {
            if (self.started) return error.AlreadyStarted;
            self.started = true;

            for (self.background_storage, 0..) |*w, i| {
                w.pool = self;
                w.index = i;
                w.active = true;
                w.job_head = Job.head();
                w.shared_head = Job.head();
                w.shared_tail = &w.shared_head;
            }
            for (self.caller_storage, 0..) |*w, i| {
                w.pool = self;
                w.index = self.background_count + i;
                w.active = false;
                w.caller_slot = i;
                w.job_head = Job.head();
                w.shared_head = Job.head();
                w.shared_tail = &w.shared_head;
            }

            var n: usize = 0;
            for (self.background_storage) |*w| {
                self.workers[n] = w;
                n += 1;
            }
            for (self.caller_storage) |*w| {
                self.workers[n] = w;
                n += 1;
            }
            self.worker_count = n;
            if (self.options.pin_workers) {
                self.pinned_cpus = try buildPinnedCpuList(self.allocator, self.io);
            }

            var spawned: usize = 0;
            if (!builtin.single_threaded) {
                while (spawned < self.background_count) : (spawned += 1) {
                    self.background_threads[spawned] = std.Thread.spawn(
                        .{ .stack_size = self.options.worker_stack_size },
                        backgroundWorker,
                        .{ self, &self.background_storage[spawned] },
                    ) catch break;
                }
            }
            self.spawned_background = spawned;
            for (self.background_storage[spawned..]) |*w| w.active = false;

            var ready: usize = 0;
            while (ready < spawned) : (ready += 1) {
                self.workers_ready.waitUncancelable(self.io);
            }

            if (self.options.enable_heartbeat and spawned != 0 and !builtin.single_threaded) {
                self.heartbeat_thread = std.Thread.spawn(
                    .{ .stack_size = 256 * 1024 },
                    heartbeatWorker,
                    .{self},
                ) catch null;
            }
        }

        pub fn deinit(self: *Self) void {
            if (self.started) {
                self.mutex.lockUncancelable(self.io);
                self.is_stopping = true;
                self.job_ready.broadcast(self.io);
                self.mutex.unlock(self.io);

                for (self.background_threads[0..self.spawned_background]) |thread| {
                    thread.join();
                }
                if (self.heartbeat_thread) |thread| thread.join();
            }

            for (self.background_storage) |*w| {
                deinitContext(&w.ctx, self.allocator, self.options);
            }
            for (self.caller_storage) |*w| {
                deinitContext(&w.ctx, self.allocator, self.options);
            }

            if (self.background_storage.len != 0) self.allocator.free(self.background_storage);
            if (self.caller_storage.len != 0) self.allocator.free(self.caller_storage);
            if (self.background_threads.len != 0) self.allocator.free(self.background_threads);
            if (self.workers.len != 0) self.allocator.free(self.workers);
            if (self.caller_busy.len != 0) self.allocator.free(self.caller_busy);
            if (self.pinned_cpus.len != 0) self.allocator.free(self.pinned_cpus);
            if (self.execute_states.len != 0) self.allocator.free(self.execute_states);
            self.* = undefined;
        }

        /// Number of lanes a flat parallel call may use: background workers
        /// plus the caller.
        pub fn parallelWorkerCount(self: *const Self) usize {
            return self.spawned_background + 1;
        }

        /// Claim a caller slot. The returned worker is already registered in
        /// the pool's worker list, so its queued jobs can be shared.
        pub fn claimCaller(self: *Self) ?*Worker(Ctx) {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            for (self.caller_storage, 0..) |*w, i| {
                if (!self.caller_busy[i]) {
                    self.caller_busy[i] = true;
                    w.active = true;
                    w.job_head = Job.head();
                    w.shared_head = Job.head();
                    w.shared_tail = &w.shared_head;
                    w.heartbeat.store(false, .monotonic);
                    return w;
                }
            }
            return null;
        }

        pub fn releaseCaller(self: *Self, w: *Worker(Ctx)) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            if (w.caller_slot) |slot| self.caller_busy[slot] = false;
            w.active = false;
            w.heartbeat.store(false, .monotonic);
            w.job_head = Job.head();
            w.shared_head = Job.head();
            w.shared_tail = &w.shared_head;
        }

        /// Context for a caller that could not claim a slot. The caller runs
        /// serially with this temporary worker.
        pub fn createTempContext(self: *Self) !Ctx {
            return initContext(self.options, self.allocator, self.worker_count);
        }

        pub fn destroyTempContext(self: *Self, ctx: *Ctx) void {
            deinitContext(ctx, self.allocator, self.options);
        }

        /// Move up to `max` local jobs to the owner's shared list. The owner
        /// keeps its local tail, so a worker always retains one job to run
        /// even when every idle worker picks up shared work.
        fn shareMany(self: *Self, owner: *Worker(Ctx), max: usize) void {
            if (max == 0) return;

            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            if (self.is_stopping) return;
            if (@atomicLoad(?*anyopaque, &owner.shared_head.next_or_null, .acquire) != null) return;

            var shared: usize = 0;
            while (shared < max) {
                const job = owner.job_head.shift() orelse break;
                job.pushShared(&owner.shared_tail);
                shared += 1;
            }

            var i: usize = 0;
            while (i < shared) : (i += 1) {
                self.job_ready.signal(self.io);
            }
        }

        /// Reclaim a job that is still queued in the owner's shared list.
        /// Returns false when an idle worker already picked it up.
        fn reclaimShared(self: *Self, owner: *Worker(Ctx), job: *Job) bool {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            if (job.state() != .queued_shared) return false;
            job.remove(&owner.shared_tail);
            return true;
        }

        fn waitForJob(self: *Self, worker: *Worker(Ctx), job: *Job) bool {
            _ = worker;
            const state = job.getExecuteState();
            state.done.waitUncancelable(self.io);
            return true;
        }

        fn releaseExecuteState(self: *Self, state: *ExecuteState) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            self.releaseExecuteStateLocked(state);
        }

        fn acquireExecuteStateLocked(self: *Self) ?*ExecuteState {
            const index = self.execute_free orelse return null;
            const state = &self.execute_states[index];
            self.execute_free = state.next_free;
            state.next_free = null;
            state.io = self.io;
            state.done = .unset;
            return state;
        }

        fn releaseExecuteStateLocked(self: *Self, state: *ExecuteState) void {
            state.done = .unset;
            state.next_free = self.execute_free;
            self.execute_free = state.index;
        }

        /// Pick one shared job. Called with the pool mutex held.
        fn popReadyJob(self: *Self) ?*Job {
            for (self.workers[0..self.worker_count]) |w| {
                if (!w.active) continue;
                if (@atomicLoad(?*anyopaque, &w.shared_head.next_or_null, .acquire) == null) continue;

                const state = self.acquireExecuteStateLocked() orelse continue;
                const job = Job.popHead(&w.shared_head, &w.shared_tail).?;
                job.setExecuteState(state);
                return job;
            }
            return null;
        }

        /// Explicitly offer queued work to idle lanes. Flat parallel loops use
        /// this to fill workers immediately instead of waiting for a
        /// heartbeat.
        pub fn kickstart(self: *Self, owner: *Worker(Ctx), max: usize) void {
            self.shareMany(owner, max);
        }

        fn currentNumaNode() ?u16 {
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

        fn applyNumaPolicy(self: *Self) void {
            if (comptime builtin.os.tag != .linux) return;
            const node: u16 = self.options.numa_node orelse
                (if (self.options.auto_numa) currentNumaNode() orelse return else return);
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

        fn pinWorker(self: *Self, index: usize) void {
            if (!self.options.pin_workers) return;
            if (comptime builtin.os.tag != .linux) return;
            if (self.pinned_cpus.len == 0) return;

            const cpu = self.pinned_cpus[index % self.pinned_cpus.len];
            const word = cpu / @bitSizeOf(usize);
            const bit = cpu % @bitSizeOf(usize);
            var set = std.mem.zeroes(std.os.linux.cpu_set_t);
            set[word] = @as(usize, 1) << @intCast(bit);
            std.os.linux.sched_setaffinity(0, &set) catch {};
        }

        /// Periodically mark every active worker as ready to share one batch
        /// of local work. Small fork/join trees finish before the first
        /// heartbeat, so they never pay thread-wakeup cost.
        fn heartbeatWorker(self: *Self) void {
            var interval = self.options.heartbeat_interval_ns;
            while (true) {
                self.io.sleep(
                    std.Io.Duration.fromNanoseconds(@max(interval, 1)),
                    .awake,
                ) catch |err| switch (err) {
                    error.Canceled => return,
                };

                self.mutex.lockUncancelable(self.io);
                if (self.is_stopping) {
                    self.mutex.unlock(self.io);
                    return;
                }
                for (self.workers[0..self.worker_count]) |w| {
                    if (!w.active) continue;
                    w.heartbeat.store(true, .monotonic);
                }
                const idle = self.idle_workers.load(.monotonic);
                interval = if (self.background_count > 0 and idle >= self.background_count)
                    self.options.idle_heartbeat_interval_ns
                else
                    self.options.heartbeat_interval_ns;
                self.mutex.unlock(self.io);
            }
        }

        fn backgroundWorker(self: *Self, w: *Worker(Ctx)) void {
            self.pinWorker(w.index);
            self.applyNumaPolicy();
            self.workers_ready.post(self.io);
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            while (true) {
                if (self.is_stopping) break;
                if (self.popReadyJob()) |job| {
                    self.mutex.unlock(self.io);
                    w.executeJob(job);
                    self.mutex.lockUncancelable(self.io);
                    continue;
                }

                _ = self.idle_workers.fetchAdd(1, .monotonic);
                self.job_ready.waitUncancelable(self.io, &self.mutex);
                _ = self.idle_workers.fetchSub(1, .monotonic);
            }
        }
    };
}

pub fn Worker(comptime Ctx: type) type {
    return struct {
        const Self = @This();

        pool: *Pool(Ctx),
        index: usize = 0,
        active: bool = false,
        caller_slot: ?usize = null,
        ctx: Ctx = undefined,
        job_head: Job = Job.head(),
        shared_head: Job = Job.head(),
        shared_tail: *Job = undefined,
        heartbeat: std.atomic.Value(bool) = .init(false),

        pub fn context(self: *Self) *Ctx {
            return &self.ctx;
        }

        pub fn begin(self: *Self) Task(Ctx) {
            return .{ .worker = self, .job_tail = &self.job_head };
        }

        /// Cheap hot-path check. Only a heartbeat or an explicit kickstart
        /// lets work leave the local list, so tiny workloads stay serial.
        pub inline fn tick(self: *Self) void {
            // Inactive workers never have `heartbeat` set (the heartbeat
            // thread skips them and releaseCaller clears the flag), so the
            // atomic load is sufficient here.
            if (!self.heartbeat.load(.monotonic)) return;
            self.heartbeat.store(false, .monotonic);
            self.maybeShare();
        }

        fn maybeShare(self: *Self) void {
            if (@atomicLoad(?*anyopaque, &self.shared_head.next_or_null, .acquire) != null) return;
            if (self.job_head.isTail()) return;
            const idle = self.pool.idle_workers.load(.monotonic);
            if (idle == 0) return;
            self.pool.shareMany(self, @min(idle, 4));
        }

        fn executeJob(self: *Self, job: *Job) void {
            var task = self.begin();
            job.handler.?(@ptrCast(&task), job);
        }
    };
}

pub fn Task(comptime Ctx: type) type {
    return struct {
        const Self = @This();

        worker: *Worker(Ctx),
        job_tail: *Job,

        pub inline fn tick(self: *Self) void {
            self.worker.tick();
        }

        pub inline fn call(
            self: *Self,
            comptime R: type,
            comptime func: anytype,
            arg: anytype,
        ) R {
            return callWithContext(Ctx, self.worker, self.job_tail, R, func, arg);
        }
    };
}

fn callWithContext(
    comptime Ctx: type,
    worker: *Worker(Ctx),
    job_tail: *Job,
    comptime R: type,
    comptime func: anytype,
    arg: anytype,
) R {
    var task = Task(Ctx){ .worker = worker, .job_tail = job_tail };
    task.tick();
    // Error-union returns are passed indirectly by LLVM when forced inline,
    // which costs more than the register-passing win. Let the optimizer decide
    // for those and keep the forced-inline fast path for plain values.
    if (comptime @typeInfo(R) == .error_union) {
        return func(&task, arg);
    }
    return @call(.always_inline, func, .{ &task, arg });
}

/// A single-use fork/join slot. Reinitialize with `.{}` before forking again;
/// `join`/`tryJoin` leave the embedded job unlinked without resetting it so the
/// common local join path stays branch-light.
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
            self.job.push(&task.job_tail, Handler.run);
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
            // Fast path for a local job: the previous pointer is untagged.
            // Shared jobs tag it, and pending jobs have a null handler, so
            // both fall through to the full state decode.
            if (self.job.handler != null) {
                const prev = @atomicLoad(?*anyopaque, &self.job.prev_or_null, .acquire);
                if (prev) |raw| {
                    if (@intFromPtr(raw) & 1 == 0) {
                        if (task.job_tail == &self.job) {
                            self.job.pop(&task.job_tail);
                        } else {
                            self.job.remove(&task.job_tail);
                        }
                        return false;
                    }
                }
            }
            switch (self.job.state()) {
                .pending => return false,
                .queued_local => {
                    // The forked job is normally the local tail: deeper jobs
                    // have already been joined. Keep the common case off the
                    // doubly-linked remove path.
                    if (task.job_tail == &self.job) {
                        self.job.pop(&task.job_tail);
                    } else {
                        self.job.remove(&task.job_tail);
                    }
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
            const maybe = self.join(task) orelse
                return task.call(Output, func, self.getInput());
            return maybe;
        }
    };
}

fn initContext(options: anytype, allocator: std.mem.Allocator, index: usize) !@TypeOf(options).Context {
    const Ctx = @TypeOf(options).Context;
    if (comptime Ctx == void) return {};
    const init = options.context_init orelse return error.MissingContextInit;
    return init(allocator, index);
}

fn deinitContext(ctx: anytype, allocator: std.mem.Allocator, options: anytype) void {
    const Ctx = @TypeOf(options).Context;
    if (comptime Ctx == void) return;
    if (options.context_deinit) |deinit| deinit(allocator, ctx);
}

/// Build a CPU list with one logical CPU per physical core (best effort).
/// On Linux, read the SMT sibling list from sysfs; fall back to the allowed
/// affinity set when sysfs is unavailable.
fn buildPinnedCpuList(allocator: std.mem.Allocator, io: std.Io) ![]u32 {
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

        var tokens = std.mem.tokenizeAny(u8, content, "-,\n ");
        const first = tokens.next() orelse {
            try selected.append(allocator, cpu);
            continue;
        };
        const first_cpu = std.fmt.parseInt(u32, first, 10) catch {
            try selected.append(allocator, cpu);
            continue;
        };
        if (first_cpu == cpu) try selected.append(allocator, cpu);
    }

    if (selected.items.len == 0) return try allowed.toOwnedSlice(allocator);
    return try selected.toOwnedSlice(allocator);
}

fn effectiveCpuCount() usize {
    if (builtin.single_threaded) return 1;
    if (builtin.os.tag == .linux) {
        const affinity = std.posix.sched_getaffinity(0) catch
            return std.Thread.getCpuCount() catch 1;
        return @max(@as(usize, 1), std.posix.CPU_COUNT(affinity));
    }
    return std.Thread.getCpuCount() catch 1;
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

test "pool: start and stop without workers" {
    const io = std.testing.io;
    var pool = try Pool(void).init(std.testing.allocator, io, .{
        .workers = 0,
        .max_workers = 0,
        .max_callers = 2,
        .max_execute_states = 16,
    });
    defer pool.deinit();
    try pool.start();
    try std.testing.expectEqual(@as(usize, 0), pool.spawned_background);
    try std.testing.expectEqual(@as(usize, 1), pool.parallelWorkerCount());
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

test "pool pins workers when requested" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const io = std.testing.io;
    var pool = try Pool(void).init(std.testing.allocator, io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 1,
        .max_execute_states = 8,
        .pin_workers = true,
    });
    defer pool.deinit();
    try pool.start();
    try std.testing.expectEqual(@as(usize, 2), pool.spawned_background);
    try std.testing.expect(pool.pinned_cpus.len > 0);
}

test "pool applies a preferred numa node" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const io = std.testing.io;
    var pool = try Pool(void).init(std.testing.allocator, io, .{
        .workers = 1,
        .max_workers = 1,
        .max_callers = 1,
        .max_execute_states = 8,
        .numa_node = 0,
    });
    defer pool.deinit();
    try pool.start();
    try std.testing.expectEqual(@as(usize, 1), pool.spawned_background);
}

test "pool applies automatic numa policy" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const io = std.testing.io;
    var pool = try Pool(void).init(std.testing.allocator, io, .{
        .workers = 1,
        .max_workers = 1,
        .max_callers = 1,
        .max_execute_states = 8,
        .pin_workers = true,
        .auto_numa = true,
    });
    defer pool.deinit();
    try pool.start();
    try std.testing.expectEqual(@as(usize, 1), pool.spawned_background);
}

test "Future shares input and output storage" {
    const F = Future(void, usize, usize);
    try std.testing.expect(@sizeOf(F) <= @sizeOf(Job) + @sizeOf(usize));
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
