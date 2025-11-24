const std = @import("std");

/// Icon size/suffix combinations to search
const icon_sizes = [_]struct { size: []const u8, suffix: []const u8 }{
    .{ .size = "48x48", .suffix = ".png" },
    .{ .size = "48x48", .suffix = ".svg" },
    .{ .size = "64x64", .suffix = ".png" },
    .{ .size = "64x64", .suffix = ".svg" },
    .{ .size = "32x32", .suffix = ".png" },
    .{ .size = "32x32", .suffix = ".svg" },
    .{ .size = "128x128", .suffix = ".png" },
    .{ .size = "128x128", .suffix = ".svg" },
    .{ .size = "256x256", .suffix = ".png" },
    .{ .size = "256x256", .suffix = ".svg" },
    .{ .size = "scalable", .suffix = ".svg" },
};

/// Resolve an icon name to an absolute file path
/// data_dir is the XDG data directory where the .desktop was found (e.g., "/usr/share" or "~/.local/share")
/// Returns the path if found, empty string if not
pub fn resolveIconPath(allocator: std.mem.Allocator, icon_name: []const u8, data_dir: []const u8) []const u8 {
    if (icon_name.len == 0) return "";

    // If already an absolute path, check if it exists
    if (std.mem.startsWith(u8, icon_name, "/")) {
        if (fileExists(icon_name)) {
            std.log.debug("Icon found (absolute): {s}", .{icon_name});
            return allocator.dupe(u8, icon_name) catch return "";
        }
        return "";
    }

    var path_buf: [512]u8 = undefined;

    // Get home directory for user icons fallback
    const home = std.posix.getenv("HOME") orelse "/home";
    var home_data_buf: [256]u8 = undefined;
    const home_data = std.fmt.bufPrint(&home_data_buf, "{s}/.local/share", .{home}) catch "/home/.local/share";

    // Determine primary and fallback icon directories based on .desktop source
    const primary_base = data_dir;
    const fallback_base = if (std.mem.eql(u8, data_dir, "/usr/share") or std.mem.eql(u8, data_dir, "/usr/local/share"))
        home_data
    else
        @as([]const u8, "/usr/share");

    // Search primary directory first, then fallback
    const bases = [_][]const u8{ primary_base, fallback_base };
    for (bases) |base| {
        for (icon_sizes) |size| {
            const path = std.fmt.bufPrint(&path_buf, "{s}/icons/hicolor/{s}/apps/{s}{s}", .{
                base,
                size.size,
                icon_name,
                size.suffix,
            }) catch continue;

            if (fileExists(path)) {
                std.log.debug("Icon found: {s} -> {s}", .{ icon_name, path });
                return allocator.dupe(u8, path) catch return "";
            }
        }
    }

    // Try pixmaps (system only)
    for ([_][]const u8{ ".png", ".svg" }) |suffix| {
        const pixmap_path = std.fmt.bufPrint(&path_buf, "/usr/share/pixmaps/{s}{s}", .{ icon_name, suffix }) catch continue;
        if (fileExists(pixmap_path)) {
            std.log.debug("Icon found (pixmaps): {s} -> {s}", .{ icon_name, pixmap_path });
            return allocator.dupe(u8, pixmap_path) catch return "";
        }
    }

    // Try without extension (some icons already have extension in .desktop)
    if (std.mem.endsWith(u8, icon_name, ".png") or std.mem.endsWith(u8, icon_name, ".svg")) {
        const pixmap_path = std.fmt.bufPrint(&path_buf, "/usr/share/pixmaps/{s}", .{icon_name}) catch return "";
        if (fileExists(pixmap_path)) {
            std.log.debug("Icon found (with ext): {s} -> {s}", .{ icon_name, pixmap_path });
            return allocator.dupe(u8, pixmap_path) catch return "";
        }
    }

    std.log.debug("Icon not found: {s}", .{icon_name});
    return "";
}

fn fileExists(path: []const u8) bool {
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    file.close();
    return true;
}
