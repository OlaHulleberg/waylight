const std = @import("std");
const desktop = @import("desktop.zig");
const result = @import("../result.zig");
const scoring = @import("../scoring.zig");

const SearchResult = result.SearchResult;
const ResultKind = result.ResultKind;
const Score = scoring.Score;

/// Cached app entry for in-memory search
const AppEntry = struct {
    name: []const u8,
    exec: []const u8,
    icon_path: []const u8,
    comment: []const u8,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *AppEntry) void {
        self.arena.deinit();
    }
};

/// App search provider - loads and caches all desktop entries
pub const AppProvider = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(AppEntry),
    loaded: bool,

    pub fn init(allocator: std.mem.Allocator) AppProvider {
        return .{
            .allocator = allocator,
            .entries = .{},
            .loaded = false,
        };
    }

    pub fn deinit(self: *AppProvider) void {
        for (self.entries.items) |*entry| {
            entry.deinit();
        }
        self.entries.deinit(self.allocator);
    }

    /// Load all desktop entries from standard locations
    pub fn loadEntries(self: *AppProvider) !void {
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
        std.log.info("Loaded {d} total app entries", .{self.entries.items.len});
    }

    fn loadFromDir(self: *AppProvider, dir_path: []const u8) !void {
        var dir = std.fs.openDirAbsolute(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();

        const data_dir = desktop.extractDataDir(dir_path);

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if ((entry.kind == .file or entry.kind == .sym_link) and std.mem.endsWith(u8, entry.name, ".desktop")) {
                if (desktop.parseFromDir(dir, entry.name, data_dir)) |data| {
                    try self.entries.append(self.allocator, .{
                        .name = data.name,
                        .exec = data.exec,
                        .icon_path = data.icon_path,
                        .comment = data.comment,
                        .arena = data.arena,
                    });
                }
            }
        }
    }

    /// Search for apps matching query
    pub fn search(self: *AppProvider, query: []const u8, max_results: usize) ![]SearchResult {
        if (!self.loaded) {
            try self.loadEntries();
        }

        var results = std.ArrayListUnmanaged(SearchResult){};
        errdefer {
            for (results.items) |*r| r.deinit();
            results.deinit(self.allocator);
        }

        for (self.entries.items) |entry| {
            const score = scoring.computeScore(entry.name, entry.comment, query);
            if (score >= Score.NO_MATCH) continue;

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            errdefer arena.deinit();
            const alloc = arena.allocator();

            // Build icon URL
            var icon_url: []const u8 = "";
            if (entry.icon_path.len > 0) {
                icon_url = std.fmt.allocPrint(alloc, "waylight:///icon{s}", .{entry.icon_path}) catch "";
            }

            try results.append(self.allocator, .{
                .kind = .app,
                .name = try alloc.dupe(u8, entry.name),
                .description = try alloc.dupe(u8, entry.comment),
                .icon_url = icon_url,
                .exec = try alloc.dupe(u8, entry.exec),
                .path = "",
                .value = "",
                .score = score,
                .arena = arena,
            });

            if (results.items.len >= max_results * 2) break; // Get extra for sorting
        }

        // Sort and trim
        result.sortByScore(results.items);
        result.trimToMax(&results, max_results);

        return results.toOwnedSlice(self.allocator);
    }
};
