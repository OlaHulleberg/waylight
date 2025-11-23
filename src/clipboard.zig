const std = @import("std");

/// Copy text to clipboard using wl-copy (Wayland)
pub fn copy(allocator: std.mem.Allocator, text: []const u8) !void {
    if (text.len == 0) return;

    const argv = [_][]const u8{
        "wl-copy",
        text,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();

    const term = try child.wait();

    if (term.Exited != 0) {
        std.log.err("wl-copy failed with exit code: {}", .{term.Exited});
        return error.ClipboardFailed;
    }
}
