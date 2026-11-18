//! Flat parallel loop / fold APIs on top of the heartbeat scheduler.
//!
//! These APIs intentionally use direct callbacks instead of a composable
//! Rayon-style iterator. Every chunk owns a disjoint range; results are
//! combined in chunk-index order, so the output does not depend on which
//! worker ran which chunk.

pub const Chunk = @import("parallel/types.zig").Chunk;
pub const Schedule = @import("parallel/types.zig").Schedule;
pub const Options = @import("parallel/types.zig").Options;
pub const Scratch = @import("parallel/scratch.zig").Scratch;

pub const parallelFor = @import("parallel/index.zig").parallelFor;
pub const parallelForEach = @import("parallel/index.zig").parallelForEach;
pub const parallelFor2D = @import("parallel/index.zig").parallelFor2D;
pub const parallelForRange = @import("parallel/range.zig").parallelForRange;
pub const parallelFoldRange = @import("parallel/range.zig").parallelFoldRange;
pub const parallelFoldRangeInfallible = @import("parallel/range.zig").parallelFoldRangeInfallible;
pub const parallelFold = @import("parallel/fold.zig").parallelFold;
pub const parallelFoldInfallible = @import("parallel/fold.zig").parallelFoldInfallible;
pub const parallelReduce = @import("parallel/fold.zig").parallelReduce;
pub const parallelReduceInfallible = @import("parallel/fold.zig").parallelReduceInfallible;

test {
    _ = @import("parallel/types.zig");
    _ = @import("parallel/cancellation.zig");
    _ = @import("parallel/index.zig");
    _ = @import("parallel/range.zig");
    _ = @import("parallel/fold.zig");
    _ = @import("parallel/dispatch.zig");
    _ = @import("parallel/planning.zig");
    _ = @import("parallel/serial.zig");
    _ = @import("parallel/executor.zig");
    _ = @import("parallel/scratch.zig");
}
