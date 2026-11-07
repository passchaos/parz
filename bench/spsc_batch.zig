//! Fixed-CPU scalar/batch transfer with identical prebuilt input and FIFO checks.
const std = @import("std");
const builtin = @import("builtin");
const parz = @import("parz");
const timing = @import("timing.zig");
const Queue = parz.sync.SpscQueue(u64);

const Config = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    values: []const u64,
    scratch: []u64,
    capacity: usize,
    producer_cpu: usize,
};

fn pin(cpu: usize) !void {
    if (builtin.os.tag != .linux) return error.AffinityUnsupported;
    var set = std.mem.zeroes(std.os.linux.cpu_set_t);
    const bits = @bitSizeOf(@TypeOf(set[0]));
    if (cpu >= set.len * bits) return error.InvalidCpu;
    set[cpu / bits] |= @as(@TypeOf(set[0]), 1) << @intCast(cpu % bits);
    try std.os.linux.sched_setaffinity(0, &set);
}

fn run(comptime batch: bool, comptime parallel: bool, comptime single: bool, config: Config) !i96 {
    var queue = try Queue.init(config.allocator, config.capacity);
    defer queue.deinit();
    var checksum: u64 = 0;
    var bad_order = false;
    var elapsed: i96 = undefined;
    if (parallel) {
        const State = struct {
            queue: *Queue,
            values: []const u64,
            batch_size: usize,
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
                var next: usize = 0;
                while (next < self.values.len) {
                    const length = if (single) 1 else @min(self.batch_size, self.values.len - next);
                    const pushed: usize = if (batch)
                        self.queue.tryPushSlice(self.values[next..][0..length])
                    else blk: {
                        var pushed: usize = 0;
                        while (pushed < length) : (pushed += 1) {
                            if (!self.queue.tryPush(self.values[next + pushed])) break;
                        }
                        break :blk pushed;
                    };
                    next += pushed;
                    if (pushed == 0) std.atomic.spinLoopHint();
                }
            }
        };
        var state = State{ .queue = &queue, .values = config.values, .batch_size = config.scratch.len, .cpu = config.producer_cpu };
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
        while (received < config.values.len) {
            const length = if (single) 1 else @min(config.scratch.len, config.values.len - received);
            const popped = if (batch) queue.tryPopSlice(config.scratch[0..length]) else blk: {
                var popped: usize = 0;
                while (popped < length) : (popped += 1) {
                    config.scratch[popped] = queue.tryPop() orelse break;
                }
                break :blk popped;
            };
            for (config.scratch[0..popped]) |value| {
                bad_order = bad_order or value != config.values[received];
                checksum +%= value;
                received += 1;
            }
            if (popped == 0) std.atomic.spinLoopHint();
        }
        elapsed = start.untilNow(config.io).raw.toNanoseconds();
    } else {
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        var next: usize = 0;
        while (next < config.values.len) {
            const length = if (single) 1 else @min(@min(config.scratch.len, queue.capacity()), config.values.len - next);
            const input = config.values[next..][0..length];
            if (batch) {
                if (queue.tryPushSlice(input) != length) return error.UnexpectedFull;
                if (queue.tryPopSlice(config.scratch[0..length]) != length) return error.UnexpectedEmpty;
            } else {
                for (input) |value| if (!queue.tryPush(value)) return error.UnexpectedFull;
                for (config.scratch[0..length]) |*value| value.* = queue.tryPop() orelse return error.UnexpectedEmpty;
            }
            for (config.scratch[0..length], input) |value, expected| {
                bad_order = bad_order or value != expected;
                checksum +%= value;
            }
            next += length;
        }
        elapsed = start.untilNow(config.io).raw.toNanoseconds();
    }
    const count = config.values.len;
    const expected: u64 = @truncate(@as(u128, count) * (count - 1) / 2);
    if (bad_order or checksum != expected or queue.len() != 0) return error.ChecksumMismatch;
    return elapsed;
}

fn sample(path: usize, config: Config) !i96 {
    if (config.scratch.len == 1) return switch (path) {
        0 => run(false, false, true, config),
        1 => run(false, true, true, config),
        2 => run(true, false, true, config),
        3 => run(true, true, true, config),
        else => unreachable,
    };
    return switch (path) {
        0 => run(false, false, false, config),
        1 => run(false, true, false, config),
        2 => run(true, false, false, config),
        3 => run(true, true, false, config),
        else => unreachable,
    };
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const count = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 3_000_000;
    const capacity = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 1024;
    const batch_size = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 64;
    const producer_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 24;
    const consumer_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 26;
    const rounds = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 9;
    if (count == 0 or batch_size == 0 or rounds == 0 or producer_cpu == consumer_cpu) return error.InvalidArguments;
    try pin(consumer_cpu);
    const values = try init.gpa.alloc(u64, count);
    defer init.gpa.free(values);
    for (values, 0..) |*value, index| value.* = @intCast(index);
    const queue_capacity = std.math.ceilPowerOfTwo(usize, @max(capacity, 1)) catch return error.CapacityOverflow;
    const scratch = try init.gpa.alloc(u64, @min(count, @min(batch_size, queue_capacity)));
    defer init.gpa.free(scratch);
    const config = Config{ .allocator = init.gpa, .io = init.io, .values = values, .scratch = scratch, .capacity = capacity, .producer_cpu = producer_cpu };
    const storage = try init.gpa.alloc(i96, try std.math.mul(usize, 4, rounds));
    defer init.gpa.free(storage);
    var samples: [4][]i96 = undefined;
    for (&samples, 0..) |*entry, index| entry.* = storage[index * rounds ..][0..rounds];
    for (0..4) |path| _ = try sample(path, config);
    std.debug.print("spsc-batch count={d} capacity={d} batch={d} effective_batch={d} producer_cpu={d} consumer_cpu={d} checksum={d}\n", .{
        count, capacity, batch_size, scratch.len, producer_cpu, consumer_cpu, @as(u128, count) * (count - 1) / 2,
    });
    for (0..rounds) |round| {
        for (0..4) |order| {
            const path = if (round % 2 == 0) order else 3 - order;
            samples[path][round] = try sample(path, config);
        }
        std.debug.print("sample={d} scalar_serial_ns={d} scalar_parallel_ns={d} batch_serial_ns={d} batch_parallel_ns={d}\n", .{ round, samples[0][round], samples[1][round], samples[2][round], samples[3][round] });
    }
    for (samples) |values_ns| std.mem.sort(i96, values_ns, {}, std.sort.asc(i96));
    const scalar = timing.Times{ .serial_ns = samples[0][rounds / 2], .parallel_ns = samples[1][rounds / 2] };
    const batched = timing.Times{ .serial_ns = samples[2][rounds / 2], .parallel_ns = samples[3][rounds / 2] };
    std.debug.print("spsc implementation=scalar serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ scalar.serial_ns, scalar.parallel_ns, scalar.speedup() });
    std.debug.print("spsc implementation=batch serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ batched.serial_ns, batched.parallel_ns, batched.speedup() });
    std.debug.print("spsc comparison scalar_ns={d} batch_ns={d} speedup={d:.3}\n", .{ scalar.parallel_ns, batched.parallel_ns, @as(f64, @floatFromInt(scalar.parallel_ns)) / @as(f64, @floatFromInt(batched.parallel_ns)) });
}
