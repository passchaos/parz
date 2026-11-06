//! parz: Zig-native fine-grained parallelism.
//!
//! Public surface:
//! - `Pool(Ctx)` / `Worker(Ctx)` / `Task(Ctx)` / `Future(Ctx, Input, Output)`
//! - `parallelFor`, `parallelForEach`, `parallelForRange`, `parallelFold`,
//!   `parallelReduce`
//!
//! The scheduler core is derived from judofyr/spice (0BSD). The flat loop
//! APIs, error propagation, per-worker context, deterministic combine, and
//! bounded execute-state pool are project-specific additions.

pub const core = @import("core.zig");
pub const parallel = @import("parallel.zig");
pub const job = @import("job.zig");

pub const Pool = core.Pool;
pub const Options = core.Options;
pub const Worker = core.Worker;
pub const Task = core.Task;
pub const Future = core.Future;

pub const Chunk = parallel.Chunk;
pub const ParallelOptions = parallel.Options;
pub const parallelFor = parallel.parallelFor;
pub const parallelForEach = parallel.parallelForEach;
pub const parallelForRange = parallel.parallelForRange;
pub const parallelFold = parallel.parallelFold;
pub const parallelReduce = parallel.parallelReduce;

test {
    _ = job;
    _ = core;
    _ = parallel;
}
