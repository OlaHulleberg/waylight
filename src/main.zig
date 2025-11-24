const std = @import("std");
const build_options = @import("build_options");
const wayland = @import("wayland.zig");
const webview = @import("webview.zig");
const handler = @import("handler.zig");
const ipc = @import("ipc.zig");

pub const std_options: std.Options = .{
    .log_level = @enumFromInt(@intFromEnum(build_options.log_level)),
};

const Mode = enum {
    daemon,
    toggle,
    quit_daemon,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const mode = parseArgs();

    switch (mode) {
        .toggle => {
            // Try to signal existing daemon
            if (ipc.IpcClient.isDaemonRunning(allocator)) {
                ipc.IpcClient.sendCommand(allocator, .toggle) catch {
                    // Failed to send, try starting daemon
                    try runDaemon(allocator);
                };
            } else {
                // No daemon running, start one
                try runDaemon(allocator);
            }
        },
        .quit_daemon => {
            if (ipc.IpcClient.isDaemonRunning(allocator)) {
                ipc.IpcClient.sendCommand(allocator, .quit) catch {};
            }
        },
        .daemon => {
            // Check if already running
            if (ipc.IpcClient.isDaemonRunning(allocator)) {
                std.log.err("Waylight daemon is already running", .{});
                return;
            }
            try runDaemon(allocator);
        },
    }
}

fn parseArgs() Mode {
    var args = std.process.args();
    _ = args.skip(); // Skip program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--toggle") or std.mem.eql(u8, arg, "-t")) {
            return .toggle;
        } else if (std.mem.eql(u8, arg, "--quit") or std.mem.eql(u8, arg, "-q")) {
            return .quit_daemon;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        }
    }

    return .daemon;
}

fn printUsage() void {
    std.debug.print(
        \\Usage: waylight [OPTIONS]
        \\
        \\Options:
        \\  --toggle, -t    Toggle window visibility (starts daemon if not running)
        \\  --quit, -q      Quit the running daemon
        \\  --help, -h      Show this help message
        \\
        \\Without options, starts as daemon and shows the window.
        \\
    , .{});
}

// Global handler for IPC callbacks
var global_msg_handler: ?*handler.Handler = null;

fn runDaemon(allocator: std.mem.Allocator) !void {
    // Initialize GTK (required by WebKitGTK)
    webview.init();

    // Set up IPC server
    var ipc_server = ipc.IpcServer.init(allocator) catch |err| {
        switch (err) {
            error.AlreadyRunning => {
                std.log.err("Another instance of waylight is already running", .{});
                return;
            },
            else => return err,
        }
    };
    defer ipc_server.deinit();

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
    global_msg_handler = &msg_handler;

    // Set hide callback (for Escape and selection)
    msg_handler.setHideCallback(&struct {
        fn hide() void {
            wayland.global_ctx.?.hide();
        }
    }.hide);

    // Set on_show callback to reset UI when window becomes visible
    wl_ctx.setOnShowCallback(&struct {
        fn onShow() void {
            if (global_msg_handler) |h| {
                h.notifyReset();
            }
        }
    }.onShow);

    // Set up message handlers for JS -> Zig communication
    try wv.setupMessageHandlers(&msg_handler);

    // Load the UI
    try wv.loadUI();

    // Realize the Wayland window with the WebView
    try wl_ctx.realize(wv.getNativeWidget());

    // Set up IPC command handler
    ipc_server.setCommandCallback(&struct {
        fn onCommand(cmd: ipc.Command) void {
            switch (cmd) {
                .toggle => wayland.global_ctx.?.toggle(),
                .quit => wayland.global_ctx.?.quit(),
                .show => wayland.global_ctx.?.show(),
                .hide => wayland.global_ctx.?.hide(),
            }
        }
    }.onCommand);

    // Integrate IPC with GLib main loop
    ipc_server.integrateWithGLib();

    // Run main event loop
    try wl_ctx.run();
}
