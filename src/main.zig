const std = @import("std");
const wayland = @import("wayland.zig");
const webview = @import("webview.zig");
const handler = @import("handler.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize GTK (required by WebKitGTK)
    webview.init();

    // Initialize Wayland connection and create layer-shell surface
    var wl_ctx = try wayland.WaylandContext.init(allocator);
    defer wl_ctx.deinit();
    wayland.global_ctx = &wl_ctx;

    // Create WebView
    var wv = try webview.WebView.init(allocator);
    defer wv.deinit();

    // Create message handler
    var msg_handler = handler.Handler.init(allocator, wv.webview);
    defer msg_handler.deinit();
    msg_handler.setQuitCallback(&struct {
        fn quit() void {
            // Access wl_ctx through global - a bit hacky but works
            // In a real app we'd use proper state management
            @import("wayland.zig").global_ctx.?.quit();
        }
    }.quit);

    // Set up message handlers for JS -> Zig communication
    try wv.setupMessageHandlers(&msg_handler);

    // Load the UI
    try wv.loadUI();

    // Realize the Wayland window with the WebView
    try wl_ctx.realize(wv.getNativeWidget());

    // Run main event loop
    try wl_ctx.run();
}
