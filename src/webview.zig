const std = @import("std");
const c = @import("c.zig");
const assets = @import("assets.zig");
const handler = @import("handler.zig");

pub fn init() void {
    c.gtk_init();
}

pub const WebView = struct {
    allocator: std.mem.Allocator,
    webview: *c.WebKitWebView,
    box: *c.GtkBox,

    pub fn init(allocator: std.mem.Allocator) !WebView {
        // Create WebView first (it creates its own context in WebKitGTK 6.0)
        const webview = c.webkit_web_view_new();
        if (webview == null) return error.WebViewCreationFailed;

        // Get the context from the webview and register our scheme
        const context = c.webkit_web_view_get_context(@ptrCast(webview));
        if (context == null) return error.ContextNotFound;

        // Register waylight:// URI scheme
        c.webkit_web_context_register_uri_scheme(
            context,
            "waylight",
            handleSchemeRequest,
            null, // user_data
            null, // destroy_notify
        );

        // Enable file:// URL access for loading local icons
        const settings = c.webkit_web_view_get_settings(@ptrCast(webview));
        if (settings != null) {
            c.webkit_settings_set_allow_file_access_from_file_urls(settings, 1);
            c.webkit_settings_set_allow_universal_access_from_file_urls(settings, 1);
        }

        const box = c.gtk_box_new(c.GTK_ORIENTATION_VERTICAL, 0);

        // Set transparent background
        c.webkit_web_view_set_background_color(
            @ptrCast(webview),
            &c.GdkRGBA{ .red = 0.0, .green = 0.0, .blue = 0.0, .alpha = 0.0 },
        );

        // Make webview expand to fill available space
        c.gtk_widget_set_hexpand(webview, 1);
        c.gtk_widget_set_vexpand(webview, 1);

        c.gtk_box_append(@ptrCast(box), webview);

        return WebView{
            .allocator = allocator,
            .webview = @ptrCast(webview),
            .box = @ptrCast(box),
        };
    }

    pub fn deinit(_: *WebView) void {}

    pub fn getNativeWidget(self: *WebView) *c.GtkWidget {
        return @ptrCast(self.box);
    }

    pub fn loadUI(self: *WebView) !void {
        c.webkit_web_view_load_uri(
            @ptrCast(self.webview),
            "waylight:///index.html",
        );
    }

    pub fn setupMessageHandlers(self: *WebView, msg_handler: *handler.Handler) !void {
        // Set global handler for C callback
        handler.setGlobalHandler(msg_handler);

        // Get user content manager
        const manager = c.webkit_web_view_get_user_content_manager(@ptrCast(self.webview));
        if (manager == null) {
            std.log.err("Failed to get user content manager", .{});
            return error.ContentManagerNotFound;
        }

        // Register script message handler for "waylight"
        _ = c.webkit_user_content_manager_register_script_message_handler(manager, "waylight", null);

        // Connect signal for receiving messages
        _ = c.g_signal_connect_data(
            manager,
            "script-message-received::waylight",
            @ptrCast(&handler.onScriptMessage),
            null,
            null,
            0,
        );
    }

    pub fn sendToJS(self: *WebView, js_code: []const u8) void {
        const code_z = self.allocator.dupeZ(u8, js_code) catch return;
        defer self.allocator.free(code_z);
        c.webkit_web_view_run_javascript(@ptrCast(self.webview), code_z.ptr, null, null, null);
    }
};

/// Handle requests to waylight:// URIs
fn handleSchemeRequest(request: ?*c.WebKitURISchemeRequest, _: ?*anyopaque) callconv(.c) void {
    if (request == null) return;

    const path_ptr = c.webkit_uri_scheme_request_get_path(request);
    if (path_ptr == null) {
        std.log.warn("URI scheme request has no path", .{});
        finishWithError(request);
        return;
    }

    const path = std.mem.span(path_ptr);
    std.log.debug("waylight:// request for: {s}", .{path});

    // Handle icon requests (path starts with /icon/)
    if (std.mem.startsWith(u8, path, "/icon/")) {
        const file_path = path[5..]; // Strip "/icon" prefix, keep leading /
        serveFileFromDisk(request, file_path);
        return;
    }

    if (assets.get(path)) |asset| {
        // Create input stream from embedded content
        const stream = c.g_memory_input_stream_new_from_data(
            asset.content.ptr,
            @intCast(asset.content.len),
            null, // Don't free - it's static comptime data
        );

        if (stream == null) {
            std.log.err("Failed to create input stream for: {s}", .{path});
            finishWithError(request);
            return;
        }

        // Finish request with content
        c.webkit_uri_scheme_request_finish(
            request,
            stream,
            @intCast(asset.content.len),
            asset.mime_type.ptr,
        );

        c.g_object_unref(stream);
        std.log.debug("Served: {s} ({d} bytes, {s})", .{ path, asset.content.len, asset.mime_type });
    } else {
        std.log.warn("Asset not found: {s}", .{path});
        finishWithError(request);
    }
}

fn finishWithError(request: ?*c.WebKitURISchemeRequest) void {
    const quark = c.g_quark_from_string("waylight");
    const err = c.g_error_new_literal(quark, 404, "Not Found");
    c.webkit_uri_scheme_request_finish_error(request, err);
    c.g_error_free(err);
}

/// Serve a file from disk (used for icons)
fn serveFileFromDisk(request: ?*c.WebKitURISchemeRequest, file_path: []const u8) void {
    // Open the file
    const file = std.fs.openFileAbsolute(file_path, .{}) catch {
        std.log.warn("Icon file not found: {s}", .{file_path});
        finishWithError(request);
        return;
    };
    defer file.close();

    // Get file size
    const stat = file.stat() catch {
        finishWithError(request);
        return;
    };

    // Allocate buffer using GLib so g_free can properly free it
    const content_ptr: [*]u8 = @ptrCast(c.g_malloc(stat.size) orelse {
        finishWithError(request);
        return;
    });
    const content = content_ptr[0..stat.size];

    _ = file.readAll(content) catch {
        c.g_free(content_ptr);
        finishWithError(request);
        return;
    };

    // Determine MIME type based on extension
    const mime_type: [:0]const u8 = if (std.mem.endsWith(u8, file_path, ".png"))
        "image/png"
    else if (std.mem.endsWith(u8, file_path, ".svg"))
        "image/svg+xml"
    else if (std.mem.endsWith(u8, file_path, ".jpg") or std.mem.endsWith(u8, file_path, ".jpeg"))
        "image/jpeg"
    else
        "application/octet-stream";

    // Create GLib input stream - g_free is called automatically when stream is destroyed
    const stream = c.g_memory_input_stream_new_from_data(
        content_ptr,
        @intCast(stat.size),
        @ptrCast(&c.g_free),
    );

    if (stream == null) {
        c.g_free(content_ptr);
        finishWithError(request);
        return;
    }

    c.webkit_uri_scheme_request_finish(
        request,
        stream,
        @intCast(stat.size),
        mime_type.ptr,
    );

    c.g_object_unref(stream);
    std.log.debug("Served icon: {s} ({d} bytes)", .{ file_path, stat.size });
}
