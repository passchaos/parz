const std = @import("std");
const parz = @import("parz");
test "serial-kick-fixture: inactive fallback keeps jobs local" {
    const Run = struct {
        fn leaf(_: *parz.Task(void), value: usize) usize { return value + 1; }
        fn range(w: *parz.Worker(void), _: void, _: parz.Chunk) anyerror!void {
            var task = w.begin();
            var first: parz.Future(void, usize, usize) = undefined;
            var second: parz.Future(void, usize, usize) = undefined;
            first.initFork(&task, leaf, 3);
            second.initFork(&task, leaf, 7);
            w.pool.kickstart(w, 1);
            try std.testing.expectEqual(parz.job.JobState.queued_local, first.job.state());
            try std.testing.expectEqual(@as(usize, 12), first.joinOrCall(&task, leaf) + second.joinOrCall(&task, leaf));
        }
    };
    var pool = try parz.Pool(void).init(std.testing.allocator, std.testing.io, .{ .max_workers = 0, .max_callers = 1 });
    defer pool.deinit();
    try pool.start();
    try parz.parallelForRange(&pool, {}, 8, .{}, Run.range);
}
