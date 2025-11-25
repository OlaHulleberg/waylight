const std = @import("std");
const icons = @import("../../icons.zig");

/// Parsed data from a .desktop file
pub const DesktopData = struct {
    name: []const u8,
    exec: []const u8,
    icon: []const u8,
    icon_path: []const u8,
    comment: []const u8,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *DesktopData) void {
        self.arena.deinit();
    }
};

/// Parse a .desktop file from a directory
pub fn parseFromDir(dir: std.fs.Dir, filename: []const u8, data_dir: []const u8) ?DesktopData {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    // Read entire file
    const max_size = 64 * 1024; // 64KB max for desktop files
    const content = dir.readFileAlloc(alloc, filename, max_size) catch return null;

    return parseContent(alloc, content, data_dir, arena);
}

/// Parse a .desktop file from an absolute path
pub fn parseFromPath(path: []const u8) ?DesktopData {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer arena.deinit();
    const alloc = arena.allocator();

    // Read entire file
    const max_size = 64 * 1024;
    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();

    const content = file.readToEndAlloc(alloc, max_size) catch return null;

    // Extract data_dir from path (e.g., "/usr/share/applications/foo.desktop" -> "/usr/share")
    const data_dir = extractDataDir(path);

    return parseContent(alloc, content, data_dir, arena);
}

/// Extract data directory from a .desktop file path
pub fn extractDataDir(path: []const u8) []const u8 {
    return if (std.mem.lastIndexOf(u8, path, "/applications/")) |idx|
        path[0..idx]
    else
        "/usr/share";
}

fn parseContent(alloc: std.mem.Allocator, content: []const u8, data_dir: []const u8, arena: std.heap.ArenaAllocator) ?DesktopData {
    var name: []const u8 = "";
    var exec: []const u8 = "";
    var icon: []const u8 = "";
    var comment: []const u8 = "";
    var no_display = false;
    var hidden = false;
    var in_desktop_entry = false;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const trimmed = std.mem.trim(u8, raw_line, " \t\r");

        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Section header
        if (trimmed[0] == '[') {
            in_desktop_entry = std.mem.eql(u8, trimmed, "[Desktop Entry]");
            continue;
        }

        if (!in_desktop_entry) continue;

        // Parse key=value
        if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
            const key = trimmed[0..eq_pos];
            const value = trimmed[eq_pos + 1 ..];

            if (std.mem.eql(u8, key, "Name") and name.len == 0) {
                name = alloc.dupe(u8, value) catch return null;
            } else if (std.mem.eql(u8, key, "Exec")) {
                exec = alloc.dupe(u8, value) catch return null;
            } else if (std.mem.eql(u8, key, "Icon")) {
                icon = alloc.dupe(u8, value) catch return null;
            } else if (std.mem.eql(u8, key, "Comment") and comment.len == 0) {
                comment = alloc.dupe(u8, value) catch return null;
            } else if (std.mem.eql(u8, key, "NoDisplay")) {
                no_display = std.mem.eql(u8, value, "true");
            } else if (std.mem.eql(u8, key, "Hidden")) {
                hidden = std.mem.eql(u8, value, "true");
            }
        }
    }

    // Skip entries that shouldn't be displayed
    if (no_display or hidden or name.len == 0) {
        return null;
    }

    // Resolve icon path
    const icon_path = icons.resolveIconPath(alloc, icon, data_dir);

    return DesktopData{
        .name = name,
        .exec = exec,
        .icon = icon,
        .icon_path = icon_path,
        .comment = comment,
        .arena = arena,
    };
}
