const std = @import("std");
const parz = @import("parz");
// Inspect the compiler's actual layout before changing scheduler padding.
fn report(comptime Ctx: type) void {
    const W = parz.Worker(Ctx);
    std.debug.print("ctx_bytes={d} worker_bytes={d} worker_align={d} cache_unit={d}\n", .{ @sizeOf(Ctx), @sizeOf(W), @alignOf(W), std.atomic.cache_line });
    inline for (@typeInfo(W).@"struct".fields) |field| {
        std.debug.print("field={s} offset={d} bytes={d}\n", .{ field.name, @offsetOf(W, field.name), @sizeOf(field.type) });
    }
}
pub fn main() void {
    report(void);
    report(struct { words: [8]u64 });
    report(struct { value: u64 align(16) });
    report(struct { value: u64 align(64) });
    report(struct { value: u64 align(256) });
}
