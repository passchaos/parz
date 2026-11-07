//! Cooperative cancellation for flat parallel loops.
//!
//! The token is a single atomic flag. Nonempty flat calls check it at chunk
//! entry/exit boundaries, every 4096 items in index-based loops, and before
//! successful completion. Cancellation is cooperative: a call drains all
//! started lane futures before returning, so caller-owned input and scratch
//! storage can be released after the call unwinds.

const std = @import("std");

pub const CancelToken = struct {
    flag: std.atomic.Value(bool) = .init(false),

    pub fn cancel(self: *CancelToken) void {
        self.flag.store(true, .release);
    }

    pub fn isCancelled(self: *const CancelToken) bool {
        return self.flag.load(.acquire);
    }

    /// Reuse a token after a cancelled call has fully unwound.
    pub fn reset(self: *CancelToken) void {
        self.flag.store(false, .release);
    }
};

test "cancel token transitions" {
    var token = CancelToken{};
    try std.testing.expect(!token.isCancelled());
    token.cancel();
    try std.testing.expect(token.isCancelled());
    token.reset();
    try std.testing.expect(!token.isCancelled());
}
