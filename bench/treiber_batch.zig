//! Fixed-CPU TreiberStack scalar/batch comparison with post-timing checks.
const std = @import("std");
const builtin = @import("builtin");
const parz = @import("parz");
const timing = @import("timing.zig");

const producers = 4;

fn Benchmark(comptime StackType: type, comptime tracked: bool) type {
    return struct {
        const Stack = StackType;
        const Node = Stack.Node;

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
            nodes: []Node,
            output: []u64,
            seen: []bool,
            batch_size: usize,
            cpus: [producers]usize,
        };

        fn check(config: Config, stack: *Stack) !void {
            @memset(config.seen, false);
            var checksum: u64 = 0;
            for (config.output) |value| {
                if (value >= config.seen.len or config.seen[value]) return error.ChecksumMismatch;
                config.seen[value] = true;
                checksum +%= value;
            }
            const expected: u64 = @truncate(@as(u128, config.output.len) * (config.output.len - 1) / 2);
            if (checksum != expected or !stack.isEmpty()) return error.ChecksumMismatch;
            if (comptime tracked) {
                if (stack.len() != 0) return error.ChecksumMismatch;
            }
        }

        fn run(comptime batch: bool, comptime parallel: bool, comptime single: bool, config: Config) !i96 {
            var stack = Stack{};
            const elapsed = if (parallel) blk: {
                const State = struct {
                    stack: *Stack,
                    config: Config,
                    ready: std.atomic.Value(usize) = .init(0),
                    failed: std.atomic.Value(bool) = .init(false),
                    start: std.atomic.Value(bool) align(std.atomic.cache_line) = .init(false),
                    stop: std.atomic.Value(bool) = .init(false),

                    fn produce(self: *@This(), producer: usize) void {
                        pin(self.config.cpus[producer]) catch {
                            self.failed.store(true, .release);
                            _ = self.ready.fetchAdd(1, .release);
                            return;
                        };
                        _ = self.ready.fetchAdd(1, .release);
                        while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
                        if (self.stop.load(.acquire)) return;
                        const count = self.config.nodes.len / producers;
                        const nodes = self.config.nodes[producer * count ..][0..count];
                        if (batch) {
                            if (comptime single) {
                                for (nodes, 0..) |*node, index| {
                                    node.* = .{ .value = @as(u64, @intCast(producer * count + index)) };
                                    self.stack.pushSlice(nodes[index..][0..1]);
                                }
                            } else {
                                var next: usize = 0;
                                while (next < nodes.len) {
                                    const length = @min(self.config.batch_size, nodes.len - next);
                                    for (nodes[next..][0..length], next..) |*node, index| {
                                        node.* = .{ .value = @as(u64, @intCast(producer * count + index)) };
                                    }
                                    self.stack.pushSlice(nodes[next..][0..length]);
                                    next += length;
                                }
                            }
                        } else {
                            for (nodes, 0..) |*node, index| {
                                node.* = .{ .value = @as(u64, @intCast(producer * count + index)) };
                                self.stack.push(node);
                            }
                        }
                    }
                };
                var state = State{ .stack = &stack, .config = config };
                var threads: [producers]std.Thread = undefined;
                var spawned: usize = 0;
                defer for (threads[0..spawned]) |thread| thread.join();
                errdefer {
                    state.stop.store(true, .release);
                    state.start.store(true, .release);
                }
                for (&threads, 0..) |*thread, producer| {
                    thread.* = try std.Thread.spawn(.{}, State.produce, .{ &state, producer });
                    spawned += 1;
                }
                while (state.ready.load(.acquire) != producers) std.atomic.spinLoopHint();
                if (state.failed.load(.acquire)) return error.ProducerAffinityFailed;
                const start = std.Io.Clock.Timestamp.now(config.io, .awake);
                state.start.store(true, .release);
                var received: usize = 0;
                var popped: [256]*Node = undefined;
                while (received < config.output.len) {
                    const count: usize = if (batch)
                        stack.popSlice(popped[0..if (comptime single) 1 else @min(config.batch_size, config.output.len - received)])
                    else blk_pop: {
                        popped[0] = stack.pop() orelse {
                            std.atomic.spinLoopHint();
                            break :blk_pop 0;
                        };
                        break :blk_pop 1;
                    };
                    for (popped[0..count]) |node| {
                        config.output[received] = node.value;
                        received += 1;
                    }
                    if (count == 0) std.atomic.spinLoopHint();
                }
                for (threads) |thread| thread.join();
                spawned = 0;
                break :blk start.untilNow(config.io).raw.toNanoseconds();
            } else blk: {
                const start = std.Io.Clock.Timestamp.now(config.io, .awake);
                if (batch) {
                    if (comptime single) {
                        for (config.nodes, 0..) |*node, index| {
                            node.* = .{ .value = @intCast(index) };
                            stack.pushSlice(config.nodes[index..][0..1]);
                        }
                    } else {
                        var next: usize = 0;
                        while (next < config.nodes.len) {
                            const length = @min(config.batch_size, config.nodes.len - next);
                            for (config.nodes[next..][0..length], next..) |*node, index| node.* = .{ .value = @intCast(index) };
                            stack.pushSlice(config.nodes[next..][0..length]);
                            next += length;
                        }
                    }
                    var received: usize = 0;
                    var popped: [256]*Node = undefined;
                    while (received < config.output.len) {
                        const count = stack.popSlice(popped[0..if (comptime single) 1 else @min(config.batch_size, config.output.len - received)]);
                        for (popped[0..count]) |node| {
                            config.output[received] = node.value;
                            received += 1;
                        }
                    }
                } else {
                    for (config.nodes, 0..) |*node, index| {
                        node.* = .{ .value = @intCast(index) };
                        stack.push(node);
                    }
                    for (config.output) |*value| value.* = stack.pop().?.value;
                }
                break :blk start.untilNow(config.io).raw.toNanoseconds();
            };
            try check(config, &stack);
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

        fn parseCpus(value: []const u8, consumer_cpu: usize) ![producers]usize {
            var result: [producers]usize = undefined;
            var parts = std.mem.splitScalar(u8, value, ',');
            var count: usize = 0;
            while (parts.next()) |part| {
                if (count == result.len) return error.InvalidArguments;
                const cpu = try std.fmt.parseInt(usize, part, 10);
                if (cpu == consumer_cpu or std.mem.indexOfScalar(usize, result[0..count], cpu) != null) return error.InvalidArguments;
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
            const per_producer = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 250_000;
            const batch_size = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 64;
            const cpu_arg = args.next() orelse "24,25,26,27";
            const consumer_cpu = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 31;
            const rounds = if (args.next()) |arg| try std.fmt.parseInt(usize, arg, 10) else 9;
            if (per_producer == 0 or batch_size == 0 or batch_size > 256 or rounds == 0) return error.InvalidArguments;
            const cpus = try parseCpus(cpu_arg, consumer_cpu);
            try pin(consumer_cpu);

            const total = try std.math.mul(usize, per_producer, producers);
            const nodes = try init.gpa.alloc(Node, total);
            defer init.gpa.free(nodes);
            const output = try init.gpa.alloc(u64, total);
            defer init.gpa.free(output);
            const seen = try init.gpa.alloc(bool, total);
            defer init.gpa.free(seen);
            const config = Config{ .io = init.io, .nodes = nodes, .output = output, .seen = seen, .batch_size = batch_size, .cpus = cpus };

            const storage = try init.gpa.alloc(i96, 4 * rounds);
            defer init.gpa.free(storage);
            var samples: [4][]i96 = undefined;
            for (&samples, 0..) |*entry, index| entry.* = storage[index * rounds ..][0..rounds];
            for (0..4) |path| _ = try sample(path, config);
            std.debug.print("treiber-batch per_producer={d} batch={d} producer_cpus={any} consumer_cpu={d} checksum={d}\n", .{
                per_producer, batch_size, cpus, consumer_cpu, @as(u128, total) * (total - 1) / 2,
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
            std.debug.print("treiber implementation=scalar serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ scalar.serial_ns, scalar.parallel_ns, scalar.speedup() });
            std.debug.print("treiber implementation=batch serial_ns={d} parallel_ns={d} speedup={d:.3} statistic=median\n", .{ batched.serial_ns, batched.parallel_ns, batched.speedup() });
            std.debug.print("treiber comparison scalar_ns={d} batch_ns={d} speedup={d:.3}\n", .{
                scalar.parallel_ns, batched.parallel_ns, @as(f64, @floatFromInt(scalar.parallel_ns)) / @as(f64, @floatFromInt(batched.parallel_ns)),
            });
        }
    };
}

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    var uncounted = false;
    while (args.next()) |arg| if (std.mem.eql(u8, arg, "uncounted")) {
        uncounted = true;
    };
    if (uncounted) {
        if (comptime @hasDecl(parz.sync, "UncountedTreiberStack")) {
            return Benchmark(parz.sync.UncountedTreiberStack(u64), false).main(init);
        }
        // A pre-feature core uses its counted stack as the baseline for this
        // otherwise identical harness and command line.
        return Benchmark(parz.sync.TreiberStack(u64), true).main(init);
    }
    return Benchmark(parz.sync.TreiberStack(u64), true).main(init);
}
