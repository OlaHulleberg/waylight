const std = @import("std");
const calc = @import("../../calculator.zig");
const result = @import("../result.zig");
const scoring = @import("../scoring.zig");

const SearchResult = result.SearchResult;
const Score = scoring.Score;

/// Calculator search provider
pub const CalcProvider = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CalcProvider {
        return .{ .allocator = allocator };
    }

    pub fn deinit(_: *CalcProvider) void {}

    /// Check if query is a math expression and evaluate it
    pub fn search(self: *CalcProvider, query: []const u8, max_results: usize) ![]SearchResult {
        _ = max_results;

        if (!calc.isMathExpression(query)) {
            return &[_]SearchResult{};
        }

        var calc_result = calc.evaluate(self.allocator, query) catch return &[_]SearchResult{};
        defer calc_result.deinit();

        // Skip if result is empty or just "0"
        if (calc_result.result.len == 0) {
            return &[_]SearchResult{};
        }

        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        errdefer arena.deinit();
        const alloc = arena.allocator();

        // Format display name
        const display = try std.fmt.allocPrint(alloc, "{s} = {s}", .{ calc_result.query, calc_result.result });

        var results = std.ArrayListUnmanaged(SearchResult){};
        errdefer results.deinit(self.allocator);

        try results.append(self.allocator, SearchResult{
            .kind = .calc,
            .name = display,
            .description = try alloc.dupe(u8, calc_result.query),
            .icon_url = "",
            .exec = "",
            .path = "",
            .value = try alloc.dupe(u8, calc_result.result),
            .score = Score.CALCULATOR,
            .arena = arena,
        });

        return results.toOwnedSlice(self.allocator);
    }
};
