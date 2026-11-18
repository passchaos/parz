//! Flat callback options, chunk ranges and scheduling policy.

const std = @import("std");
const CancelToken = @import("../cancel.zig").CancelToken;
const Scratch = @import("scratch.zig").Scratch;

pub const Chunk = struct {
    start: usize,
    end: usize,
};

pub const Schedule = enum {
    /// Idle lanes dynamically claim chunks. Best for irregular work and
    /// heterogeneous CPUs.
    dynamic,
    /// Each dispatch lane owns one contiguous span of chunk indices. This
    /// removes cursor contention and improves locality for uniform work.
    static,
};

pub const Options = struct {
    /// Minimum number of logical items per chunk, unless the whole input is smaller.
    min_chunk: usize = 1,
    /// Hard upper bound on chunks for one call.
    max_chunks: usize = 4096,
    /// Target chunks per available lane. More chunks improve dynamic load
    /// balance; static scheduling assigns them in contiguous lane spans. This
    /// controls granularity rather than the number of jobs to wake.
    chunks_per_worker: usize = 16,
    /// Dynamic balances irregular callbacks; static avoids the shared cursor
    /// when each chunk has predictable cost.
    schedule: Schedule = .dynamic,
    /// Per-call lane cap, including the caller. 0 uses all available lanes.
    max_workers: usize = 0,
    /// Run serially below this item count. A flat call with fewer items than
    /// this is almost always dominated by caller-slot setup, future
    /// allocation, and worker wake-up cost. Set to 0 to force parallelism.
    serial_threshold: usize = 4096,
    /// Optional cooperative cancellation token. Nonempty calls check chunk
    /// entry/exit and successful completion; index loops also check every
    /// 4096 items. Range callbacks may check the token within their own work.
    cancel: ?*CancelToken = null,
    /// Estimated useful nanoseconds per item. Zero leaves existing item-count
    /// planning unchanged; a nonzero estimate adds a minimum-work guard and
    /// caps lanes by useful work per lane. serial_threshold=0 still explicitly
    /// forces dispatch.
    estimated_item_ns: usize = 0,
    min_parallel_ns: usize = 50 * std.time.ns_per_us,
    /// Minimum useful work per lane when `estimated_item_ns` is nonzero.
    /// Cheap calls use fewer lanes so they do not pay wake-up cost for lanes
    /// that cannot stay busy. Zero disables the lane cap.
    min_parallel_lane_ns: usize = 20 * std.time.ns_per_us,
    /// Strict caller-owned dispatch buffer. Insufficient capacity returns
    /// OutOfMemory before callbacks. Nested use gets an independent stack
    /// fallback; concurrent calls require separate scratch objects.
    scratch: ?*Scratch = null,
};
