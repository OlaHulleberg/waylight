const std = @import("std");
const c = @import("c.zig");
const search = @import("search.zig");
const filesearch = @import("filesearch.zig");
const calculator = @import("calculator.zig");
const launcher = @import("launcher.zig");
const clipboard = @import("clipboard.zig");

pub const MessageType = enum {
    search,
    select,
    close,
};

pub const Message = struct {
    type: []const u8,
    query: ?[]const u8 = null,
    result: ?std.json.Value = null,
};

pub const Handler = struct {
    allocator: std.mem.Allocator,
    webview: *c.WebKitWebView,
    hide_callback: ?*const fn () void,
    app_search: search.Search,
    file_search: filesearch.FileSearch,

    pub fn init(allocator: std.mem.Allocator, webview: *c.WebKitWebView) Handler {
        return Handler{
            .allocator = allocator,
            .webview = webview,
            .hide_callback = null,
            .app_search = search.Search.init(allocator),
            .file_search = filesearch.FileSearch.init(allocator),
        };
    }

    pub fn deinit(self: *Handler) void {
        self.app_search.deinit();
        self.file_search.deinit();
    }

    pub fn setHideCallback(self: *Handler, callback: *const fn () void) void {
        self.hide_callback = callback;
    }

    /// Send reset message to JS to clear UI state
    pub fn notifyReset(self: *Handler) void {
        self.sendToJS("{\"type\":\"reset\"}");
    }

    pub fn handleMessage(self: *Handler, message_json: []const u8) void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, message_json, .{}) catch |err| {
            std.log.err("Failed to parse message: {}", .{err});
            return;
        };
        defer parsed.deinit();

        const obj = parsed.value.object;
        const msg_type = obj.get("type") orelse return;

        if (std.mem.eql(u8, msg_type.string, "search")) {
            if (obj.get("query")) |query_val| {
                self.handleSearch(query_val.string);
            }
        } else if (std.mem.eql(u8, msg_type.string, "select")) {
            if (obj.get("result")) |result_val| {
                self.handleSelect(result_val);
            }
        } else if (std.mem.eql(u8, msg_type.string, "close")) {
            self.handleClose();
        }
    }

    fn handleSearch(self: *Handler, query: []const u8) void {
        if (query.len == 0) {
            self.sendToJS("{\"type\":\"results\",\"results\":[]}");
            return;
        }

        // Build combined results
        var json_buf = std.ArrayListUnmanaged(u8){};
        defer json_buf.deinit(self.allocator);
        const writer = json_buf.writer(self.allocator);

        writer.writeAll("{\"type\":\"results\",\"results\":[") catch return;

        var has_results = false;
        var result_count: usize = 0;
        const max_results: usize = 8;

        // Check if query looks like a math expression
        if (calculator.isMathExpression(query)) {
            if (calculator.evaluate(self.allocator, query)) |calc_result_const| {
                var calc_result = calc_result_const;
                defer calc_result.deinit();

                // Add calculator result
                if (has_results) writer.writeAll(",") catch return;
                writer.writeAll("{\"type\":\"calc\",\"query\":\"") catch return;
                writeJsonEscaped(writer, calc_result.query) catch return;
                writer.writeAll("\",\"value\":\"") catch return;
                writeJsonEscaped(writer, calc_result.result) catch return;
                writer.writeAll("\"}") catch return;
                has_results = true;
                result_count += 1;
            } else |err| {
                std.log.debug("Calculator error: {}", .{err});
            }
        }

        // Search for desktop apps (instant, in-memory) - prioritize apps, fill up to max_results
        if (self.app_search.search(query, max_results)) |entries| {
            defer self.allocator.free(entries);

            for (entries) |entry| {
                if (result_count >= max_results) break;

                if (has_results) writer.writeAll(",") catch return;
                writer.writeAll("{\"type\":\"app\",\"name\":\"") catch return;
                writeJsonEscaped(writer, entry.name) catch return;
                writer.writeAll("\",\"exec\":\"") catch return;
                writeJsonEscaped(writer, entry.exec) catch return;
                writer.writeAll("\",\"icon\":\"") catch return;
                if (entry.icon_path.len > 0) {
                    writer.writeAll("waylight:///icon") catch return;
                    writeJsonEscaped(writer, entry.icon_path) catch return;
                }
                writer.writeAll("\",\"description\":\"") catch return;
                writeJsonEscaped(writer, entry.comment) catch return;
                writer.writeAll("\"}") catch return;
                has_results = true;
                result_count += 1;
            }
        } else |err| {
            std.log.debug("App search error: {}", .{err});
        }

        // Search for files and directories using plocate/fd
        if (self.file_search.search(query, max_results - result_count)) |results| {
            defer {
                for (results) |*r| {
                    var result = r.*;
                    result.deinit();
                }
                self.allocator.free(results);
            }

            for (results) |result| {
                if (result_count >= max_results) break;

                // Skip .desktop files (already handled by app_search)
                if (result.result_type == .app) continue;

                if (has_results) writer.writeAll(",") catch return;

                switch (result.result_type) {
                    .app => {}, // Skip, handled above
                    .file => {
                        writer.writeAll("{\"type\":\"file\",\"name\":\"") catch return;
                        writeJsonEscaped(writer, result.name) catch return;
                        writer.writeAll("\",\"path\":\"") catch return;
                        writeJsonEscaped(writer, result.path) catch return;
                        writer.writeAll("\",\"icon\":\"\",\"description\":\"") catch return;
                        writeJsonEscaped(writer, result.description) catch return;
                        writer.writeAll("\"}") catch return;
                        has_results = true;
                        result_count += 1;
                    },
                    .dir => {
                        writer.writeAll("{\"type\":\"dir\",\"name\":\"") catch return;
                        writeJsonEscaped(writer, result.name) catch return;
                        writer.writeAll("\",\"path\":\"") catch return;
                        writeJsonEscaped(writer, result.path) catch return;
                        writer.writeAll("\",\"icon\":\"\",\"description\":\"") catch return;
                        writeJsonEscaped(writer, result.description) catch return;
                        writer.writeAll("\"}") catch return;
                        has_results = true;
                        result_count += 1;
                    },
                }
            }
        } else |err| {
            std.log.debug("File search error: {}", .{err});
        }

        writer.writeAll("]}") catch return;

        self.sendToJS(json_buf.items);
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

    fn handleSelect(self: *Handler, result: std.json.Value) void {
        const obj = result.object;
        const result_type = obj.get("type") orelse return;

        if (std.mem.eql(u8, result_type.string, "calc")) {
            // Copy calculator result to clipboard
            if (obj.get("value")) |value| {
                clipboard.copy(self.allocator, value.string) catch |err| {
                    std.log.err("Failed to copy to clipboard: {}", .{err});
                };
            }
        } else if (std.mem.eql(u8, result_type.string, "app")) {
            // Launch application
            if (obj.get("exec")) |exec_val| {
                launcher.launch(self.allocator, exec_val.string) catch |err| {
                    std.log.err("Failed to launch app: {}", .{err});
                };
            }
        } else if (std.mem.eql(u8, result_type.string, "file") or std.mem.eql(u8, result_type.string, "dir")) {
            // Open file or directory with xdg-open
            if (obj.get("path")) |path_val| {
                self.xdgOpen(path_val.string) catch |err| {
                    std.log.err("Failed to open: {}", .{err});
                };
            }
        }

        // Close after selection
        self.handleClose();
    }

    fn xdgOpen(self: *Handler, path: []const u8) !void {
        const argv = [_][]const u8{ "xdg-open", path };

        var child = std.process.Child.init(&argv, self.allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        try child.spawn();
        // Don't wait - let xdg-open run in background
    }

    fn handleClose(self: *Handler) void {
        if (self.hide_callback) |callback| {
            callback();
        }
    }

    fn sendToJS(self: *Handler, json: []const u8) void {
        // Build JavaScript call: window.receiveFromBackend({json})
        var buf: [16384]u8 = undefined;
        const js = std.fmt.bufPrint(&buf, "window.receiveFromBackend({s});", .{json}) catch {
            std.log.err("Failed to format JS call", .{});
            return;
        };

        // Null-terminate for C
        const js_z = self.allocator.dupeZ(u8, js) catch return;
        defer self.allocator.free(js_z);

        // WebKitGTK 6.0 API: evaluate_javascript(webview, script, length, world_name, source_uri, cancellable, callback, user_data)
        c.webkit_web_view_evaluate_javascript(
            self.webview,
            js_z.ptr,
            -1, // length: -1 for null-terminated
            null, // world_name: default world
            null, // source_uri
            null, // cancellable
            null, // callback (fire-and-forget)
            null, // user_data
        );
        std.log.debug("Sent to JS: {s}", .{js});
    }
};

// Global handler instance for C callback
var global_handler: ?*Handler = null;

pub fn setGlobalHandler(handler: *Handler) void {
    global_handler = handler;
}

/// C callback for script message received
pub fn onScriptMessage(_: ?*c.WebKitUserContentManager, js_result: ?*c.JSCValue, _: ?*anyopaque) callconv(.c) void {
    if (global_handler == null) return;
    if (js_result == null) return;

    // Get string value from JSCValue
    const str_ptr = c.jsc_value_to_string(js_result);
    if (str_ptr == null) return;
    defer c.g_free(str_ptr);

    const message = std.mem.span(str_ptr);
    global_handler.?.handleMessage(message);
}
