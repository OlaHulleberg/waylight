const std = @import("std");
const result = @import("../result.zig");
const scoring = @import("../scoring.zig");

const SearchResult = result.SearchResult;
const Score = scoring.Score;

/// File/directory search provider using plocate (indexed) and fd (home directory)
pub const FileProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FileProvider {
        return .{ .allocator = allocator };
    }

    pub fn deinit(_: *FileProvider) void {}

    /// Search for files and directories using parallel plocate + fd
    pub fn search(self: *FileProvider, query: []const u8, max_results: usize) ![]SearchResult {
        if (query.len == 0) return &[_]SearchResult{};

        // Run plocate and fd in parallel
        var plocate_results: []SearchResult = &[_]SearchResult{};
        var fd_results: []SearchResult = &[_]SearchResult{};

        const plocate_thread = std.Thread.spawn(.{}, runPlocateThread, .{ self, query, max_results, &plocate_results }) catch |err| blk: {
            std.log.debug("Failed to spawn plocate thread: {}", .{err});
            break :blk null;
        };
        const fd_thread = std.Thread.spawn(.{}, runFdThread, .{ self, query, max_results, &fd_results }) catch |err| blk: {
            std.log.debug("Failed to spawn fd thread: {}", .{err});
            break :blk null;
        };

        var plocate_ran = false;
        var fd_ran = false;

        if (plocate_thread) |t| {
            t.join();
            plocate_ran = true;
        }
        if (fd_thread) |t| {
            t.join();
            fd_ran = true;
        }

        defer if (plocate_ran) self.allocator.free(plocate_results);
        defer if (fd_ran) self.allocator.free(fd_results);

        // Merge results, deduplicating by path
        var results = std.ArrayListUnmanaged(SearchResult){};
        var seen = std.StringHashMap(void).init(self.allocator);
        defer seen.deinit();
        errdefer {
            for (results.items) |*r| r.deinit();
            results.deinit(self.allocator);
        }

        // Add plocate results first (indexed, faster)
        for (plocate_results) |r| {
            if (!seen.contains(r.path)) {
                try seen.put(r.path, {});
                try results.append(self.allocator, r);
            } else {
                var res = r;
                res.deinit();
            }
        }

        // Add fd results (catches recent files not in plocate index)
        for (fd_results) |r| {
            if (!seen.contains(r.path)) {
                try seen.put(r.path, {});
                try results.append(self.allocator, r);
            } else {
                var res = r;
                res.deinit();
            }
        }

        // Filter out no-match results
        var i: usize = 0;
        while (i < results.items.len) {
            if (results.items[i].score >= Score.NO_MATCH) {
                var r = results.items[i];
                r.deinit();
                _ = results.swapRemove(i);
            } else {
                i += 1;
            }
        }

        // Sort and trim
        result.sortByScore(results.items);
        result.trimToMax(&results, max_results);

        return results.toOwnedSlice(self.allocator);
    }

    fn runPlocateThread(self: *FileProvider, query: []const u8, max_results: usize, out: *[]SearchResult) void {
        out.* = self.runPlocateSearch(query, max_results) catch |err| {
            std.log.debug("plocate search failed: {}", .{err});
            out.* = self.allocator.alloc(SearchResult, 0) catch return;
            return;
        };
    }

    fn runFdThread(self: *FileProvider, query: []const u8, max_results: usize, out: *[]SearchResult) void {
        out.* = self.runFdSearch(query, max_results) catch |err| {
            std.log.debug("fd search failed: {}", .{err});
            out.* = self.allocator.alloc(SearchResult, 0) catch return;
            return;
        };
    }

    fn runPlocateSearch(self: *FileProvider, query: []const u8, max_results: usize) ![]SearchResult {
        var limit_buf: [20]u8 = undefined;
        const limit_str = std.fmt.bufPrint(&limit_buf, "{d}", .{max_results * 2}) catch unreachable;

        const argv = [_][]const u8{
            "plocate",
            "-i",
            "-l",
            limit_str,
            query,
        };

        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = child.stdout.?;
        const output = try stdout.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(output);

        const term = child.wait() catch |err| {
            std.log.debug("plocate wait failed: {}", .{err});
            return self.parseOutput(output, query, max_results);
        };
        if (term.Exited != 0) {
            std.log.debug("plocate exited with code {}", .{term.Exited});
        }

        return self.parseOutput(output, query, max_results);
    }

    fn runFdSearch(self: *FileProvider, query: []const u8, max_results: usize) ![]SearchResult {
        const home = std.posix.getenv("HOME") orelse return &[_]SearchResult{};

        var limit_buf: [20]u8 = undefined;
        const limit_str = std.fmt.bufPrint(&limit_buf, "{d}", .{max_results * 2}) catch unreachable;

        const argv = [_][]const u8{
            "fd",
            "-i",
            "--max-results",
            limit_str,
            query,
            home,
        };

        var child = std.process.Child.init(&argv, self.allocator);
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        try child.spawn();

        const stdout = child.stdout.?;
        const output = try stdout.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(output);

        const term = child.wait() catch |err| {
            std.log.debug("fd wait failed: {}", .{err});
            return self.parseOutput(output, query, max_results);
        };
        if (term.Exited != 0) {
            std.log.debug("fd exited with code {}", .{term.Exited});
        }

        return self.parseOutput(output, query, max_results);
    }

    fn parseOutput(self: *FileProvider, output: []const u8, query: []const u8, max_results: usize) ![]SearchResult {
        var results = std.ArrayListUnmanaged(SearchResult){};
        errdefer {
            for (results.items) |*r| r.deinit();
            results.deinit(self.allocator);
        }

        var lines = std.mem.splitScalar(u8, output, '\n');
        while (lines.next()) |line| {
            const path = std.mem.trim(u8, line, " \t\r");
            if (path.len == 0) continue;

            // Skip .desktop files (handled by app search)
            if (std.mem.endsWith(u8, path, ".desktop")) continue;

            if (self.parseResult(path, query)) |res| {
                try results.append(self.allocator, res);
                if (results.items.len >= max_results) break;
            }
        }

        return results.toOwnedSlice(self.allocator);
    }

    fn parseResult(self: *FileProvider, path: []const u8, query: []const u8) ?SearchResult {
        _ = self;

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer arena.deinit();
        const alloc = arena.allocator();

        const stored_path = alloc.dupe(u8, path) catch return null;
        const name = std.fs.path.basename(path);
        const stored_name = alloc.dupe(u8, name) catch return null;

        const is_dir = isDirectory(path);
        const score = scoring.computeNameScore(name, query);

        return SearchResult{
            .kind = if (is_dir) .dir else .file,
            .name = stored_name,
            .description = stored_path,
            .icon_url = "",
            .exec = "",
            .path = stored_path,
            .value = "",
            .score = score,
            .arena = arena,
        };
    }

    fn isDirectory(path: []const u8) bool {
        var dir = std.fs.openDirAbsolute(path, .{}) catch return false;
        dir.close();
        return true;
    }
};
