//! Throughput smoke benchmarks for the sync module.

const std = @import("std");
const parz = @import("parz");

const total: usize = 1_000_000;
const mpsc_producers: usize = 4;
const mpsc_per_producer: usize = total / mpsc_producers;
const treiber_producers: usize = 4;
const treiber_per_producer: usize = total / treiber_producers;
const blocking_producers: usize = 2;
const blocking_per_producer: usize = total / blocking_producers;
const blocking_consumers: usize = 2;
const blocking_per_consumer: usize = total / blocking_consumers;

fn now(io: std.Io) std.Io.Clock.Timestamp {
    return std.Io.Clock.Timestamp.now(io, .awake);
}

fn report(name: []const u8, ns: i96, count: usize) void {
    const ops = @as(f64, @floatFromInt(count)) * 1e9 / @as(f64, @floatFromInt(ns));
    std.debug.print("{s} count={d} ns={d} ops_per_sec={d:.0}\n", .{
        name, count, ns, ops,
    });
}

fn runSpsc(allocator: std.mem.Allocator, io: std.Io) !void {
    var queue = try parz.sync.SpscQueue(u64).init(allocator, 1024);
    defer queue.deinit();

    const Producer = struct {
        fn run(q: *parz.sync.SpscQueue(u64)) void {
            var value: u64 = 0;
            while (value < total) {
                if (q.tryPush(value)) {
                    value += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    const start = now(io);
    const thread = try std.Thread.spawn(.{}, Producer.run, .{&queue});
    var received: usize = 0;
    var checksum: u64 = 0;
    var bad_order = false;
    while (received < total) {
        if (queue.tryPop()) |value| {
            checksum += value;
            bad_order = bad_order or value != received;
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    thread.join();
    if (bad_order or checksum != @as(u64, total) * (total - 1) / 2 or queue.len() != 0)
        return error.ChecksumMismatch;
    report("spsc", start.untilNow(io).raw.toNanoseconds(), total);
    std.debug.print("spsc checksum={d}\n", .{checksum});
}

fn runMpsc(allocator: std.mem.Allocator, io: std.Io) !void {
    var queue = try parz.sync.MpscQueue(u64).init(allocator, 1024);
    defer queue.deinit();

    const Producer = struct {
        fn run(q: *parz.sync.MpscQueue(u64), base: u64) void {
            var offset: usize = 0;
            while (offset < mpsc_per_producer) {
                if (q.tryPush(base + @as(u64, @intCast(offset)))) {
                    offset += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    const start = now(io);
    var threads: [mpsc_producers]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{
            &queue,
            @as(u64, @intCast(index * mpsc_per_producer)),
        });
    }
    var received: usize = 0;
    while (received < total) {
        if (queue.tryPop()) |_| {
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    for (threads) |thread| thread.join();
    report("mpsc", start.untilNow(io).raw.toNanoseconds(), total);
}

fn runMpscSingle(allocator: std.mem.Allocator, io: std.Io) !void {
    var queue = try parz.sync.MpscQueue(u64).init(allocator, 1024);
    defer queue.deinit();

    const Producer = struct {
        fn run(q: *parz.sync.MpscQueue(u64)) void {
            var value: u64 = 0;
            while (value < total) {
                if (q.tryPush(value)) {
                    value += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    const start = now(io);
    const thread = try std.Thread.spawn(.{}, Producer.run, .{&queue});
    var received: usize = 0;
    while (received < total) {
        if (queue.tryPop()) |_| {
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    thread.join();
    report("mpsc-1p", start.untilNow(io).raw.toNanoseconds(), total);
}

fn runShardedMpsc(allocator: std.mem.Allocator, io: std.Io) !void {
    const shards = 4;
    var queue = try parz.sync.ShardedMpscQueue(u64, shards).init(allocator, 1024);
    defer queue.deinit();

    const Producer = struct {
        fn run(q: *parz.sync.ShardedMpscQueue(u64, shards), shard: usize, base: u64) void {
            var offset: usize = 0;
            while (offset < mpsc_per_producer) {
                if (q.tryPush(shard, base + @as(u64, @intCast(offset)))) {
                    offset += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    const start = now(io);
    var threads: [shards]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{
            &queue,
            index,
            @as(u64, @intCast(index * mpsc_per_producer)),
        });
    }
    var received: usize = 0;
    while (received < total) {
        if (queue.tryPop()) |_| {
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    for (threads) |thread| thread.join();
    report("mpsc-sharded", start.untilNow(io).raw.toNanoseconds(), total);
}

fn runMutexMpsc(allocator: std.mem.Allocator, io: std.Io) !void {
    var queue = try parz.sync.BlockingQueue(u64).init(allocator, 1024);
    defer queue.deinit();

    const Producer = struct {
        fn run(q: *parz.sync.BlockingQueue(u64), thread_io: std.Io, base: u64) void {
            var offset: usize = 0;
            while (offset < mpsc_per_producer) {
                if (q.tryPut(thread_io, base + @as(u64, @intCast(offset)))) {
                    offset += 1;
                } else {
                    std.atomic.spinLoopHint();
                }
            }
        }
    };

    const start = now(io);
    var threads: [mpsc_producers]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{
            &queue,
            io,
            @as(u64, @intCast(index * mpsc_per_producer)),
        });
    }
    var received: usize = 0;
    while (received < total) {
        if (queue.tryGet(io)) |_| {
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    for (threads) |thread| thread.join();
    report("mpsc-mutex", start.untilNow(io).raw.toNanoseconds(), total);
}

fn runTreiber(allocator: std.mem.Allocator, io: std.Io) !void {
    var stack = parz.sync.TreiberStack(u64){};
    const Node = parz.sync.TreiberStack(u64).Node;
    const nodes = try allocator.alloc(Node, total);
    defer allocator.free(nodes);

    const Producer = struct {
        fn run(s: *parz.sync.TreiberStack(u64), slice: []Node, base: u64) void {
            for (slice, 0..) |*node, index| {
                node.* = .{ .value = base + @as(u64, @intCast(index)) };
                s.push(node);
            }
        }
    };

    const start = now(io);
    var threads: [treiber_producers]std.Thread = undefined;
    for (&threads, 0..) |*thread, index| {
        const base = @as(u64, @intCast(index * treiber_per_producer));
        const slice = nodes[index * treiber_per_producer ..][0..treiber_per_producer];
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{ &stack, slice, base });
    }
    var received: usize = 0;
    while (received < total) {
        if (stack.pop()) |_| {
            received += 1;
        } else {
            std.atomic.spinLoopHint();
        }
    }
    for (threads) |thread| thread.join();
    report("treiber", start.untilNow(io).raw.toNanoseconds(), total);
}

fn runBlocking(allocator: std.mem.Allocator, io: std.Io) !void {
    var queue = try parz.sync.BlockingQueue(u64).init(allocator, 1024);
    defer queue.deinit();

    const Producer = struct {
        fn run(q: *parz.sync.BlockingQueue(u64), thread_io: std.Io, base: u64) void {
            for (0..blocking_per_producer) |index| {
                q.put(thread_io, base + @as(u64, @intCast(index))) catch unreachable;
            }
        }
    };
    const Consumer = struct {
        fn run(q: *parz.sync.BlockingQueue(u64), thread_io: std.Io) void {
            for (0..blocking_per_consumer) |_| {
                _ = q.get(thread_io) catch unreachable;
            }
        }
    };

    const start = now(io);
    var producers: [blocking_producers]std.Thread = undefined;
    for (&producers, 0..) |*thread, index| {
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{
            &queue,
            io,
            @as(u64, @intCast(index * blocking_per_producer)),
        });
    }
    var consumers: [blocking_consumers]std.Thread = undefined;
    for (&consumers) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Consumer.run, .{ &queue, io });
    }
    for (producers) |thread| thread.join();
    for (consumers) |thread| thread.join();
    report("blocking", start.untilNow(io).raw.toNanoseconds(), total);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    try runSpsc(allocator, io);
    try runMpsc(allocator, io);
    try runMpscSingle(allocator, io);
    try runShardedMpsc(allocator, io);
    try runMutexMpsc(allocator, io);
    try runTreiber(allocator, io);
    try runBlocking(allocator, io);
}
