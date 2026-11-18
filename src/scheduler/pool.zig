//! Pool lifecycle, shared-job publication and bounded execution states.

const std = @import("std");
const builtin = @import("builtin");
const affinity = @import("../affinity.zig");
const job_mod = @import("../job.zig");
const Job = job_mod.Job;
const ExecuteState = job_mod.ExecuteState;
const ReadyOwners = @import("ready_owners.zig").ReadyOwners;
const Options = @import("pool_options.zig").Options;
const Worker = @import("../core.zig").Worker;
const Task = @import("../core.zig").Task;
const Future = @import("../core.zig").Future;
const heartbeat_idle = @import("../core.zig").heartbeat_idle;
const heartbeat_pacing = @import("../core.zig").heartbeat_pacing;
const initContext = @import("context.zig").initContext;
const deinitContext = @import("context.zig").deinitContext;
const Scratch = @import("../parallel/scratch.zig").Scratch;

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
        /// Caller slots are claimed and released with atomics, so a flat call
        /// in the default heartbeat mode never takes the pool mutex. Parking
        /// demand signaling still uses it.
        active_callers: std.atomic.Value(usize) = .init(0),
        has_callers: std.atomic.Value(bool) = .init(false),
        caller_epoch: std.atomic.Value(usize) = .init(0),
        /// True when adaptive pacing can actually wake the heartbeat. Kept as
        /// a plain field so the hot `tick` path skips atomic demand loads when
        /// pacing is disabled (no heartbeat, parking, or explicit periodic).
        pacing_enabled: bool = false,
        heartbeat_parked: bool = false,
        heartbeat_demand: std.atomic.Value(bool) = .init(false),
        /// Adaptive-heartbeat wake. Caller claims and recursive begins set it
        /// so the pacing thread can leave a backed-off idle wait immediately.
        heartbeat_tick: std.Io.Event = .unset,
        /// Last pacing interval used by the adaptive heartbeat, in
        /// nanoseconds. Diagnostic/test hook; zero until the first tick.
        heartbeat_period_ns: std.atomic.Value(u64) = .init(0),
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
        caller_busy: []std.atomic.Value(bool),
        pinned_cpus: []u32 = &.{},

        execute_states: []ExecuteState,
        execute_free: ?usize = null,
        /// Pool-owned dispatch scratch for high-chunk flat calls. Each object
        /// is exclusive while acquired; nested/concurrent calls fall back.
        dispatch_scratch_buffers: []align(64) u8,
        dispatch_scratch: []Scratch,
        /// Dedicated lock for the execute-state free list. Joins push states
        /// back without taking the pool mutex, so completion does not contend
        /// with sharing or ready-job pickup.
        execute_free_lock: std.atomic.Value(bool) = .init(false),
        ready_owners: ReadyOwners,
        execute_state_pressure: std.atomic.Value(bool) = .init(false),

        pub fn init(
            allocator: std.mem.Allocator,
            io: std.Io,
            options: OptionsType,
        ) !Self {
            if (comptime Ctx != void) {
                if (options.context_init == null) return error.MissingContextInit;
            }

            const pinned_cpus: []u32 = if (options.pin_workers)
                try affinity.pinnedCpuList(allocator, io, .{
                    .prefer_performance_cores = options.prefer_performance_cores,
                    .use_smt_siblings = options.use_smt_siblings,
                })
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
            const caller_busy = try allocator.alloc(std.atomic.Value(bool), caller_count);
            errdefer allocator.free(caller_busy);
            const execute_states = try allocator.alloc(ExecuteState, options.max_execute_states);
            errdefer allocator.free(execute_states);
            const dispatch_scratch_bytes = options.dispatch_scratch_count *| options.dispatch_scratch_bytes;
            const dispatch_scratch_buffers = try allocator.alignedAlloc(u8, .fromByteUnits(64), dispatch_scratch_bytes);
            errdefer allocator.free(dispatch_scratch_buffers);
            const dispatch_scratch = try allocator.alloc(Scratch, options.dispatch_scratch_count);
            errdefer allocator.free(dispatch_scratch);
            for (dispatch_scratch, 0..) |*scratch, index| {
                const offset = index * options.dispatch_scratch_bytes;
                scratch.* = Scratch.init(dispatch_scratch_buffers[offset..][0..options.dispatch_scratch_bytes]);
            }
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
                    .active = .init(true),
                    .ctx = try initContext(options, allocator, i),
                };
                bg_initialized += 1;
            }
            for (caller_storage, 0..) |*w, i| {
                w.* = .{
                    .pool = undefined,
                    .index = background_count + i,
                    .active = .init(false),
                    .caller_slot = i,
                    .ctx = try initContext(options, allocator, background_count + i),
                };
                caller_initialized += 1;
            }
            for (caller_busy) |*busy| busy.* = .init(false);

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
                .pacing_enabled = options.adaptive_heartbeat and options.enable_heartbeat and
                    !options.park_idle_heartbeat,
                .pinned_cpus = pinned_cpus,
                .execute_states = execute_states,
                .execute_free = if (execute_states.len != 0) 0 else null,
                .dispatch_scratch_buffers = dispatch_scratch_buffers,
                .dispatch_scratch = dispatch_scratch,
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
                w.active.store(true, .monotonic);
                w.pacing_enabled = self.pacing_enabled;
                w.heartbeat.store(if (self.pacing_enabled) heartbeat_pacing else heartbeat_idle, .monotonic);
                w.job_head = Job.head();
                w.local_tail = &w.job_head;
                w.shared_head = Job.head();
                w.shared_tail = &w.shared_head;
            }
            for (self.caller_storage, 0..) |*w, i| {
                w.pool = self;
                w.index = self.background_count + i;
                w.active.store(false, .monotonic);
                w.pacing_enabled = self.pacing_enabled;
                w.heartbeat.store(if (self.pacing_enabled) heartbeat_pacing else heartbeat_idle, .monotonic);
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
            for (self.background_storage[spawned..]) |*w| w.active.store(false, .monotonic);

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
                self.heartbeat_tick.set(self.io);
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
            if (self.dispatch_scratch_buffers.len != 0) self.allocator.free(self.dispatch_scratch_buffers);
            if (self.dispatch_scratch.len != 0) self.allocator.free(self.dispatch_scratch);
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
            for (self.caller_storage, 0..) |*w, i| {
                if (self.caller_busy[i].cmpxchgStrong(false, true, .acq_rel, .monotonic) != null) continue;
                const previous = self.active_callers.fetchAdd(1, .acq_rel);
                if (previous == 0) self.has_callers.store(true, .release);
                _ = self.caller_epoch.fetchAdd(1, .release);
                if (wants_heartbeat and self.options.park_idle_heartbeat and self.options.enable_heartbeat and self.spawned_background != 0) {
                    // Parking demand is the only claim path that needs the mutex.
                    self.mutex.lockUncancelable(self.io);
                    self.heartbeat_demand.store(true, .monotonic);
                    if (self.heartbeat_parked) self.heartbeat_ready.signal(self.io);
                    self.mutex.unlock(self.io);
                }
                w.active.store(true, .monotonic);
                w.pacing_enabled = self.pacing_enabled;
                w.job_head = Job.head();
                w.local_tail = &w.job_head;
                w.shared_head = Job.head();
                w.shared_tail = &w.shared_head;
                w.heartbeat.store(if (self.pacing_enabled) heartbeat_pacing else heartbeat_idle, .monotonic);
                return w;
            }
            return null;
        }

        /// Internal scheduler protocol; use Worker/Future for user work.
        pub fn requestHeartbeat(self: *Self) void {
            if (!self.options.park_idle_heartbeat or !self.options.enable_heartbeat or self.spawned_background == 0) return;
            if (self.heartbeat_demand.load(.monotonic)) return;
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            self.heartbeat_demand.store(true, .monotonic);
            if (self.heartbeat_parked) self.heartbeat_ready.signal(self.io);
        }

        /// Adaptive pacing demand. Called only when a lane actually has local
        /// jobs to offer, so tiny serial kernels do not wake the heartbeat.
        pub noinline fn requestPacing(self: *Self) void {
            if (!self.pacing_enabled or self.spawned_background == 0) return;
            self.heartbeat_demand.store(true, .monotonic);
            self.heartbeat_tick.set(self.io);
        }

        pub fn releaseCaller(self: *Self, w: *Worker(Ctx)) void {
            std.debug.assert(w.job_head.isTail());
            std.debug.assert(w.shared_head.isTail());
            // The membership check reads the mutex-protected ready-owner list.
            // Keep it in safety-checked builds only; release itself is lock-free.
            if (comptime builtin.mode == .Debug or builtin.mode == .ReleaseSafe) {
                self.mutex.lockUncancelable(self.io);
                std.debug.assert(!self.ready_owners.contains(w.index));
                self.mutex.unlock(self.io);
            }
            // Reset owner-local fields before publishing the slot as free; a
            // new claimant must never observe or overwrite this lane's state.
            w.active.store(false, .monotonic);
            w.heartbeat.store(if (self.pacing_enabled) heartbeat_pacing else heartbeat_idle, .monotonic);
            w.job_head = Job.head();
            w.local_tail = &w.job_head;
            w.shared_head = Job.head();
            w.shared_tail = &w.shared_head;
            if (w.caller_slot) |slot| {
                if (self.caller_busy[slot].swap(false, .acq_rel)) {
                    const previous = self.active_callers.fetchSub(1, .acq_rel);
                    std.debug.assert(previous > 0);
                    if (previous == 1) self.has_callers.store(false, .release);
                }
            }
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
        /// Internal scheduler protocol; use Worker/Future for user work.
        pub fn shareMany(self: *Self, owner: *Worker(Ctx), max: usize) void {
            if (max == 0) return;

            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            if (self.is_stopping.load(.monotonic) or !owner.active.load(.monotonic)) return;
            if (@atomicLoad(?*anyopaque, &owner.shared_head.next_or_null, .acquire) != null) return;

            var shared: usize = 0;
            while (shared < max) {
                const job = owner.job_head.shift() orelse break;
                job.pushShared(&owner.shared_tail);
                shared += 1;
            }
            if (shared != 0) self.ready_owners.push(owner.index);

            // When the batch can occupy every idle lane, one broadcast replaces
            // one futex wake per job. Smaller batches keep per-job signals so
            // lanes without work are not woken. The count is stable while the
            // pool mutex is held: workers enter and leave idle under it too.
            const idle = self.idle_workers.load(.monotonic);
            if (shared > 1 and shared >= idle) {
                self.job_ready.broadcast(self.io);
            } else {
                var i: usize = 0;
                while (i < shared) : (i += 1) {
                    self.job_ready.signal(self.io);
                }
            }
        }

        /// Reclaim a job that is still queued in the owner's shared list.
        /// Returns false when an idle worker already picked it up.
        /// Internal scheduler protocol; use Worker/Future for user work.
        pub fn reclaimShared(self: *Self, owner: *Worker(Ctx), job: *Job) bool {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);

            if (job.state() != .queued_shared) return false;
            job.remove(&owner.shared_tail);
            if (owner.shared_head.isTail()) self.ready_owners.remove(owner.index);
            if (self.execute_state_pressure.load(.monotonic) and self.ready_owners.head == null) self.execute_state_pressure.store(false, .monotonic);
            return true;
        }

        /// Internal scheduler protocol; use Worker/Future for user work.
        pub inline fn waitForJob(self: *Self, worker: *Worker(Ctx), job: *Job) bool {
            _ = worker;
            const state = job.getExecuteState();
            state.done.waitUncancelable(self.io);
            return true;
        }

        /// Internal scheduler protocol; use Worker/Future for user work.
        pub fn releaseExecuteState(self: *Self, state: *ExecuteState) void {
            self.pushExecuteState(state);
            // Normal joins already have capacity and publication's wake-ups.
            // Only actual state exhaustion needs the pool mutex for the wake.
            if (self.execute_state_pressure.load(.monotonic) and self.idle_workers.load(.monotonic) != 0) {
                self.mutex.lockUncancelable(self.io);
                defer self.mutex.unlock(self.io);
                if (self.execute_state_pressure.load(.monotonic) and self.ready_owners.head != null)
                    self.job_ready.signal(self.io);
            }
        }

        fn lockExecuteFree(self: *Self) void {
            while (self.execute_free_lock.swap(true, .acquire)) {
                std.atomic.spinLoopHint();
            }
        }

        fn unlockExecuteFree(self: *Self) void {
            self.execute_free_lock.store(false, .release);
        }

        fn pushExecuteState(self: *Self, state: *ExecuteState) void {
            state.done = .unset;
            self.lockExecuteFree();
            defer self.unlockExecuteFree();
            state.next_free = self.execute_free;
            self.execute_free = state.index;
        }

        fn acquireExecuteState(self: *Self) ?*ExecuteState {
            self.lockExecuteFree();
            defer self.unlockExecuteFree();
            const index = self.execute_free orelse {
                self.execute_state_pressure.store(true, .monotonic);
                return null;
            };
            const state = &self.execute_states[index];
            self.execute_free = state.next_free;
            state.next_free = null;
            state.io = self.io;
            state.done = .unset;
            return state;
        }

        /// Push a state while the pool mutex is already held. Used by tests
        /// that return several states under one lock to exercise pressure
        /// wake-ups without re-locking.
        fn releaseExecuteStateLocked(self: *Self, state: *ExecuteState) void {
            self.pushExecuteState(state);
            if (self.execute_state_pressure.load(.monotonic) and self.ready_owners.head != null and self.idle_workers.load(.monotonic) != 0)
                self.job_ready.signal(self.io);
        }

        /// Pick one shared job. Called with the pool mutex held.
        fn popReadyJob(self: *Self) ?*Job {
            const index = (if (self.options.fair_shared_owners)
                self.ready_owners.head
            else
                self.ready_owners.firstPriority()) orelse return null;
            const state = self.acquireExecuteState() orelse return null;
            if (self.options.fair_shared_owners) self.ready_owners.remove(index);
            const w = self.workers[index];
            std.debug.assert(w.active.load(.monotonic));
            const job = Job.popHead(&w.shared_head, &w.shared_tail).?;
            if (self.options.fair_shared_owners) {
                if (!w.shared_head.isTail()) self.ready_owners.push(index);
            } else if (w.shared_head.isTail()) self.ready_owners.remove(index);
            if (self.execute_state_pressure.load(.monotonic) and self.ready_owners.head == null) self.execute_state_pressure.store(false, .monotonic);
            job.setExecuteState(state);
            return job;
        }

        /// Explicitly offer queued work to idle lanes. Flat parallel loops use
        /// this to fill workers immediately instead of waiting for a
        /// heartbeat.
        pub fn kickstart(self: *Self, owner: *Worker(Ctx), max: usize) void {
            self.shareMany(owner, max);
        }

        /// Pool-owned dispatch scratch for high-chunk flat calls. Returns null
        /// when every object is busy; callers then use the stack/heap path.
        pub fn acquireDispatchScratch(self: *Self) ?*Scratch {
            for (self.dispatch_scratch) |*scratch| {
                if (!scratch.busy.load(.monotonic)) return scratch;
            }
            return null;
        }

        pub fn dispatchScratchBytes(self: *const Self) usize {
            return self.options.dispatch_scratch_bytes;
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

        const heartbeatWorker = @import("heartbeat.zig").Heartbeat(Self).run;

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
        try std.testing.expectEqual(@as(usize, 1), pool.active_callers.load(.monotonic));
        try std.testing.expect(pool.has_callers.load(.acquire));
        try std.testing.expect(pool.claimCaller() == null);
        pool.releaseCaller(caller);
        try std.testing.expectEqual(@as(usize, 0), pool.active_callers.load(.monotonic));
        try std.testing.expect(!pool.has_callers.load(.acquire));
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

test "shareMany bounds offered jobs and retains the local tail" {
    const F = Future(void, u64, u64);
    const Run = struct {
        fn leaf(_: *Task(void), value: u64) u64 {
            return value;
        }
    };
    var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
        .max_workers = 0,
        .max_callers = 1,
        .max_execute_states = 16,
        .enable_heartbeat = false,
    });
    defer pool.deinit();
    try pool.start();
    const caller = pool.claimCaller().?;
    defer pool.releaseCaller(caller);
    for ([_]usize{ 1, 2, 4, 8 }) |batch| {
        var task = caller.begin();
        var futures: [8]F = undefined;
        for (&futures, 0..) |*future, index| future.initFork(&task, Run.leaf, index);
        pool.shareMany(caller, batch);
        var shared: usize = 0;
        for (&futures) |*future| {
            if (future.job.state() == .queued_shared) shared += 1;
        }
        try std.testing.expect(shared <= batch);
        try std.testing.expect(shared <= futures.len - 1);
        try std.testing.expect(!caller.job_head.isTail());
        for (&futures, 0..) |*future, index| {
            try std.testing.expectEqual(@as(u64, index), future.joinOrCall(&task, Run.leaf));
        }
        try std.testing.expect(caller.job_head.isTail());
    }
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

test "pool accepts performance-core and SMT placement policies" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
        .workers = 2,
        .max_workers = 2,
        .max_callers = 1,
        .max_execute_states = 8,
        .pin_workers = true,
        .prefer_performance_cores = true,
        .use_smt_siblings = true,
    });
    defer pool.deinit();
    try pool.start();
    try std.testing.expect(pool.pinned_cpus.len > 0);
    try std.testing.expect(pool.spawned_background <= pool.pinned_cpus.len);
    for (pool.pinned_cpus, 0..) |cpu, index| {
        for (pool.pinned_cpus[0..index]) |previous| try std.testing.expect(cpu != previous);
    }
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

test "exhausted execution states wake ready work on capacity return across workers" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const F = Future(void, u64, u64);
    const Run = struct {
        fn leaf(_: *Task(void), value: u64) u64 {
            return value;
        }
        fn exhausted(pool: *Pool(void)) !void {
            for (0..20000) |_| {
                pool.mutex.lockUncancelable(pool.io);
                const stalled = pool.execute_free == null and pool.ready_owners.head != null and
                    pool.idle_workers.load(.monotonic) == pool.spawned_background;
                pool.mutex.unlock(pool.io);
                if (stalled) return;
                try pool.io.sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_us), .awake);
            }
            return error.StateExhaustionNotObserved;
        }
        fn picked(pool: *Pool(void), future: *F) !void {
            for (0..20000) |_| {
                if (future.job.state() == .executing) return;
                try pool.io.sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_us), .awake);
            }
            return error.ReadyWorkWasStranded;
        }
    };
    for (1..5) |workers| {
        var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .max_execute_states = 1,
            .enable_heartbeat = false,
        });
        defer pool.deinit();
        try pool.start();
        if (pool.spawned_background == 0) continue;
        const caller = pool.claimCaller().?;
        defer pool.releaseCaller(caller);
        for (0..3) |_| {
            var task = caller.begin();
            var futures: [4]F = undefined;
            for (&futures, 0..) |*future, index| future.initFork(&task, Run.leaf, (index + 1) * 11);
            var joined: usize = 0;
            defer for (futures[joined..]) |*future| {
                _ = future.joinOrCall(&task, Run.leaf);
            };
            pool.kickstart(caller, futures.len);
            // The first job finishes, but every worker must wait for state
            // capacity before another queued job can run. The caller's join
            // returns that capacity and must wake one of those workers.
            try Run.exhausted(&pool);
            for (futures[0..3], 0..) |*future, index| {
                try Run.picked(&pool, future);
                const value = future.joinOrCall(&task, Run.leaf);
                joined += 1;
                try std.testing.expectEqual(@as(u64, (index + 1) * 11), value);
            }
            const value = futures[3].joinOrCall(&task, Run.leaf);
            joined += 1;
            try std.testing.expectEqual(@as(u64, 44), value);
        }
    }
}

test "multiple capacity returns wake blocked peers before any state is consumed" {
    if (builtin.single_threaded) return error.SkipZigTest;
    const Barrier = struct {
        started: std.atomic.Value(usize) = .init(0),
        release: std.Io.Event = .unset,
    };
    const Input = struct { value: u64, barrier: *Barrier, blocks: bool };
    const F = Future(void, Input, u64);
    const Run = struct {
        fn leaf(t: *Task(void), input: Input) u64 {
            if (input.blocks) {
                _ = input.barrier.started.fetchAdd(1, .acq_rel);
                input.barrier.release.waitUncancelable(t.worker.pool.io);
            }
            return input.value;
        }
        fn idle(pool: *Pool(void)) !void {
            for (0..20000) |_| {
                pool.mutex.lockUncancelable(pool.io);
                const stalled = pool.execute_free == null and pool.ready_owners.head != null and
                    pool.idle_workers.load(.monotonic) == pool.spawned_background;
                pool.mutex.unlock(pool.io);
                if (stalled) return;
                try pool.io.sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_us), .awake);
            }
            return error.StateExhaustionNotObserved;
        }
        fn bothStarted(pool: *Pool(void), barrier: *Barrier) !void {
            for (0..20000) |_| {
                if (barrier.started.load(.acquire) == 2) return;
                try pool.io.sleep(std.Io.Duration.fromNanoseconds(50 * std.time.ns_per_us), .awake);
            }
            return error.ReadyPeerWasStranded;
        }
    };
    for (2..5) |workers| {
        var pool = try Pool(void).init(std.testing.allocator, std.testing.io, .{
            .workers = workers,
            .max_workers = workers,
            .max_callers = 1,
            .max_execute_states = 2,
            .enable_heartbeat = false,
        });
        defer pool.deinit();
        try pool.start();
        if (pool.spawned_background < 2) continue;
        const caller = pool.claimCaller().?;
        defer pool.releaseCaller(caller);
        for (0..3) |_| {
            var barrier = Barrier{};
            var task = caller.begin();
            var futures: [5]F = undefined;
            for (&futures, 0..) |*future, index| future.initFork(&task, Run.leaf, .{
                .value = (index + 1) * 11,
                .barrier = &barrier,
                .blocks = index == 2 or index == 3,
            });
            var joined: usize = 0;
            defer {
                barrier.release.set(pool.io);
                for (futures[joined..]) |*future| _ = future.joinOrCall(&task, Run.leaf);
            }
            pool.kickstart(caller, futures.len);
            try Run.idle(&pool);
            var states: [2]*ExecuteState = undefined;
            for (futures[0..2], &states, 0..) |*future, *state, index| {
                state.* = future.job.getExecuteState();
                // Perform the wait/result part of join first, then return both
                // states under one lock so no worker can consume the first
                // capacity before the second return. This is a white-box join.
                try std.testing.expect(pool.waitForJob(caller, &future.job));
                try std.testing.expectEqual(@as(u64, (index + 1) * 11), future.result());
            }
            pool.mutex.lockUncancelable(pool.io);
            for (states) |state| pool.releaseExecuteStateLocked(state);
            pool.mutex.unlock(pool.io);
            joined = 2;
            try Run.bothStarted(&pool, &barrier);
            barrier.release.set(pool.io);
            for (futures[2..], 2..) |*future, index| {
                const value = future.joinOrCall(&task, Run.leaf);
                joined += 1;
                try std.testing.expectEqual(@as(u64, (index + 1) * 11), value);
            }
            try std.testing.expect(!pool.execute_state_pressure.load(.monotonic));
        }
    }
}
