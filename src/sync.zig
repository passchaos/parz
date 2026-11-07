//! Standalone synchronization primitives.
//!
//! This module is intentionally independent of the scheduler. Queues and the
//! stack are non-blocking; semaphores and wait groups use `std.Io` for
//! blocking. All containers are bounded and allocate only in `init`.
//!
//! Implementations live in `sync/`:
//! - `spsc.zig` — single-producer/single-consumer ring buffer
//! - `mpsc.zig` — multi-producer/single-consumer ring buffer
//! - `sharded_mpsc.zig` — per-producer SPSC shards
//! - `blocking_queue.zig` — bounded blocking MPMC queue
//! - `treiber_stack.zig` — multi-producer/single-consumer stack
//! - `coordination.zig` — counting semaphore and wait group

const spsc = @import("sync/spsc.zig");
const mpsc = @import("sync/mpsc.zig");
const sharded_mpsc = @import("sync/sharded_mpsc.zig");
const blocking_queue = @import("sync/blocking_queue.zig");
const treiber_stack = @import("sync/treiber_stack.zig");
const coordination = @import("sync/coordination.zig");

pub const SpscQueue = spsc.SpscQueue;
pub const MpscQueue = mpsc.MpscQueue;
pub const ShardedMpscQueue = sharded_mpsc.ShardedMpscQueue;
pub const BlockingQueue = blocking_queue.BlockingQueue;
pub const TreiberStack = treiber_stack.TreiberStack;
pub const Semaphore = coordination.Semaphore;
pub const WaitGroup = coordination.WaitGroup;

test {
    _ = spsc;
    _ = mpsc;
    _ = sharded_mpsc;
    _ = blocking_queue;
    _ = treiber_stack;
    _ = coordination;
}
