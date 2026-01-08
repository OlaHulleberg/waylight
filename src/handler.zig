const std = @import("std");
const c = @import("c.zig");
const search = @import("search/mod.zig");
const launcher = @import("launcher.zig");
const clipboard = @import("clipboard.zig");

pub const Handler = struct {
    allocator: std.mem.Allocator,
    webview: *c.WebKitWebView,
    hide_callback: ?*const fn () void,
    orchestrator: search.Orchestrator,

    pub fn init(allocator: std.mem.Allocator, webview: *c.WebKitWebView) Handler {
        return Handler{
            .allocator = allocator,
            .webview = webview,
            .hide_callback = null,
            .orchestrator = search.Orchestrator.init(allocator),
        };
    }

    pub fn deinit(self: *Handler) void {
        self.orchestrator.deinit();
    }

    /// Reload desktop entries (called when .desktop files change)
    pub fn reloadApps(self: *Handler) void {
        self.orchestrator.reloadApps();
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

        const max_results: usize = 20;

        // Single call to orchestrator - all search logic is there
        const results = self.orchestrator.search(query, max_results) catch |err| {
            std.log.err("Search failed: {}", .{err});
            self.sendToJS("{\"type\":\"results\",\"results\":[]}");
            return;
        };
        defer {
            for (results) |*r| {
                var res = r.*;
                res.deinit();
            }
            self.allocator.free(results);
        }

        // Serialize results to JSON
        const json = search.serializeResults(self.allocator, results) catch {
            self.sendToJS("{\"type\":\"results\",\"results\":[]}");
            return;
        };
        defer self.allocator.free(json);

        self.sendToJS(json);
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
