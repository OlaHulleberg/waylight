const std = @import("std");
const icons = @import("icons.zig");

pub const ResultType = enum {
    app,
    file,
    dir,
};

pub const SearchResult = struct {
    result_type: ResultType,
    name: []const u8,
    path: []const u8,
    exec: []const u8,
    icon_path: []const u8,
    description: []const u8,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *SearchResult) void {
        self.arena.deinit();
    }
};

pub const FileSearch = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FileSearch {
        return FileSearch{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *FileSearch) void {
        // Nothing to clean up
    }

    /// Search for files, directories, and apps using parallel plocate + fd
    pub fn search(self: *FileSearch, query: []const u8, max_results: usize) ![]SearchResult {
        if (query.len == 0) {
            return &[_]SearchResult{};
        }

        // Run plocate and fd in parallel threads
        const PlocateContext = struct {
            search: *FileSearch,
            query: []const u8,
            max: usize,
            results: ?[]SearchResult = null,
        };
        const FdContext = struct {
            search: *FileSearch,
            query: []const u8,
            max: usize,
            results: ?[]SearchResult = null,
        };

        var plocate_ctx = PlocateContext{ .search = self, .query = query, .max = max_results };
        var fd_ctx = FdContext{ .search = self, .query = query, .max = max_results };

        // Spawn plocate thread
        const plocate_thread = std.Thread.spawn(.{}, struct {
            fn run(ctx: *PlocateContext) void {
                ctx.results = ctx.search.runPlocateSearch(ctx.query, ctx.max) catch null;
            }
        }.run, .{&plocate_ctx}) catch null;

        // Spawn fd thread
        const fd_thread = std.Thread.spawn(.{}, struct {
            fn run(ctx: *FdContext) void {
                ctx.results = ctx.search.runFdSearch(ctx.query, ctx.max) catch null;
            }
        }.run, .{&fd_ctx}) catch null;

        // Wait for both threads
        if (plocate_thread) |t| t.join();
        if (fd_thread) |t| t.join();

        // Merge results: apps first, then fd results (home files), limited to max_results
        var results = std.ArrayListUnmanaged(SearchResult){};
        errdefer {
            for (results.items) |*r| r.deinit();
            results.deinit(self.allocator);
        }

        // Add apps from plocate first
        if (plocate_ctx.results) |plocate_results| {
            defer self.allocator.free(plocate_results);
            for (plocate_results) |result| {
                if (result.result_type == .app) {
                    try results.append(self.allocator, result);
                } else {
                    var r = result;
                    r.deinit();
                }
            }
        }

        // Add fd results (home directory files/dirs)
        if (fd_ctx.results) |fd_results| {
            defer self.allocator.free(fd_results);
            for (fd_results) |result| {
                if (results.items.len >= max_results) {
                    var r = result;
                    r.deinit();
                    continue;
                }
                try results.append(self.allocator, result);
            }
        }

        // Trim to max_results
        while (results.items.len > max_results) {
            if (results.pop()) |*r| {
                var result = r.*;
                result.deinit();
            }
        }

        return results.toOwnedSlice(self.allocator);
    }

    /// Run plocate search for .desktop apps only
    fn runPlocateSearch(self: *FileSearch, query: []const u8, max_results: usize) ![]SearchResult {
        const plocate_paths = self.runPlocate(query, max_results * 3) catch return &[_]SearchResult{};
        defer self.allocator.free(plocate_paths);

        var results = std.ArrayListUnmanaged(SearchResult){};
        errdefer {
            for (results.items) |*r| r.deinit();
            results.deinit(self.allocator);
        }

        var lines = std.mem.splitScalar(u8, plocate_paths, '\n');
        while (lines.next()) |line| {
            const path = std.mem.trim(u8, line, " \t\r");
            if (path.len == 0) continue;
            if (!self.shouldIncludePath(path)) continue;

            // Only process .desktop files from plocate
            if (!std.mem.endsWith(u8, path, ".desktop")) continue;

            if (self.parseResult(path)) |result| {
                try results.append(self.allocator, result);
                if (results.items.len >= max_results) break;
            }
        }

        return results.toOwnedSlice(self.allocator);
    }

    /// Run fd search for home directory files
    fn runFdSearch(self: *FileSearch, query: []const u8, max_results: usize) ![]SearchResult {
        const home = std.posix.getenv("HOME") orelse return &[_]SearchResult{};
        const max_str = try std.fmt.allocPrint(self.allocator, "{d}", .{max_results * 2});
        defer self.allocator.free(max_str);

        const argv = [_][]const u8{
            "fd",
            "-i",
            "--max-results",
            max_str,
            query,
            home,
        };

        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = child.stdout.?;
        const fd_output = try stdout.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(fd_output);

        _ = child.wait() catch {};

        var results = std.ArrayListUnmanaged(SearchResult){};
        errdefer {
            for (results.items) |*r| r.deinit();
            results.deinit(self.allocator);
        }

        var lines = std.mem.splitScalar(u8, fd_output, '\n');
        while (lines.next()) |line| {
            const path = std.mem.trim(u8, line, " \t\r");
            if (path.len == 0) continue;

            // Skip .desktop files (handled by plocate)
            if (std.mem.endsWith(u8, path, ".desktop")) continue;

            if (self.parseResult(path)) |result| {
                try results.append(self.allocator, result);
                if (results.items.len >= max_results) break;
            }
        }

        return results.toOwnedSlice(self.allocator);
    }

    fn runPlocate(self: *FileSearch, query: []const u8, limit: usize) ![]u8 {
        const limit_str = try std.fmt.allocPrint(self.allocator, "{d}", .{limit});
        defer self.allocator.free(limit_str);

        const argv = [_][]const u8{
            "plocate",
            "-i", // Case-insensitive
            "-l",
            limit_str, // Limit results
            query,
        };

        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = child.stdout.?;
        const result = try stdout.readToEndAlloc(self.allocator, 1024 * 1024);

        _ = child.wait() catch {};

        return result;
    }


    fn shouldIncludePath(_: *FileSearch, path: []const u8) bool {
        // Always include .desktop files from applications directories
        if (std.mem.endsWith(u8, path, ".desktop")) {
            if (std.mem.indexOf(u8, path, "/applications/") != null) {
                return true;
            }
        }

        // Exclude system paths that aren't useful
        const excluded_prefixes = [_][]const u8{
            "/usr/lib",
            "/usr/libexec",
            "/usr/share/doc",
            "/usr/share/man",
            "/usr/share/locale",
            "/usr/share/icons",
            "/usr/share/mime",
            "/var/cache",
            "/var/log",
            "/var/lib",
            "/proc",
            "/sys",
            "/dev",
            "/run",
            "/tmp",
            "/boot",
            "/etc",
        };

        for (excluded_prefixes) |prefix| {
            if (std.mem.startsWith(u8, path, prefix)) {
                return false;
            }
        }

        // Exclude hidden directories in paths (but not hidden files at end)
        const excluded_dirs = [_][]const u8{
            "/.git/",
            "/node_modules/",
            "/__pycache__/",
            "/.cache/",
            "/.local/share/Trash/",
            "/.cargo/registry/",
            "/.rustup/",
            "/.npm/",
        };

        for (excluded_dirs) |dir| {
            if (std.mem.indexOf(u8, path, dir) != null) {
                return false;
            }
        }

        return true;
    }

    fn parseResult(self: *FileSearch, path: []const u8) ?SearchResult {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer arena.deinit();
        const alloc = arena.allocator();

        // Duplicate path for storage
        const stored_path = alloc.dupe(u8, path) catch return null;

        // Get basename
        const name = std.fs.path.basename(path);
        const stored_name = alloc.dupe(u8, name) catch return null;

        // Check if it's a .desktop file
        if (std.mem.endsWith(u8, path, ".desktop")) {
            if (self.parseDesktopFile(alloc, path)) |app_info| {
                return SearchResult{
                    .result_type = .app,
                    .name = app_info.name,
                    .path = stored_path,
                    .exec = app_info.exec,
                    .icon_path = app_info.icon_path,
                    .description = app_info.comment,
                    .arena = arena,
                };
            }
            // If .desktop parsing failed, skip this entry
            return null;
        }

        // Check if directory or file
        const is_dir = self.isDirectory(path);

        return SearchResult{
            .result_type = if (is_dir) .dir else .file,
            .name = stored_name,
            .path = stored_path,
            .exec = "",
            .icon_path = "",
            .description = stored_path, // Show full path as description
            .arena = arena,
        };
    }

    const AppInfo = struct {
        name: []const u8,
        exec: []const u8,
        icon_path: []const u8,
        comment: []const u8,
    };

    fn parseDesktopFile(self: *FileSearch, alloc: std.mem.Allocator, path: []const u8) ?AppInfo {
        _ = self;

        // Read the file
        const file = std.fs.openFileAbsolute(path, .{}) catch return null;
        defer file.close();

        const content = file.readToEndAlloc(alloc, 64 * 1024) catch return null;

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

        // Extract data_dir from path for icon resolution
        const data_dir = if (std.mem.lastIndexOf(u8, path, "/applications/")) |idx|
            path[0..idx]
        else
            "/usr/share";

        // Resolve icon path
        const icon_path = icons.resolveIconPath(alloc, icon, data_dir);

        return AppInfo{
            .name = name,
            .exec = exec,
            .icon_path = icon_path,
            .comment = comment,
        };
    }

    fn isDirectory(_: *FileSearch, path: []const u8) bool {
        // Try to open as directory - if it succeeds, it's a directory
        var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
        dir.close();
        return true;
    }
};
