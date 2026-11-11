//! Heartbeat/fork-join scheduler core.
//!
//! Scheduling model (derived from judofyr/spice, 0BSD):
//! - each worker owns a truly local intrusive job list (no atomics on push);
//! - `fork` only appends to that list;
//! - `tick` occasionally hands one queued job to an idle worker;
//! - `join` returns null when nobody picked the job up, and the caller runs it;
//! - user code is never executed while the pool mutex is held.
//!
//! A dedicated heartbeat thread marks active lanes periodically. `tick`
//! checks the flag at each `Task.call`; only a flagged owner shares local
//! work. Flat calls use explicit `kickstart` to offer their chunks immediately.

const std = @import("std");
const builtin = @import("builtin");
const affinity = @import("affinity.zig");
const job_mod = @import("job.zig");
const Job = job_mod.Job;
const ExecuteState = job_mod.ExecuteState;
const ReadyOwners = @import("scheduler/ready_owners.zig").ReadyOwners;

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

pub fn Options(comptime Ctx: type) type {
    return struct {
        pub const Context = Ctx;

        /// Number of background workers. 0 selects allowed CPU count - 1;
        /// pinning uses one allowed logical CPU per physical core.
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
        /// Optional owner round robin improves fairness between concurrent
        /// callers. Default bitmap priority preserves registered-index order.
        fair_shared_owners: bool = false,
        /// Heartbeat period. A worker only offers queued work to idle lanes
        /// once per period, which keeps tiny fork/join trees at serial cost.
        /// 10us is short enough to fill lanes on medium trees while still
        /// leaving microsecond-scale trees untouched.
        heartbeat_interval_ns: i96 = 10 * std.time.ns_per_us,
        /// Heartbeat period while every background worker is idle. This keeps
        /// a held caller from waking 100k times per second while background
        /// workers idle. Default idle cycles skip locks and worker writes;
        /// optional parking stops the timer when there is no heartbeat demand.
        idle_heartbeat_interval_ns: i96 = 20 * std.time.ns_per_us,
        /// Keep periodic pacing through short gaps in a burst of calls before
        /// parking. This avoids a heartbeat wake-up on every small flat call.
        idle_heartbeat_grace_ns: i96 = 10 * std.time.ns_per_ms,
        /// Opt-in complete idle parking. Saves periodic wake-ups, but cold
        /// first-call latency can increase. Default periodic pacing preserves
        /// the measured latency contract while skipping idle metadata work.
        park_idle_heartbeat: bool = false,
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

// ---------------------------------------------------------------------------
// Pool
// ---------------------------------------------------------------------------

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
        heartbeat_ready: std.Io.Condition = .init,
        /// Protected by mutex, as are caller_busy and Worker.active.
        active_callers: usize = 0,
        has_callers: std.atomic.Value(bool) = .init(false),
        caller_epoch: usize = 0,
        heartbeat_parked: bool = false,
        heartbeat_demand: std.atomic.Value(bool) = .init(false),
        workers_ready: std.Io.Semaphore = .{},
        idle_workers: std.atomic.Value(usize) = .init(0),
        is_stopping: std.atomic.Value(bool) = .init(false),
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
        ready_owners: ReadyOwners,

        pub fn init(
            allocator: std.mem.Allocator,
            io: std.Io,
            options: OptionsType,
        ) !Self {
            if (comptime Ctx != void) {
                if (options.context_init == null) return error.MissingContextInit;
            }

            const pinned_cpus: []u32 = if (options.pin_workers)
                try affinity.pinnedCpuList(allocator, io)
            else
                &.{};
            errdefer allocator.free(pinned_cpus);
            const cpu_count = if (!builtin.single_threaded and pinned_cpus.len != 0)
                pinned_cpus.len
            else
                affinity.effectiveCpuCount();
            const requested = if (options.workers == 0)
                cpu_count -| 1
            else
                options.workers;
            const pin_cap = if (pinned_cpus.len != 0) pinned_cpus.len else std.math.maxInt(usize);
            const background_count = @min(@min(requested, options.max_workers), pin_cap);
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
            var ready_owners = try ReadyOwners.init(allocator, background_count + caller_count);
            errdefer ready_owners.deinit();

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
                .pinned_cpus = pinned_cpus,
                .execute_states = execute_states,
                .execute_free = if (execute_states.len != 0) 0 else null,
                .ready_owners = ready_owners,
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
                w.local_tail = &w.job_head;
                w.shared_head = Job.head();
                w.shared_tail = &w.shared_head;
            }
            for (self.caller_storage, 0..) |*w, i| {
                w.pool = self;
                w.index = self.background_count + i;
                w.active = false;
                w.caller_slot = i;
                w.job_head = Job.head();
                w.local_tail = &w.job_head;
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
                self.is_stopping.store(true, .release);
                self.job_ready.broadcast(self.io);
                self.heartbeat_ready.broadcast(self.io);
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
            self.ready_owners.deinit();
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
            return self.claimCallerKind(true);
        }

        /// Flat loops kickstart their lanes directly. A callback that starts
        /// recursive work via Worker.begin() requests heartbeat pacing then.
        pub fn claimFlatCaller(self: *Self) ?*Worker(Ctx) {
            return self.claimCallerKind(false);
        }

        fn claimCallerKind(self: *Self, wants_heartbeat: bool) ?*Worker(Ctx) {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            for (self.caller_storage, 0..) |*w, i| {
                if (!self.caller_busy[i]) {
                    self.caller_busy[i] = true;
                    self.active_callers += 1;
                    if (self.active_callers == 1) self.has_callers.store(true, .release);
                    self.caller_epoch +%= 1;
                    if (wants_heartbeat and self.options.park_idle_heartbeat and self.options.enable_heartbeat and self.spawned_background != 0) {
                        self.heartbeat_demand.store(true, .monotonic);
                        if (self.heartbeat_parked) self.heartbeat_ready.signal(self.io);
                    }
                    w.active = true;
                    w.job_head = Job.head();
                    w.local_tail = &w.job_head;
                    w.shared_head = Job.head();
                    w.shared_tail = &w.shared_head;
                    w.heartbeat.store(false, .monotonic);
                    return w;
                }
            }
            return null;
        }

        fn requestHeartbeat(self: *Self) void {
            if (!self.options.park_idle_heartbeat or !self.options.enable_heartbeat or self.spawned_background == 0) return;
            if (self.heartbeat_demand.load(.monotonic)) return;
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            self.heartbeat_demand.store(true, .monotonic);
            if (self.heartbeat_parked) self.heartbeat_ready.signal(self.io);
        }

        pub fn releaseCaller(self: *Self, w: *Worker(Ctx)) void {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            std.debug.assert(w.job_head.isTail());
            std.debug.assert(w.shared_head.isTail());
            std.debug.assert(!self.ready_owners.contains(w.index));
            if (w.caller_slot) |slot| {
                if (self.caller_busy[slot]) {
                    std.debug.assert(self.active_callers > 0);
                    self.active_callers -= 1;
                    if (self.active_callers == 0) self.has_callers.store(false, .release);
                    self.caller_busy[slot] = false;
                }
            }
            w.active = false;
            w.heartbeat.store(false, .monotonic);
            w.job_head = Job.head();
            w.local_tail = &w.job_head;
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

            if (self.is_stopping.load(.monotonic) or !owner.active) return;
            if (@atomicLoad(?*anyopaque, &owner.shared_head.next_or_null, .acquire) != null) return;

            var shared: usize = 0;
            while (shared < max) {
                const job = owner.job_head.shift() orelse break;
                job.pushShared(&owner.shared_tail);
                shared += 1;
            }
            if (shared != 0) self.ready_owners.push(owner.index);

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
            if (owner.shared_head.isTail()) self.ready_owners.remove(owner.index);
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
            if (self.ready_owners.head != null and self.idle_workers.load(.monotonic) != 0)
                self.job_ready.signal(self.io);
        }

        /// Pick one shared job. Called with the pool mutex held.
        fn popReadyJob(self: *Self) ?*Job {
            const index = (if (self.options.fair_shared_owners)
                self.ready_owners.head
            else
                self.ready_owners.firstPriority()) orelse return null;
            const state = self.acquireExecuteStateLocked() orelse return null;
            if (self.options.fair_shared_owners) self.ready_owners.remove(index);
            const w = self.workers[index];
            std.debug.assert(w.active);
            const job = Job.popHead(&w.shared_head, &w.shared_tail).?;
            if (self.options.fair_shared_owners) {
                if (!w.shared_head.isTail()) self.ready_owners.push(index);
            } else if (w.shared_head.isTail()) self.ready_owners.remove(index);
            job.setExecuteState(state);
            return job;
        }

        /// Explicitly offer queued work to idle lanes. Flat parallel loops use
        /// this to fill workers immediately instead of waiting for a
        /// heartbeat.
        pub fn kickstart(self: *Self, owner: *Worker(Ctx), max: usize) void {
            self.shareMany(owner, max);
        }

        fn applyNumaPolicy(self: *Self) void {
            if (comptime builtin.os.tag != .linux) return;
            const node: u16 = self.options.numa_node orelse
                (if (self.options.auto_numa) affinity.currentNumaNode() orelse return else return);
            affinity.applyNumaPreferred(node);
        }

        fn pinWorker(self: *Self, index: usize) void {
            if (!self.options.pin_workers) return;
            if (self.pinned_cpus.len == 0) return;
            affinity.pinCurrentThread(self.pinned_cpus[index]);
        }

        /// Periodically mark every active worker as ready to share one batch
        /// of local work. Small fork/join trees finish before the first
        /// heartbeat, so they never pay thread-wakeup cost.
        fn heartbeatWorker(self: *Self) void {
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
                // Preserve periodic pacing, but don't lock the pool or write
                // registered idle workers when no caller or job is active.
                if (!self.options.park_idle_heartbeat and
                    !self.has_callers.load(.acquire) and
                    self.idle_workers.load(.monotonic) >= self.spawned_background)
                {
                    interval = self.options.idle_heartbeat_interval_ns;
                    continue;
                }
                self.mutex.lockUncancelable(self.io);
                if (self.options.park_idle_heartbeat) {
                    if (observed_epoch != self.caller_epoch) {
                        observed_epoch = self.caller_epoch;
                        idle_since = null;
                    }
                    while (!self.is_stopping.load(.monotonic)) {
                        if (self.heartbeat_demand.load(.monotonic)) {
                            if (self.active_callers != 0 or self.idle_workers.load(.monotonic) < self.spawned_background) {
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
                        observed_epoch = self.caller_epoch;
                    }
                }
                if (self.is_stopping.load(.monotonic)) {
                    self.mutex.unlock(self.io);
                    return;
                }
                for (self.workers[0..self.worker_count]) |w| {
                    if (w.active) w.heartbeat.store(true, .monotonic);
                }
                const idle = self.idle_workers.load(.monotonic);
                interval = if (idle >= self.spawned_background)
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
                if (self.is_stopping.load(.monotonic)) break;
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

// ---------------------------------------------------------------------------
// Worker
// ---------------------------------------------------------------------------

pub fn Worker(comptime Ctx: type) type {
    return struct {
        const Self = @This();

        pool: *Pool(Ctx),
        /// Registered lane index. Serial flat fallbacks use pool.worker_count.
        index: usize = 0,
        active: bool = false,
        caller_slot: ?usize = null,
        ctx: Ctx = undefined,
        job_head: Job = Job.head(),
        /// Owner-only tail, shared by every nested task on this lane.
        local_tail: *Job = undefined,
        shared_head: Job = Job.head(),
        shared_tail: *Job = undefined,
        heartbeat: std.atomic.Value(bool) = .init(false),

        pub fn context(self: *Self) *Ctx {
            return &self.ctx;
        }

        pub fn begin(self: *Self) Task(Ctx) {
            if (self.active) self.pool.requestHeartbeat();
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

// ---------------------------------------------------------------------------
// Future
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Context helpers
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

var test_context_live = std.atomic.Value(u32).init(0);

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
            try std.testing.expectEqual(@as(usize, 2), pool.active_callers);
            try Wait.flag(first);
            try Wait.flag(second);
            try Wait.parked(&pool, false);
            pool.releaseCaller(first);
            try std.testing.expectEqual(@as(usize, 1), pool.active_callers);
            second.heartbeat.store(false, .monotonic);
            try Wait.flag(second);
            var task = second.begin();
            var future: Future(void, u64, u64) = undefined;
            future.initFork(&task, Wait.leaf, 19);
            try std.testing.expectEqual(@as(u64, 19), future.joinOrCall(&task, Wait.leaf));
            pool.releaseCaller(second);
            try std.testing.expectEqual(@as(usize, 0), pool.active_callers);
        }
        try Wait.parked(&pool, true);
        // The deferred deinit must wake a heartbeat blocked on its condition.
    }
}

test "zero worker caller accounting preserves serial fallback" {
    var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
        .max_workers = 0,
        .max_callers = 1,
    });
    defer pool.deinit();
    try pool.start();
    try std.testing.expect(pool.heartbeat_thread == null);
    for (0..10) |_| {
        const caller = pool.claimCaller().?;
        try std.testing.expectEqual(@as(usize, 1), pool.active_callers);
        try std.testing.expect(pool.has_callers.load(.acquire));
        try std.testing.expect(pool.claimCaller() == null);
        pool.releaseCaller(caller);
        try std.testing.expectEqual(@as(usize, 0), pool.active_callers);
        try std.testing.expect(!pool.has_callers.load(.acquire));
    }
}

test "default heartbeat skips idle worker writes and resumes periodic flags for callers" {
    if (builtin.single_threaded) return error.SkipZigTest;
    var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 1,
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
            try std.testing.expectEqual(@as(u64, 8386560), try @import("parallel.zig").parallelFoldInfallible(caller, u64, {}, 4096, .{
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

test "shared ready owners rotate fairly and state exhaustion preserves reclamation" {
    const Run = struct {
        fn leaf(_: *Task(void), value: u64) u64 {
            return value;
        }
    };
    const F = Future(void, u64, u64);
    for ([_]usize{ 0, 1 }) |states| {
        var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
            .max_workers = 0,
            .max_callers = 3,
            .max_execute_states = states,
            .enable_heartbeat = false,
            .fair_shared_owners = true,
        });
        defer pool.deinit();
        try pool.start();
        var callers: [3]*Worker(void) = undefined;
        var tasks: [3]Task(void) = undefined;
        var futures: [3][3]F = undefined;
        for (&callers, &tasks, &futures, 0..) |*caller, *task, *slots, owner| {
            caller.* = pool.claimCaller().?;
            task.* = caller.*.begin();
            for (slots, 0..) |*f, index| f.initFork(task, Run.leaf, owner * 10 + index);
            pool.kickstart(caller.*, 3);
        }
        if (states != 0) {
            for (0..6) |step| {
                const owner = step % callers.len;
                const offset = step / callers.len;
                pool.mutex.lockUncancelable(pool.io);
                const job = pool.popReadyJob().?;
                pool.mutex.unlock(pool.io);
                try std.testing.expectEqual(&futures[owner][offset].job, job);
                callers[owner].executeJob(job);
                try std.testing.expectEqual(@as(u64, owner * 10 + offset), futures[owner][offset].joinOrCall(&tasks[owner], Run.leaf));
            }
        } else {
            pool.mutex.lockUncancelable(pool.io);
            const empty = pool.popReadyJob() == null;
            pool.mutex.unlock(pool.io);
            try std.testing.expect(empty);
            // Reclaim the middle owner first; both list links must survive.
            for (futures[1][0..2], 0..) |*f, i| try std.testing.expectEqual(@as(u64, 10 + i), f.joinOrCall(&tasks[1], Run.leaf));
            try std.testing.expect(!pool.ready_owners.contains(callers[1].index));
            try std.testing.expectEqual(callers[0].index, pool.ready_owners.head.?);
            try std.testing.expectEqual(callers[2].index, pool.ready_owners.tail.?);
            for ([_]usize{ 0, 2 }) |owner| for (futures[owner][0..2], 0..) |*f, i| {
                try std.testing.expectEqual(@as(u64, owner * 10 + i), f.joinOrCall(&tasks[owner], Run.leaf));
            };
        }
        try std.testing.expect(pool.ready_owners.head == null);
        for (callers, &tasks, &futures, 0..) |caller, *task, *slots, owner| {
            try std.testing.expectEqual(@as(u64, owner * 10 + 2), slots[2].joinOrCall(task, Run.leaf));
            pool.releaseCaller(caller);
        }
    }
}

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
    try std.testing.expectEqual(@as(usize, if (builtin.single_threaded) 0 else @min(2, pool.pinned_cpus.len)), pool.spawned_background);
    try std.testing.expect(pool.pinned_cpus.len > 0);
}

test "affinity: pinned worker counts fit selected CPUs before startup" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var automatic = try Pool(void).init(std.testing.allocator, std.testing.io, .{ .pin_workers = true });
    defer automatic.deinit();
    try std.testing.expect(automatic.pinned_cpus.len > 0);
    try std.testing.expect(automatic.background_count < automatic.pinned_cpus.len);
    var explicit = try Pool(void).init(std.testing.allocator, std.testing.io, .{
        .workers = 128,
        .max_workers = 128,
        .pin_workers = true,
    });
    defer explicit.deinit();
    try std.testing.expect(explicit.background_count <= explicit.pinned_cpus.len);
    for (explicit.pinned_cpus, 0..) |cpu, index| {
        for (explicit.pinned_cpus[0..index]) |previous| try std.testing.expect(cpu != previous);
    }
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
    try std.testing.expectEqual(@as(usize, if (builtin.single_threaded) 0 else 1), pool.spawned_background);
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
    try std.testing.expectEqual(@as(usize, if (builtin.single_threaded) 0 else 1), pool.spawned_background);
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
