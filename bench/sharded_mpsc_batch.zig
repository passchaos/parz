//! Fixed-CPU sharded MPSC scalar/batch comparison with per-shard FIFO checks.
const std = @import("std");
const builtin = @import("builtin");
const parz = @import("parz");
const timing = @import("timing.zig");

const shard_count = 4;
const Queue = parz.sync.ShardedMpscQueue(u64, shard_count);

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
    positions: *[shard_count]usize,
    capacity: usize,
    cpus: [shard_count]usize,
};

fn push(comptime batch: bool, queue: *Queue, shard: usize, values: []const u64) usize {
    if (batch) return queue.tryPushSlice(shard, values);
    var count: usize = 0;
    while (count < values.len) : (count += 1) {
        if (!queue.tryPush(shard, values[count])) break;
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
    positions: *[shard_count]usize,
    per_producer: usize,
    checksum: u64 = 0,
    bad_order: bool = false,

    fn accept(self: *@This(), values: []const u64) void {
        for (values) |value| {
            const shard = value / self.per_producer;
            if (shard < shard_count) {
                self.bad_order = self.bad_order or value % self.per_producer != self.positions[shard];
                self.positions[shard] += 1;
            } else self.bad_order = true;
            self.checksum +%= value;
        }
    }
};

fn run(comptime batch: bool, comptime parallel: bool, config: Config) !i96 {
    var queue = try Queue.init(config.allocator, config.capacity);
    defer queue.deinit();
    @memset(config.positions, 0);
    const per_producer = config.values.len / shard_count;
    var observer = Observer{ .positions = config.positions, .per_producer = per_producer };

    const elapsed = if (parallel) blk: {
        const State = struct {
            queue: *Queue,
            config: Config,
            ready: std.atomic.Value(usize) = .init(0),
            failed: std.atomic.Value(bool) = .init(false),
            start: std.atomic.Value(bool) align(std.atomic.cache_line) = .init(false),
            stop: std.atomic.Value(bool) = .init(false),

            fn produce(self: *@This(), shard: usize) void {
                pin(self.config.cpus[shard]) catch {
                    self.failed.store(true, .release);
                    _ = self.ready.fetchAdd(1, .release);
                    return;
                };
                _ = self.ready.fetchAdd(1, .release);
                while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
                if (self.stop.load(.acquire)) return;
                const count = self.config.values.len / shard_count;
                const values = self.config.values[shard * count ..][0..count];
                var next: usize = 0;
                while (next < values.len) {
                    const length = @min(self.config.scratch.len, values.len - next);
                    const pushed = push(batch, self.queue, shard, values[next..][0..length]);
                    next += pushed;
                    if (pushed == 0) {
                        if (self.stop.load(.acquire)) return;
                        std.atomic.spinLoopHint();
                    }
                }
            }
        };
        var state = State{ .queue = &queue, .config = config };
        var threads: [shard_count]std.Thread = undefined;
        var spawned: usize = 0;
        defer for (threads[0..spawned]) |thread| thread.join();
        errdefer {
            state.stop.store(true, .release);
            state.start.store(true, .release);
        }
        for (&threads, 0..) |*thread, shard| {
            thread.* = try std.Thread.spawn(.{}, State.produce, .{ &state, shard });
            spawned += 1;
        }
        while (state.ready.load(.acquire) != shard_count) std.atomic.spinLoopHint();
        if (state.failed.load(.acquire)) return error.ProducerAffinityFailed;
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        state.start.store(true, .release);
        var received: usize = 0;
        while (received < config.values.len) {
            const popped = pop(batch, &queue, config.scratch);
            observer.accept(config.scratch[0..popped]);
            received += popped;
            if (popped == 0) std.atomic.spinLoopHint();
        }
        break :blk start.untilNow(config.io).raw.toNanoseconds();
    } else blk: {
        var next = [_]usize{0} ** shard_count;
        var received: usize = 0;
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        while (received < config.values.len) {
            for (0..shard_count) |shard| {
                if (next[shard] == per_producer) continue;
                const length = @min(config.scratch.len, per_producer - next[shard]);
                const values = config.values[shard * per_producer + next[shard] ..][0..length];
                next[shard] += push(batch, &queue, shard, values);
            }
            const popped = pop(batch, &queue, config.scratch);
            observer.accept(config.scratch[0..popped]);
            received += popped;
            if (popped == 0) return error.NoProgress;
        }
        break :blk start.untilNow(config.io).raw.toNanoseconds();
    };

    const total = config.values.len;
    const expected: u64 = @truncate(@as(u128, total) * (total - 1) / 2);
    if (observer.bad_order or observer.checksum != expected or queue.tryPop() != null) return error.ChecksumMismatch;
    for (config.positions) |count| if (count != per_producer) return error.ChecksumMismatch;
    return elapsed;
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

    var cpus: [shard_count]usize = undefined;
    var parts = std.mem.splitScalar(u8, cpu_arg, ',');
    var cpu_count: usize = 0;
    while (parts.next()) |part| {
        if (cpu_count == cpus.len) return error.InvalidArguments;
        const cpu = try std.fmt.parseInt(usize, part, 10);
        if (cpu == consumer_cpu or std.mem.indexOfScalar(usize, cpus[0..cpu_count], cpu) != null) return error.InvalidArguments;
        cpus[cpu_count] = cpu;
        cpu_count += 1;
    }
    if (cpu_count != cpus.len) return error.InvalidArguments;
    try pin(consumer_cpu);

    const total = try std.math.mul(usize, per_producer, shard_count);
    const values = try init.gpa.alloc(u64, total);
    defer init.gpa.free(values);
    for (values, 0..) |*value, index| value.* = @intCast(index);
    const actual_capacity = std.math.ceilPowerOfTwo(usize, @max(capacity, 1)) catch return error.CapacityOverflow;
    const scratch = try init.gpa.alloc(u64, @min(total, @min(batch_size, actual_capacity)));
    defer init.gpa.free(scratch);
    var positions = [_]usize{0} ** shard_count;
    const config = Config{
        .allocator = init.gpa,
        .io = init.io,
        .values = values,
        .scratch = scratch,
        .positions = &positions,
        .capacity = capacity,
        .cpus = cpus,
    };

    const storage = try init.gpa.alloc(i96, 4 * rounds);
    defer init.gpa.free(storage);
    var samples: [4][]i96 = undefined;
    for (&samples, 0..) |*entry, index| entry.* = storage[index * rounds ..][0..rounds];
    for (0..4) |path| _ = try switch (path) {
        0 => run(false, false, config),
        1 => run(false, true, config),
        2 => run(true, false, config),
        3 => run(true, true, config),
        else => unreachable,
    };
    std.debug.print("sharded-mpsc-batch per_producer={d} capacity_per_shard={d} batch={d} effective_batch={d} producer_cpus={any} consumer_cpu={d} checksum={d}\n", .{
        per_producer, capacity, batch_size, scratch.len, cpus, consumer_cpu, @as(u128, total) * (total - 1) / 2,
    });
    for (0..rounds) |round| {
        for (0..4) |order| {
            const path = if (round % 2 == 0) order else 3 - order;
            samples[path][round] = try switch (path) {
                0 => run(false, false, config),
                1 => run(false, true, config),
                2 => run(true, false, config),
                3 => run(true, true, config),
                else => unreachable,
            };
        }
        std.debug.print("sample={d} scalar_serial_ns={d} scalar_parallel_ns={d} batch_serial_ns={d} batch_parallel_ns={d}\n", .{
            round, samples[0][round], samples[1][round], samples[2][round], samples[3][round],
        });
    }
    for (samples) |values_ns| std.mem.sort(i96, values_ns, {}, std.sort.asc(i96));
    const scalar = timing.Times{ .serial_ns = samples[0][rounds / 2], .parallel_ns = samples[1][rounds / 2] };
    const batched = timing.Times{ .serial_ns = samples[2][rounds / 2], .parallel_ns = samples[3][rounds / 2] };
    std.debug.print("sharded-mpsc implementation=scalar serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ scalar.serial_ns, scalar.parallel_ns, scalar.speedup() });
    std.debug.print("sharded-mpsc implementation=batch serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ batched.serial_ns, batched.parallel_ns, batched.speedup() });
    std.debug.print("sharded-mpsc comparison scalar_ns={d} batch_ns={d} speedup={d:.3}\n", .{
        scalar.parallel_ns, batched.parallel_ns, @as(f64, @floatFromInt(scalar.parallel_ns)) / @as(f64, @floatFromInt(batched.parallel_ns)),
    });
}
