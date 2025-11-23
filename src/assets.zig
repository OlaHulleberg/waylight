const std = @import("std");

pub const Asset = struct {
    content: []const u8,
    mime_type: [:0]const u8,
};

// Embed all web assets at compile time
const index_html = @embedFile("web/index.html");
const style_css = @embedFile("web/style.css");
const app_js = @embedFile("web/app.js");

/// Get an embedded asset by path
/// Strips leading slash if present
pub fn get(path: []const u8) ?Asset {
    // Strip leading slash if present
    const clean_path = if (path.len > 0 and path[0] == '/') path[1..] else path;

    // Handle empty path or root as index.html
    const lookup = if (clean_path.len == 0) "index.html" else clean_path;

    if (std.mem.eql(u8, lookup, "index.html")) {
        return Asset{ .content = index_html, .mime_type = "text/html" };
    } else if (std.mem.eql(u8, lookup, "style.css")) {
        return Asset{ .content = style_css, .mime_type = "text/css" };
    } else if (std.mem.eql(u8, lookup, "app.js")) {
        return Asset{ .content = app_js, .mime_type = "application/javascript" };
    }

    return null;
}
