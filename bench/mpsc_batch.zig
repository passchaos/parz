//! Fixed-CPU MPSC transfers with prebuilt input and per-producer FIFO checks.
const std = @import("std");
const builtin = @import("builtin");
const parz = @import("parz");
const timing = @import("timing.zig");
const Queue = parz.sync.MpscQueue(u64);

fn pin(cpu: usize) !void {
    if (builtin.os.tag != .linux) return error.AffinityUnsupported;
    var set = std.mem.zeroes(std.os.linux.cpu_set_t);
    const bits = @bitSizeOf(@TypeOf(set[0]));
    if (cpu >= set.len * bits) return error.InvalidCpu;
    set[cpu / bits] |= @as(@TypeOf(set[0]), 1) << @intCast(cpu % bits);
    try std.os.linux.sched_setaffinity(0, &set);
}

const Config = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    values: []const u64,
    scratch: []u64,
    positions: []usize,
    capacity: usize,
    cpus: []const usize,
};

fn push(comptime batch: bool, queue: *Queue, input: []const u64) usize {
    if (batch) return queue.tryPushSlice(input);
    var count: usize = 0;
    while (count < input.len) : (count += 1) {
        if (!queue.tryPush(input[count])) break;
    }
    return count;
}

fn pop(comptime batch: bool, queue: *Queue, output: []u64) usize {
    if (batch) return queue.tryPopSlice(output);
    var count: usize = 0;
    while (count < output.len) : (count += 1) output[count] = queue.tryPop() orelse break;
    return count;
}

const Observer = struct {
    positions: []usize,
    per_producer: usize,
    checksum: u64 = 0,
    bad_order: bool = false,

    fn accept(self: *@This(), values: []const u64) void {
        for (values) |value| {
            const id = value / self.per_producer;
            if (id < self.positions.len) {
                self.bad_order = self.bad_order or value % self.per_producer != self.positions[id];
                self.positions[id] += 1;
            } else self.bad_order = true;
            self.checksum +%= value;
        }
    }
};

fn run(comptime batch: bool, comptime parallel: bool, comptime single: bool, config: Config) !i96 {
    var queue = try Queue.init(config.allocator, config.capacity);
    defer queue.deinit();
    @memset(config.positions, 0);
    const per_producer = config.values.len / config.cpus.len;
    var observer = Observer{ .positions = config.positions, .per_producer = per_producer };
    const elapsed = if (parallel) blk: {
        const State = struct {
            queue: *Queue,
            config: Config,
            ready: std.atomic.Value(usize) = .init(0),
            failed: std.atomic.Value(bool) = .init(false),
            start: std.atomic.Value(bool) align(std.atomic.cache_line) = .init(false),
            stop: std.atomic.Value(bool) = .init(false),

            fn produce(self: *@This(), id: usize) void {
                pin(self.config.cpus[id]) catch {
                    self.failed.store(true, .release);
                    _ = self.ready.fetchAdd(1, .release);
                    return;
                };
                _ = self.ready.fetchAdd(1, .release);
                while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
                if (self.stop.load(.acquire)) return;
                const length = self.config.values.len / self.config.cpus.len;
                const values = self.config.values[id * length ..][0..length];
                var next: usize = 0;
                while (next < values.len) {
                    const count = if (single) 1 else @min(self.config.scratch.len, values.len - next);
                    const pushed = push(batch, self.queue, values[next..][0..count]);
                    next += pushed;
                    if (pushed == 0) {
                        if (self.stop.load(.acquire)) return;
                        std.atomic.spinLoopHint();
                    }
                }
            }
        };
        var state = State{ .queue = &queue, .config = config };
        const threads = try config.allocator.alloc(std.Thread, config.cpus.len);
        defer config.allocator.free(threads);
        var spawned: usize = 0;
        defer for (threads[0..spawned]) |thread| thread.join();
        errdefer {
            state.stop.store(true, .release);
            state.start.store(true, .release);
        }
        for (threads, 0..) |*thread, id| {
            thread.* = try std.Thread.spawn(.{}, State.produce, .{ &state, id });
            spawned += 1;
        }
        while (state.ready.load(.acquire) != config.cpus.len) std.atomic.spinLoopHint();
        if (state.failed.load(.acquire)) return error.ProducerAffinityFailed;
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        state.start.store(true, .release);
        var received: usize = 0;
        while (received < config.values.len) {
            const popped = pop(batch, &queue, if (single) config.scratch[0..1] else config.scratch);
            observer.accept(config.scratch[0..popped]);
            received += popped;
            if (popped == 0) std.atomic.spinLoopHint();
        }
        break :blk start.untilNow(config.io).raw.toNanoseconds();
    } else blk: {
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        var next: usize = 0;
        while (next < config.values.len) {
            const count = if (single) 1 else @min(config.scratch.len, config.values.len - next);
            if (push(batch, &queue, config.values[next..][0..count]) != count) return error.UnexpectedFull;
            if (pop(batch, &queue, config.scratch[0..count]) != count) return error.UnexpectedEmpty;
            observer.accept(config.scratch[0..count]);
            next += count;
        }
        break :blk start.untilNow(config.io).raw.toNanoseconds();
    };
    const total = config.values.len;
    const expected: u64 = @truncate(@as(u128, total) * (total - 1) / 2);
    if (observer.bad_order or observer.checksum != expected or queue.tryPop() != null) return error.ChecksumMismatch;
    for (config.positions) |count| if (count != per_producer) return error.ChecksumMismatch;
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
    const per_producer = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 750_000;
    const capacity = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 1024;
    const batch_size = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 64;
    const cpu_arg = args.next() orelse "24,25,26,27";
    const consumer_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 31;
    const rounds = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 9;
    if (per_producer == 0 or batch_size == 0 or rounds == 0) return error.InvalidArguments;
    var cpus: std.ArrayList(usize) = .empty;
    defer cpus.deinit(init.gpa);
    var parts = std.mem.splitScalar(u8, cpu_arg, ',');
    while (parts.next()) |part| {
        const cpu = try std.fmt.parseInt(usize, part, 10);
        if (cpu == consumer_cpu or std.mem.indexOfScalar(usize, cpus.items, cpu) != null) return error.InvalidArguments;
        try cpus.append(init.gpa, cpu);
    }
    try pin(consumer_cpu);
    const total = try std.math.mul(usize, per_producer, cpus.items.len);
    const values = try init.gpa.alloc(u64, total);
    defer init.gpa.free(values);
    for (values, 0..) |*value, index| value.* = @intCast(index);
    const actual_capacity = std.math.ceilPowerOfTwo(usize, @max(capacity, 1)) catch return error.CapacityOverflow;
    const scratch = try init.gpa.alloc(u64, @min(total, @min(batch_size, actual_capacity)));
    defer init.gpa.free(scratch);
    const positions = try init.gpa.alloc(usize, cpus.items.len);
    defer init.gpa.free(positions);
    const config = Config{ .allocator = init.gpa, .io = init.io, .values = values, .scratch = scratch, .positions = positions, .capacity = capacity, .cpus = cpus.items };
    const storage = try init.gpa.alloc(i96, try std.math.mul(usize, 4, rounds));
    defer init.gpa.free(storage);
    var samples: [4][]i96 = undefined;
    for (&samples, 0..) |*entry, index| entry.* = storage[index * rounds ..][0..rounds];
    for (0..4) |path| _ = try sample(path, config);
    std.debug.print("mpsc-batch per_producer={d} capacity={d} batch={d} effective_batch={d} producer_cpus={any} consumer_cpu={d} checksum={d}\n", .{
        per_producer, capacity, batch_size, scratch.len, cpus.items, consumer_cpu, @as(u128, total) * (total - 1) / 2,
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
    std.debug.print("mpsc implementation=scalar serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ scalar.serial_ns, scalar.parallel_ns, scalar.speedup() });
    std.debug.print("mpsc implementation=batch serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ batched.serial_ns, batched.parallel_ns, batched.speedup() });
    std.debug.print("mpsc comparison scalar_ns={d} batch_ns={d} speedup={d:.3}\n", .{ scalar.parallel_ns, batched.parallel_ns, @as(f64, @floatFromInt(scalar.parallel_ns)) / @as(f64, @floatFromInt(batched.parallel_ns)) });
}
