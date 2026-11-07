const std = @import("std");
const parz = @import("parz");
test "allocation-fixture: 256 chunks need no pool allocations" {
    const Run = struct {
        fn map(_: *parz.Worker(void), _: void, index: usize) u64 { return index; }
        fn add(a: u64, b: u64) u64 { return a + b; }
    };
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var pool = try parz.Pool(void).init(failing.allocator(), std.testing.io, .{ .workers = 1, .max_workers = 1, .max_callers = 1 });
    defer pool.deinit();
    try pool.start();
    if (pool.spawned_background != 1) return error.SkipZigTest;
    failing.fail_index = failing.alloc_index;
    const result = try parz.parallelFoldInfallible(&pool, u64, {}, 4096, .{ .min_chunk = 1, .max_chunks = 256, .chunks_per_worker = 256, .serial_threshold = 0 }, 0, Run.map, Run.add);
    try std.testing.expectEqual(@as(u64, 8386560), result);
    try std.testing.expect(!failing.has_induced_failure);
}
