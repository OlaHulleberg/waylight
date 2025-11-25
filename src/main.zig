const std = @import("std");
const build_options = @import("build_options");
const c = @import("c.zig");
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

const Args = struct {
    mode: Mode,
    start_hidden: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = parseArgs();

    switch (args.mode) {
        .toggle => {
            // Try to signal existing daemon
            if (ipc.IpcClient.isDaemonRunning(allocator)) {
                ipc.IpcClient.sendCommand(allocator, .toggle) catch {
                    // Failed to send, try starting daemon
                    try runDaemon(allocator, false);
                };
            } else {
                // No daemon running, start one (visible since user wants to toggle)
                try runDaemon(allocator, false);
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
            try runDaemon(allocator, args.start_hidden);
        },
    }
}

fn parseArgs() Args {
    var args = std.process.args();
    _ = args.skip(); // Skip program name

    var start_hidden = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--toggle") or std.mem.eql(u8, arg, "-t")) {
            return .{ .mode = .toggle, .start_hidden = false };
        } else if (std.mem.eql(u8, arg, "--quit") or std.mem.eql(u8, arg, "-q")) {
            return .{ .mode = .quit_daemon, .start_hidden = false };
        } else if (std.mem.eql(u8, arg, "--daemon") or std.mem.eql(u8, arg, "-d")) {
            start_hidden = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        }
    }

    return .{ .mode = .daemon, .start_hidden = start_hidden };
}

fn printUsage() void {
    std.debug.print(
        \\Usage: waylight [OPTIONS]
        \\
        \\Options:
        \\  --daemon, -d    Start daemon in background (hidden)
        \\  --toggle, -t    Toggle window visibility (starts daemon if not running)
        \\  --quit, -q      Quit the running daemon
        \\  --help, -h      Show this help message
        \\
        \\Without options, starts daemon and shows the window.
        \\
    , .{});
}

// Global handler for IPC callbacks
var global_msg_handler: ?*handler.Handler = null;

fn runDaemon(allocator: std.mem.Allocator, start_hidden: bool) !void {
    // Set GTK input method to simple context for proper dead key handling
    _ = c.g_setenv("GTK_IM_MODULE", "gtk-im-context-simple", 1);

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

    // Schedule window to show once main loop starts (unless started as daemon)
    if (!start_hidden) {
        wl_ctx.scheduleShow();
    }

    // Run main event loop
    try wl_ctx.run();
}
