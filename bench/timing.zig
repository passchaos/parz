//! Paired benchmark measurements. Warm up both paths, verify every result,
//! alternate which path runs first, and report medians instead of selecting
//! a single favorable parallel run against a cold serial measurement.
const std = @import("std");

pub const Times = struct {
    serial_ns: i96,
    parallel_ns: i96,

    pub fn speedup(self: Times) f64 {
        return @as(f64, @floatFromInt(self.serial_ns)) /
            @as(f64, @floatFromInt(@max(self.parallel_ns, 1)));
    }
};

pub fn paired(
    comptime Result: type,
    allocator: std.mem.Allocator,
    io: std.Io,
    rounds: usize,
    expected: Result,
    context: anytype,
    comptime serial: anytype,
    comptime parallel: anytype,
) !Times {
    if (rounds == 0) return error.InvalidRounds;
    const serial_samples = try allocator.alloc(i96, rounds);
    defer allocator.free(serial_samples);
    const parallel_samples = try allocator.alloc(i96, rounds);
    defer allocator.free(parallel_samples);

    if (try serial(context) != expected) return error.ChecksumMismatch;
    if (try parallel(context) != expected) return error.ChecksumMismatch;

    for (0..rounds) |round| {
        for (0..2) |path| {
            const run_serial = (path == 0) == (round % 2 == 0);
            const start = std.Io.Clock.Timestamp.now(io, .awake);
            const result = if (run_serial) try serial(context) else try parallel(context);
            const elapsed = start.untilNow(io).raw.toNanoseconds();
            if (result != expected) return error.ChecksumMismatch;
            if (run_serial) serial_samples[round] = elapsed else parallel_samples[round] = elapsed;
        }
        const sample = Times{ .serial_ns = serial_samples[round], .parallel_ns = parallel_samples[round] };
        std.debug.print("sample={d} serial_ns={d} parallel_ns={d} speedup={d:.3}\n", .{
            round, sample.serial_ns, sample.parallel_ns, sample.speedup(),
        });
    }

    std.mem.sort(i96, serial_samples, {}, std.sort.asc(i96));
    std.mem.sort(i96, parallel_samples, {}, std.sort.asc(i96));
    return .{
        .serial_ns = serial_samples[rounds / 2],
        .parallel_ns = parallel_samples[rounds / 2],
    };
}
