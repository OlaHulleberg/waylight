const std = @import("std");

/// Type of search result
pub const ResultKind = enum {
    app,
    file,
    dir,
    calc,

    pub fn toJsonString(self: ResultKind) []const u8 {
        return switch (self) {
            .app => "app",
            .file => "file",
            .dir => "dir",
            .calc => "calc",
        };
    }
};

/// Unified search result for all search types
pub const SearchResult = struct {
    kind: ResultKind,
    name: []const u8,
    description: []const u8,
    icon_url: []const u8,

    // Type-specific action data (empty string if not applicable)
    exec: []const u8, // For apps
    path: []const u8, // For files/dirs
    value: []const u8, // For calc

    score: u16, // Lower = better match
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *SearchResult) void {
        self.arena.deinit();
    }

    /// Serialize this result to JSON
    pub fn toJson(self: *const SearchResult, writer: anytype) !void {
        try writer.writeAll("{\"type\":\"");
        try writer.writeAll(self.kind.toJsonString());
        try writer.writeAll("\",\"name\":\"");
        try writeJsonEscaped(writer, self.name);
        try writer.writeAll("\"");

        // Type-specific fields
        switch (self.kind) {
            .app => {
                try writer.writeAll(",\"exec\":\"");
                try writeJsonEscaped(writer, self.exec);
                try writer.writeAll("\",\"icon\":\"");
                try writeJsonEscaped(writer, self.icon_url);
                try writer.writeAll("\",\"description\":\"");
                try writeJsonEscaped(writer, self.description);
                try writer.writeAll("\"");
            },
            .file, .dir => {
                try writer.writeAll(",\"path\":\"");
                try writeJsonEscaped(writer, self.path);
                try writer.writeAll("\",\"icon\":\"\",\"description\":\"");
                try writeJsonEscaped(writer, self.description);
                try writer.writeAll("\"");
            },
            .calc => {
                try writer.writeAll(",\"query\":\"");
                try writeJsonEscaped(writer, self.description);
                try writer.writeAll("\",\"value\":\"");
                try writeJsonEscaped(writer, self.value);
                try writer.writeAll("\"");
            },
        }

        try writer.writeAll("}");
    }
};

/// Serialize array of results to JSON response
pub fn serializeResults(allocator: std.mem.Allocator, results: []const SearchResult) ![]u8 {
    var buf = std.ArrayListUnmanaged(u8){};
    errdefer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writer.writeAll("{\"type\":\"results\",\"results\":[");

    for (results, 0..) |*result, i| {
        if (i > 0) try writer.writeAll(",");
        try result.toJson(writer);
    }

    try writer.writeAll("]}");
    return buf.toOwnedSlice(allocator);
}

/// Sort results by score (lower = better match)
pub fn sortByScore(items: []SearchResult) void {
    std.mem.sort(SearchResult, items, {}, struct {
        fn lessThan(_: void, a: SearchResult, b: SearchResult) bool {
            return a.score < b.score;
        }
    }.lessThan);
}

/// Trim results to max count, deinit'ing removed items
pub fn trimToMax(results: *std.ArrayListUnmanaged(SearchResult), max: usize) void {
    while (results.items.len > max) {
        if (results.pop()) |*r| {
            var res = r.*;
            res.deinit();
        }
    }
}

/// Escape a string for safe inclusion in JSON output
pub fn writeJsonEscaped(writer: anytype, str: []const u8) !void {
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
