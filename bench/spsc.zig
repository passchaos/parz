//! Fixed-CPU SPSC comparison against the frozen pre-cache implementation.
//! Every warmup and sample checks FIFO order, checksum and the final length.
//! Allocation, thread creation and affinity setup are outside the timed region.
const std = @import("std");
const builtin = @import("builtin");
const parz = @import("parz");
const baseline = @import("spsc_baseline.zig");
const timing = @import("timing.zig");

const Config = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    count: usize,
    capacity: usize,
    producer_cpu: usize,
    consumer_cpu: usize,
};

fn pin(cpu: usize) !void {
    if (builtin.os.tag != .linux) return error.AffinityUnsupported;
    var set = std.mem.zeroes(std.os.linux.cpu_set_t);
    const bits = @bitSizeOf(@TypeOf(set[0]));
    if (cpu >= set.len * bits) return error.InvalidCpu;
    set[cpu / bits] |= @as(@TypeOf(set[0]), 1) << @intCast(cpu % bits);
    try std.os.linux.sched_setaffinity(0, &set);
}

fn run(comptime Queue: type, comptime parallel: bool, config: Config) !i96 {
    var queue = try Queue.init(config.allocator, config.capacity);
    defer queue.deinit();
    var checksum: u64 = 0;
    var bad_order = false;
    var elapsed: i96 = undefined;
    if (parallel) {
        const State = struct {
            queue: *Queue,
            count: usize,
            cpu: usize,
            ready: std.atomic.Value(u8) align(std.atomic.cache_line) = .init(0),
            start: std.atomic.Value(bool) = .init(false),

            fn produce(self: *@This()) void {
                pin(self.cpu) catch {
                    self.ready.store(2, .release);
                    return;
                };
                self.ready.store(1, .release);
                while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
                for (0..self.count) |value| {
                    while (!self.queue.tryPush(@intCast(value))) std.atomic.spinLoopHint();
                }
            }
        };
        var state = State{ .queue = &queue, .count = config.count, .cpu = config.producer_cpu };
        const thread = try std.Thread.spawn(.{}, State.produce, .{&state});
        defer thread.join();
        var ready: u8 = 0;
        while (ready == 0) {
            ready = state.ready.load(.acquire);
            std.atomic.spinLoopHint();
        }
        if (ready == 2) return error.ProducerAffinityFailed;
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        state.start.store(true, .release);
        var received: usize = 0;
        while (received < config.count) {
            if (queue.tryPop()) |value| {
                bad_order = bad_order or value != received;
                checksum +%= value;
                received += 1;
            } else std.atomic.spinLoopHint();
        }
        elapsed = start.untilNow(config.io).raw.toNanoseconds();
    } else {
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        var offset: usize = 0;
        while (offset < config.count) {
            const end = offset + @min(queue.capacity(), config.count - offset);
            for (offset..end) |value| {
                if (!queue.tryPush(@intCast(value))) return error.UnexpectedFull;
            }
            for (offset..end) |expected| {
                const value = queue.tryPop() orelse return error.UnexpectedEmpty;
                bad_order = bad_order or value != expected;
                checksum +%= value;
            }
            offset = end;
        }
        elapsed = start.untilNow(config.io).raw.toNanoseconds();
    }
    const expected: u64 = @truncate(@as(u128, config.count) * (config.count - 1) / 2);
    if (bad_order or checksum != expected or queue.len() != 0) return error.ChecksumMismatch;
    return elapsed;
}

fn sample(path: usize, config: Config) !i96 {
    return switch (path) {
        0 => run(baseline.SpscQueue(u64), false, config),
        1 => run(baseline.SpscQueue(u64), true, config),
        2 => run(parz.sync.SpscQueue(u64), false, config),
        3 => run(parz.sync.SpscQueue(u64), true, config),
        else => unreachable,
    };
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const count = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 1_000_000;
    const capacity = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 1024;
    const producer_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 0;
    const consumer_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 2;
    const rounds = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 9;
    if (count == 0 or rounds == 0 or producer_cpu == consumer_cpu) return error.InvalidArguments;
    try pin(consumer_cpu);
    const config = Config{
        .allocator = init.gpa,
        .io = init.io,
        .count = count,
        .capacity = capacity,
        .producer_cpu = producer_cpu,
        .consumer_cpu = consumer_cpu,
    };
    var samples: [4][]i96 = undefined;
    const storage = try init.gpa.alloc(i96, try std.math.mul(usize, 4, rounds));
    defer init.gpa.free(storage);
    for (&samples, 0..) |*values, index| values.* = storage[index * rounds ..][0..rounds];
    for (0..4) |path| _ = try sample(path, config);
    std.debug.print("spsc count={d} capacity={d} producer_cpu={d} consumer_cpu={d} checksum={d} baseline_bytes={d} candidate_bytes={d}\n", .{
        count,                              capacity,                         producer_cpu,                      consumer_cpu,
        @as(u128, count) * (count - 1) / 2, @sizeOf(baseline.SpscQueue(u64)), @sizeOf(parz.sync.SpscQueue(u64)),
    });
    for (0..rounds) |round| {
        for (0..4) |order| {
            const path = if (round % 2 == 0) order else 3 - order;
            samples[path][round] = try sample(path, config);
        }
        std.debug.print("sample={d} baseline_serial_ns={d} baseline_parallel_ns={d} candidate_serial_ns={d} candidate_parallel_ns={d}\n", .{
            round, samples[0][round], samples[1][round], samples[2][round], samples[3][round],
        });
    }
    for (samples) |values| std.mem.sort(i96, values, {}, std.sort.asc(i96));
    const base = timing.Times{ .serial_ns = samples[0][rounds / 2], .parallel_ns = samples[1][rounds / 2] };
    const candidate = timing.Times{ .serial_ns = samples[2][rounds / 2], .parallel_ns = samples[3][rounds / 2] };
    std.debug.print("spsc implementation=baseline serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ base.serial_ns, base.parallel_ns, base.speedup() });
    std.debug.print("spsc implementation=candidate serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ candidate.serial_ns, candidate.parallel_ns, candidate.speedup() });
    std.debug.print("spsc comparison baseline_ns={d} candidate_ns={d} speedup={d:.3} statistic=median\n", .{
        base.parallel_ns,                                                                           candidate.parallel_ns,
        @as(f64, @floatFromInt(base.parallel_ns)) / @as(f64, @floatFromInt(candidate.parallel_ns)),
    });
}
