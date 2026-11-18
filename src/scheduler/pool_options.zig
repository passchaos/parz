//! Pool resource bounds, pacing policy and context constructors.

const std = @import("std");

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
        /// workers idle. Optional parking stops the timer when there is no
        /// heartbeat demand.
        idle_heartbeat_interval_ns: i96 = 20 * std.time.ns_per_us,
        /// Keep periodic pacing through short gaps in a burst of calls before
        /// parking. This avoids a heartbeat wake-up on every small flat call.
        idle_heartbeat_grace_ns: i96 = 10 * std.time.ns_per_ms,
        /// Opt-in complete idle parking. Saves periodic wake-ups, but cold
        /// first-call latency can increase. Default periodic pacing preserves
        /// the measured latency contract.
        park_idle_heartbeat: bool = false,
        /// Opt-in periodic idle metadata shortcut. Avoids the pool mutex and
        /// idle lane writes, but may increase cold first-call latency. Default
        /// pacing retains the original mutex/metadata path.
        skip_idle_heartbeat_metadata: bool = false,
        /// Start a dedicated heartbeat thread. Without it, `tick` never
        /// shares work and only eager `kickstart` paths (flat loops) run in
        /// parallel.
        enable_heartbeat: bool = true,
        /// Pin each background worker to a distinct allowed CPU. Linux only;
        /// a no-op elsewhere. The caller thread is not pinned.
        pin_workers: bool = false,
        /// On hybrid CPUs, order pinned CPUs by sysfs `cpu_capacity` so
        /// performance cores are used before efficiency cores. Best effort;
        /// missing sysfs data preserves the original order.
        prefer_performance_cores: bool = false,
        /// Include SMT siblings after every physical core has one logical CPU.
        /// The default keeps one logical CPU per physical core.
        use_smt_siblings: bool = false,
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
