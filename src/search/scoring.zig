const std = @import("std");

/// Score constants - lower is better
pub const Score = struct {
    pub const CALCULATOR: u16 = 0; // Calculator always first
    pub const EXACT_NAME: u16 = 100; // "firefox" == "firefox"
    pub const PREFIX_NAME: u16 = 200; // "fire" matches "firefox"
    pub const CONTAINS_NAME: u16 = 300; // "fox" in "firefox"
    pub const DESC_MATCH: u16 = 500; // Description only match
    pub const NO_MATCH: u16 = 1000; // Filter out
};

/// Compute the best match score for name and description
pub fn computeScore(name: []const u8, description: []const u8, query: []const u8) u16 {
    if (query.len == 0) return Score.CONTAINS_NAME;

    // Check name first
    const name_score = computeNameScore(name, query);
    if (name_score < Score.NO_MATCH) return name_score;

    // Fall back to description
    if (description.len > 0 and containsIgnoreCase(description, query)) {
        return Score.DESC_MATCH;
    }

    return Score.NO_MATCH;
}

/// Compute score based on name match quality
pub fn computeNameScore(name: []const u8, query: []const u8) u16 {
    if (query.len == 0) return Score.CONTAINS_NAME;
    if (name.len == 0) return Score.NO_MATCH;
    if (query.len > name.len) return Score.NO_MATCH;

    // Exact match (case-insensitive)
    if (name.len == query.len and eqlIgnoreCase(name, query)) {
        return Score.EXACT_NAME;
    }

    // Prefix match
    if (startsWithIgnoreCase(name, query)) {
        return Score.PREFIX_NAME;
    }

    // Contains match
    if (containsIgnoreCase(name, query)) {
        return Score.CONTAINS_NAME;
    }

    return Score.NO_MATCH;
}

/// Check if two strings are equal (case-insensitive)
pub fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (std.ascii.toLower(ac) != std.ascii.toLower(bc)) return false;
    }
    return true;
}

/// Check if haystack starts with needle (case-insensitive)
pub fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    for (haystack[0..needle.len], needle) |hc, nc| {
        if (std.ascii.toLower(hc) != std.ascii.toLower(nc)) return false;
    }
    return true;
}

/// Check if haystack contains needle (case-insensitive)
pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;

    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}
