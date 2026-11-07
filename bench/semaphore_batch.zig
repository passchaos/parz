//! Fixed-CPU scalar/batch semaphore transfer comparison.
const std = @import("std");
const builtin = @import("builtin");
const parz = @import("parz");
const timing = @import("timing.zig");

fn pin(cpu: usize) !void {
    if (builtin.os.tag != .linux) return error.AffinityUnsupported;
    var set = std.mem.zeroes(std.os.linux.cpu_set_t);
    const bits = @bitSizeOf(@TypeOf(set[0]));
    if (cpu >= set.len * bits) return error.InvalidCpu;
    set[cpu / bits] |= @as(@TypeOf(set[0]), 1) << @intCast(cpu % bits);
    try std.os.linux.sched_setaffinity(0, &set);
}

const Config = struct {
    io: std.Io,
    total: usize,
    batch_size: usize,
    producer_cpu: usize,
};

fn run(comptime batch: bool, comptime parallel: bool, comptime single: bool, config: Config) !i96 {
    var semaphore = parz.sync.Semaphore{};
    const elapsed = if (parallel) blk: {
        const State = struct {
            semaphore: *parz.sync.Semaphore,
            config: Config,
            ready: std.atomic.Value(bool) = .init(false),
            failed: std.atomic.Value(bool) = .init(false),
            start: std.atomic.Value(bool) align(std.atomic.cache_line) = .init(false),

            fn produce(self: *@This()) void {
                pin(self.config.producer_cpu) catch {
                    self.failed.store(true, .release);
                    self.ready.store(true, .release);
                    return;
                };
                self.ready.store(true, .release);
                while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
                if (batch) {
                    if (comptime single) {
                        for (0..self.config.total) |_| self.semaphore.postMany(self.config.io, 1);
                    } else {
                        var posted: usize = 0;
                        while (posted < self.config.total) {
                            const count = @min(self.config.batch_size, self.config.total - posted);
                            self.semaphore.postMany(self.config.io, count);
                            posted += count;
                        }
                    }
                } else for (0..self.config.total) |_| self.semaphore.post(self.config.io);
            }
        };
        var state = State{ .semaphore = &semaphore, .config = config };
        const producer = try std.Thread.spawn(.{}, State.produce, .{&state});
        var joined = false;
        defer if (!joined) producer.join();
        while (!state.ready.load(.acquire)) std.atomic.spinLoopHint();
        if (state.failed.load(.acquire)) return error.ProducerAffinityFailed;
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        state.start.store(true, .release);
        if (batch) {
            if (comptime single) {
                for (0..config.total) |_| try semaphore.waitMany(config.io, 1);
            } else {
                var consumed: usize = 0;
                while (consumed < config.total) {
                    const count = @min(config.batch_size, config.total - consumed);
                    try semaphore.waitMany(config.io, count);
                    consumed += count;
                }
            }
        } else for (0..config.total) |_| try semaphore.wait(config.io);
        producer.join();
        joined = true;
        break :blk start.untilNow(config.io).raw.toNanoseconds();
    } else blk: {
        const start = std.Io.Clock.Timestamp.now(config.io, .awake);
        if (batch) {
            if (comptime single) {
                for (0..config.total) |_| semaphore.postMany(config.io, 1);
                for (0..config.total) |_| try semaphore.waitMany(config.io, 1);
            } else {
                var offset: usize = 0;
                while (offset < config.total) {
                    const count = @min(config.batch_size, config.total - offset);
                    semaphore.postMany(config.io, count);
                    offset += count;
                }
                offset = 0;
                while (offset < config.total) {
                    const count = @min(config.batch_size, config.total - offset);
                    try semaphore.waitMany(config.io, count);
                    offset += count;
                }
            }
        } else {
            for (0..config.total) |_| semaphore.post(config.io);
            for (0..config.total) |_| try semaphore.wait(config.io);
        }
        break :blk start.untilNow(config.io).raw.toNanoseconds();
    };
    if (semaphore.inner.permits != 0) return error.PermitMismatch;
    return elapsed;
}

fn sample(path: usize, config: Config) !i96 {
    if (config.batch_size == 1) return switch (path) {
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
    const total = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 1_000_000;
    const batch_size = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 64;
    const producer_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 24;
    const consumer_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 26;
    const rounds = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 9;
    if (total == 0 or batch_size == 0 or producer_cpu == consumer_cpu or rounds == 0) return error.InvalidArguments;
    try pin(consumer_cpu);
    const config = Config{ .io = init.io, .total = total, .batch_size = batch_size, .producer_cpu = producer_cpu };

    const storage = try init.gpa.alloc(i96, 4 * rounds);
    defer init.gpa.free(storage);
    var samples: [4][]i96 = undefined;
    for (&samples, 0..) |*entry, index| entry.* = storage[index * rounds ..][0..rounds];
    for (0..4) |path| _ = try sample(path, config);
    std.debug.print("semaphore-batch total={d} batch={d} producer_cpu={d} consumer_cpu={d} completed={d}\n", .{
        total, batch_size, producer_cpu, consumer_cpu, total,
    });
    for (0..rounds) |round| {
        for (0..4) |order| {
            const path = if (round % 2 == 0) order else 3 - order;
            samples[path][round] = try sample(path, config);
        }
        std.debug.print("sample={d} scalar_serial_ns={d} scalar_parallel_ns={d} batch_serial_ns={d} batch_parallel_ns={d}\n", .{
            round, samples[0][round], samples[1][round], samples[2][round], samples[3][round],
        });
    }
    for (samples) |values_ns| std.mem.sort(i96, values_ns, {}, std.sort.asc(i96));
    const scalar = timing.Times{ .serial_ns = samples[0][rounds / 2], .parallel_ns = samples[1][rounds / 2] };
    const batched = timing.Times{ .serial_ns = samples[2][rounds / 2], .parallel_ns = samples[3][rounds / 2] };
    std.debug.print("semaphore implementation=scalar serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ scalar.serial_ns, scalar.parallel_ns, scalar.speedup() });
    std.debug.print("semaphore implementation=batch serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ batched.serial_ns, batched.parallel_ns, batched.speedup() });
    std.debug.print("semaphore comparison scalar_ns={d} batch_ns={d} speedup={d:.3}\n", .{
        scalar.parallel_ns, batched.parallel_ns, @as(f64, @floatFromInt(scalar.parallel_ns)) / @as(f64, @floatFromInt(batched.parallel_ns)),
    });
}
