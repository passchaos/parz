//! Fixed-CPU BlockingQueue scalar/batch comparison with post-timing checks.
const std = @import("std");
const builtin = @import("builtin");
const parz = @import("parz");
const timing = @import("timing.zig");

const producers = 2;
const consumers = 2;
const Queue = parz.sync.BlockingQueue(u64);

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
    input: []const u64,
    output: []u64,
    seen: []bool,
    capacity: usize,
    batch_size: usize,
    producer_cpus: [producers]usize,
    consumer_cpus: [consumers]usize,
};

fn check(config: Config, queue: *Queue) !void {
    @memset(config.seen, false);
    var checksum: u64 = 0;
    for (config.output) |value| {
        if (value >= config.seen.len or config.seen[value]) return error.ChecksumMismatch;
        config.seen[value] = true;
        checksum +%= value;
    }
    const expected: u64 = @truncate(@as(u128, config.output.len) * (config.output.len - 1) / 2);
    if (checksum != expected or queue.len(config.io) != 0) return error.ChecksumMismatch;
}

fn run(comptime batch: bool, comptime parallel: bool, config: Config) !i96 {
    var queue = try Queue.init(config.allocator, config.capacity);
    defer queue.deinit();

    const elapsed = if (parallel) blk: {
        const State = struct {
            queue: *Queue,
            config: Config,
            ready: std.atomic.Value(usize) = .init(0),
            failed: std.atomic.Value(bool) = .init(false),
            start: std.atomic.Value(bool) align(std.atomic.cache_line) = .init(false),
            stop: std.atomic.Value(bool) = .init(false),

            fn produce(self: *@This(), id: usize) void {
                pin(self.config.producer_cpus[id]) catch {
                    self.failed.store(true, .release);
                    _ = self.ready.fetchAdd(1, .release);
                    return;
                };
                _ = self.ready.fetchAdd(1, .release);
                while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
                if (self.stop.load(.acquire)) return;
                const count = self.config.input.len / producers;
                const values = self.config.input[id * count ..][0..count];
                if (batch) {
                    var next: usize = 0;
                    while (next < values.len) {
                        const length = @min(self.config.batch_size, values.len - next);
                        next += self.queue.putSlice(self.config.io, values[next..][0..length]) catch return;
                    }
                } else {
                    for (values) |value| self.queue.put(self.config.io, value) catch return;
                }
            }

            fn consume(self: *@This(), id: usize) void {
                pin(self.config.consumer_cpus[id]) catch {
                    self.failed.store(true, .release);
                    _ = self.ready.fetchAdd(1, .release);
                    return;
                };
                _ = self.ready.fetchAdd(1, .release);
                while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
                if (self.stop.load(.acquire)) return;
                const count = self.config.output.len / consumers;
                const output = self.config.output[id * count ..][0..count];
                if (batch) {
                    var next: usize = 0;
                    while (next < output.len) {
                        const length = @min(self.config.batch_size, output.len - next);
                        next += self.queue.getSlice(self.config.io, output[next..][0..length]) catch return;
                    }
                } else {
                    for (output) |*value| value.* = self.queue.get(self.config.io) catch return;
                }
            }
        };

        var state = State{ .queue = &queue, .config = config };
        var producer_threads: [producers]std.Thread = undefined;
        var consumer_threads: [consumers]std.Thread = undefined;
        var producers_spawned: usize = 0;
        var consumers_spawned: usize = 0;
        defer for (producer_threads[0..producers_spawned]) |thread| thread.join();
        defer for (consumer_threads[0..consumers_spawned]) |thread| thread.join();
        errdefer {
            state.stop.store(true, .release);
            state.start.store(true, .release);
        }
        for (&producer_threads, 0..) |*thread, id| {
            thread.* = try std.Thread.spawn(.{}, State.produce, .{ &state, id });
            producers_spawned += 1;
        }
        for (&consumer_threads, 0..) |*thread, id| {
            thread.* = try std.Thread.spawn(.{}, State.consume, .{ &state, id });
            consumers_spawned += 1;
        }
        while (state.ready.load(.acquire) != producers + consumers) std.atomic.spinLoopHint();
        if (state.failed.load(.acquire)) return error.AffinityFailed;
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        state.start.store(true, .release);
        for (producer_threads) |thread| thread.join();
        producers_spawned = 0;
        for (consumer_threads) |thread| thread.join();
        consumers_spawned = 0;
        break :blk start.untilNow(config.io).raw.toNanoseconds();
    } else blk: {
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        var next: usize = 0;
        while (next < config.input.len) {
            const length = @min(if (batch) config.batch_size else 1, config.input.len - next);
            const pushed = if (batch)
                queue.tryPutSlice(config.io, config.input[next..][0..length])
            else
                @intFromBool(queue.tryPut(config.io, config.input[next]));
            if (pushed == 0) return error.UnexpectedFull;
            const popped = if (batch)
                queue.tryGetSlice(config.io, config.output[next..][0..pushed])
            else blk_pop: {
                config.output[next] = queue.tryGet(config.io) orelse return error.UnexpectedEmpty;
                break :blk_pop 1;
            };
            if (popped != pushed) return error.UnexpectedEmpty;
            next += popped;
        }
        break :blk start.untilNow(config.io).raw.toNanoseconds();
    };
    try check(config, &queue);
    return elapsed;
}

fn parseCpuPair(value: []const u8, forbidden: []const usize) ![2]usize {
    var result: [2]usize = undefined;
    var parts = std.mem.splitScalar(u8, value, ',');
    var count: usize = 0;
    while (parts.next()) |part| {
        if (count == result.len) return error.InvalidArguments;
        const cpu = try std.fmt.parseInt(usize, part, 10);
        if (std.mem.indexOfScalar(usize, forbidden, cpu) != null or
            std.mem.indexOfScalar(usize, result[0..count], cpu) != null) return error.InvalidArguments;
        result[count] = cpu;
        count += 1;
    }
    if (count != result.len) return error.InvalidArguments;
    return result;
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const per_producer = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 500_000;
    const capacity = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 1024;
    const batch_size = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 64;
    const producer_cpus = try parseCpuPair(args.next() orelse "24,25", &.{});
    const consumer_cpus = try parseCpuPair(args.next() orelse "26,27", &producer_cpus);
    const serial_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 31;
    const rounds = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 9;
    if (per_producer == 0 or batch_size == 0 or rounds == 0 or
        std.mem.indexOfScalar(usize, &producer_cpus, serial_cpu) != null or
        std.mem.indexOfScalar(usize, &consumer_cpus, serial_cpu) != null) return error.InvalidArguments;
    try pin(serial_cpu);

    const total = try std.math.mul(usize, per_producer, producers);
    const input = try init.gpa.alloc(u64, total);
    defer init.gpa.free(input);
    const output = try init.gpa.alloc(u64, total);
    defer init.gpa.free(output);
    const seen = try init.gpa.alloc(bool, total);
    defer init.gpa.free(seen);
    for (input, 0..) |*value, index| value.* = @intCast(index);
    const config = Config{
        .allocator = init.gpa,
        .io = init.io,
        .input = input,
        .output = output,
        .seen = seen,
        .capacity = capacity,
        .batch_size = batch_size,
        .producer_cpus = producer_cpus,
        .consumer_cpus = consumer_cpus,
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
    std.debug.print("blocking-batch per_producer={d} capacity={d} batch={d} producer_cpus={any} consumer_cpus={any} serial_cpu={d} checksum={d}\n", .{
        per_producer, capacity, batch_size, producer_cpus, consumer_cpus, serial_cpu, @as(u128, total) * (total - 1) / 2,
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
    std.debug.print("blocking implementation=scalar serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ scalar.serial_ns, scalar.parallel_ns, scalar.speedup() });
    std.debug.print("blocking implementation=batch serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ batched.serial_ns, batched.parallel_ns, batched.speedup() });
    std.debug.print("blocking comparison scalar_ns={d} batch_ns={d} speedup={d:.3}\n", .{
        scalar.parallel_ns, batched.parallel_ns, @as(f64, @floatFromInt(scalar.parallel_ns)) / @as(f64, @floatFromInt(batched.parallel_ns)),
    });
}
