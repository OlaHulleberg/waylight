const std = @import("std");
const result = @import("result.zig");
const scoring = @import("scoring.zig");
const apps = @import("providers/apps.zig");
const files = @import("providers/files.zig");
const calculator = @import("providers/calculator.zig");

const SearchResult = result.SearchResult;
const Score = scoring.Score;

/// Search orchestrator - combines all search providers
pub const Orchestrator = struct {
    allocator: std.mem.Allocator,
    app_provider: apps.AppProvider,
    file_provider: files.FileProvider,
    calc_provider: calculator.CalcProvider,

    pub fn init(allocator: std.mem.Allocator) Orchestrator {
        return .{
            .allocator = allocator,
            .app_provider = apps.AppProvider.init(allocator),
            .file_provider = files.FileProvider.init(allocator),
            .calc_provider = calculator.CalcProvider.init(allocator),
        };
    }

    pub fn deinit(self: *Orchestrator) void {
        self.app_provider.deinit();
        self.file_provider.deinit();
        self.calc_provider.deinit();
    }

    /// Execute search across all providers and return merged, ranked results
    pub fn search(self: *Orchestrator, query: []const u8, max_results: usize) ![]SearchResult {
        if (query.len == 0) return &[_]SearchResult{};

        var all_results = std.ArrayListUnmanaged(SearchResult){};
        errdefer {
            for (all_results.items) |*r| r.deinit();
            all_results.deinit(self.allocator);
        }

        // 1. Calculator (if expression-like) - high priority
        if (self.calc_provider.search(query, 1)) |calc_results| {
            defer self.allocator.free(calc_results);
            for (calc_results) |r| try all_results.append(self.allocator, r);
        } else |_| {}

        // 2. App search (in-memory, fast)
        if (self.app_provider.search(query, max_results)) |app_results| {
            defer self.allocator.free(app_results);
            for (app_results) |r| try all_results.append(self.allocator, r);
        } else |_| {}

        // 3. File/dir search (fd)
        if (self.file_provider.search(query, max_results)) |file_results| {
            defer self.allocator.free(file_results);
            for (file_results) |r| try all_results.append(self.allocator, r);
        } else |_| {}

        // Sort and trim
        result.sortByScore(all_results.items);
        result.trimToMax(&all_results, max_results);

        return all_results.toOwnedSlice(self.allocator);
    }
};
