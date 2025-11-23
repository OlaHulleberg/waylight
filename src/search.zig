const std = @import("std");
const icons = @import("icons.zig");

/// Desktop entry parsed from .desktop file
pub const DesktopEntry = struct {
    name: []const u8,
    exec: []const u8,
    icon: []const u8,
    icon_path: []const u8, // Resolved absolute path to icon file
    comment: []const u8,
    // Keep track of allocations for cleanup
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *DesktopEntry) void {
        self.arena.deinit();
    }
};

/// Search engine for desktop applications
pub const Search = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(DesktopEntry),
    loaded: bool,

    pub fn init(allocator: std.mem.Allocator) Search {
        return Search{
            .allocator = allocator,
            .entries = .{},
            .loaded = false,
        };
    }

    pub fn deinit(self: *Search) void {
        for (self.entries.items) |*entry| {
            entry.deinit();
        }
        self.entries.deinit(self.allocator);
    }

    /// Load all desktop entries from standard locations
    pub fn loadEntries(self: *Search) !void {
        if (self.loaded) return;

        const app_dirs = [_][]const u8{
            "/usr/share/applications",
            "/usr/local/share/applications",
        };

        // Also check XDG_DATA_HOME (~/.local/share/applications)
        const home = std.posix.getenv("HOME") orelse "/home";
        var home_apps_buf: [512]u8 = undefined;
        const home_apps = std.fmt.bufPrint(&home_apps_buf, "{s}/.local/share/applications", .{home}) catch "/home/.local/share/applications";

        for (app_dirs) |dir| {
            self.loadFromDir(dir) catch |err| {
                std.log.debug("Could not load from {s}: {}", .{ dir, err });
            };
        }

        self.loadFromDir(home_apps) catch |err| {
            std.log.debug("Could not load from {s}: {}", .{ home_apps, err });
        };

        self.loaded = true;
    }

    fn loadFromDir(self: *Search, dir_path: []const u8) !void {
        var dir = try std.fs.openDirAbsolute(dir_path, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".desktop")) {
                if (self.parseDesktopFile(dir, entry.name)) |desktop_entry| {
                    try self.entries.append(self.allocator, desktop_entry);
                } else |err| {
                    std.log.debug("Failed to parse {s}: {}", .{ entry.name, err });
                }
            }
        }
    }

    fn parseDesktopFile(self: *Search, dir: std.fs.Dir, filename: []const u8) !DesktopEntry {
        _ = self;

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer arena.deinit();
        const alloc = arena.allocator();

        // Read entire file
        const max_size = 64 * 1024; // 64KB max for desktop files
        const content = dir.readFileAlloc(alloc, filename, max_size) catch |err| {
            return err;
        };

        var name: []const u8 = "";
        var exec: []const u8 = "";
        var icon: []const u8 = "";
        var comment: []const u8 = "";
        var no_display = false;
        var hidden = false;
        var in_desktop_entry = false;

        // Split by lines
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |raw_line| {
            const trimmed = std.mem.trim(u8, raw_line, " \t\r");

            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Section header
            if (trimmed[0] == '[') {
                if (std.mem.eql(u8, trimmed, "[Desktop Entry]")) {
                    in_desktop_entry = true;
                } else {
                    in_desktop_entry = false;
                }
                continue;
            }

            if (!in_desktop_entry) continue;

            // Parse key=value
            if (std.mem.indexOf(u8, trimmed, "=")) |eq_pos| {
                const key = trimmed[0..eq_pos];
                const value = trimmed[eq_pos + 1 ..];

                if (std.mem.eql(u8, key, "Name") and name.len == 0) {
                    name = try alloc.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "Exec")) {
                    exec = try alloc.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "Icon")) {
                    icon = try alloc.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "Comment") and comment.len == 0) {
                    comment = try alloc.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "NoDisplay")) {
                    no_display = std.mem.eql(u8, value, "true");
                } else if (std.mem.eql(u8, key, "Hidden")) {
                    hidden = std.mem.eql(u8, value, "true");
                }
            }
        }

        // Skip entries that shouldn't be displayed
        if (no_display or hidden or name.len == 0) {
            return error.SkipEntry;
        }

        // Resolve icon path
        const icon_path = icons.resolveIconPath(alloc, icon);

        return DesktopEntry{
            .name = name,
            .exec = exec,
            .icon = icon,
            .icon_path = icon_path,
            .comment = comment,
            .arena = arena,
        };
    }

    /// Search for applications matching the query
    pub fn search(self: *Search, query: []const u8, max_results: usize) ![]const DesktopEntry {
        if (!self.loaded) {
            try self.loadEntries();
        }

        var results = std.ArrayListUnmanaged(DesktopEntry){};
        defer results.deinit(self.allocator);

        const query_lower = try self.allocator.alloc(u8, query.len);
        defer self.allocator.free(query_lower);
        for (query, 0..) |char, i| {
            query_lower[i] = std.ascii.toLower(char);
        }

        for (self.entries.items) |entry| {
            if (results.items.len >= max_results) break;

            // Case-insensitive search in name and comment
            if (containsIgnoreCase(entry.name, query_lower) or
                containsIgnoreCase(entry.comment, query_lower))
            {
                try results.append(self.allocator, entry);
            }
        }

        // Return a slice that will be valid as long as self.entries is valid
        return results.toOwnedSlice(self.allocator);
    }
};

fn containsIgnoreCase(haystack: []const u8, needle_lower: []const u8) bool {
    if (needle_lower.len == 0) return true;
    if (haystack.len < needle_lower.len) return false;

    var i: usize = 0;
    while (i <= haystack.len - needle_lower.len) : (i += 1) {
        var match = true;
        for (needle_lower, 0..) |needle_char, j| {
            if (std.ascii.toLower(haystack[i + j]) != needle_char) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

/// Format search results as JSON
pub fn formatResultsJson(allocator: std.mem.Allocator, entries: []const DesktopEntry) ![]u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);
    const writer = result.writer(allocator);

    try writer.writeAll("{\"type\":\"results\",\"results\":[");

    for (entries, 0..) |entry, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.writeAll("{\"type\":\"app\",\"name\":\"");
        try writeJsonEscaped(writer, entry.name);
        try writer.writeAll("\",\"exec\":\"");
        try writeJsonEscaped(writer, entry.exec);
        try writer.writeAll("\",\"icon\":\"");
        // Use a folder emoji for now, could lookup actual icon later
        if (entry.icon.len > 0) {
            try writeJsonEscaped(writer, entry.icon);
        } else {
            try writer.writeAll("\xF0\x9F\x93\xA6"); // Package emoji as UTF-8
        }
        try writer.writeAll("\",\"description\":\"");
        try writeJsonEscaped(writer, entry.comment);
        try writer.writeAll("\"}");
    }

    try writer.writeAll("]}");
    return result.toOwnedSlice(allocator);
}

fn writeJsonEscaped(writer: anytype, str: []const u8) !void {
    for (str) |char| {
        switch (char) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (char < 0x20) {
                    try writer.print("\\u{x:0>4}", .{char});
                } else {
                    try writer.writeByte(char);
                }
            },
        }
    }
}
