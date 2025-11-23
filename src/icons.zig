const std = @import("std");

/// Icon search directories in priority order
const icon_dirs = [_]struct { base: []const u8, suffix: []const u8 }{
    .{ .base = "/usr/share/icons/hicolor/48x48/apps/", .suffix = ".png" },
    .{ .base = "/usr/share/icons/hicolor/48x48/apps/", .suffix = ".svg" },
    .{ .base = "/usr/share/icons/hicolor/64x64/apps/", .suffix = ".png" },
    .{ .base = "/usr/share/icons/hicolor/64x64/apps/", .suffix = ".svg" },
    .{ .base = "/usr/share/icons/hicolor/32x32/apps/", .suffix = ".png" },
    .{ .base = "/usr/share/icons/hicolor/32x32/apps/", .suffix = ".svg" },
    .{ .base = "/usr/share/icons/hicolor/128x128/apps/", .suffix = ".png" },
    .{ .base = "/usr/share/icons/hicolor/128x128/apps/", .suffix = ".svg" },
    .{ .base = "/usr/share/icons/hicolor/scalable/apps/", .suffix = ".svg" },
    .{ .base = "/usr/share/pixmaps/", .suffix = ".png" },
    .{ .base = "/usr/share/pixmaps/", .suffix = ".svg" },
};

/// Resolve an icon name to an absolute file path
/// Returns the path if found, empty string if not
pub fn resolveIconPath(allocator: std.mem.Allocator, icon_name: []const u8) []const u8 {
    if (icon_name.len == 0) return "";

    // If already an absolute path, check if it exists
    if (std.mem.startsWith(u8, icon_name, "/")) {
        if (fileExists(icon_name)) {
            std.log.debug("Icon found (absolute): {s}", .{icon_name});
            return allocator.dupe(u8, icon_name) catch return "";
        }
        return "";
    }

    // Search through icon directories
    var path_buf: [512]u8 = undefined;

    for (icon_dirs) |dir| {
        const path = std.fmt.bufPrint(&path_buf, "{s}{s}{s}", .{
            dir.base,
            icon_name,
            dir.suffix,
        }) catch continue;

        if (fileExists(path)) {
            std.log.debug("Icon found: {s} -> {s}", .{ icon_name, path });
            return allocator.dupe(u8, path) catch return "";
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
