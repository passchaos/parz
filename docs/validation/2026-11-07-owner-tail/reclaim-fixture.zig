const std = @import("std");
const parz = @import("parz");
const Task = parz.Task;
const Future = parz.Future;
const Pool = parz.Pool;
const job_mod = parz.job;

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
    var task = caller.begin();
    var parent = Future(void, void, anyerror!bool){};
    parent.fork(&task, Descendants.run, {});
    task.call(void, Nested.run, {});
    try std.testing.expectEqual(job_mod.JobState.queued_shared, parent.job.state());
    try std.testing.expect(try parent.joinOrCall(&task, Descendants.run));
}
