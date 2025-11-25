const std = @import("std");
const c = @import("c.zig");

// Global context for callbacks
pub var global_ctx: ?*WaylandContext = null;

pub const WaylandContext = struct {
    allocator: std.mem.Allocator,
    window: *c.GtkWindow,
    main_loop: *c.GMainLoop,
    visible: bool = false,
    on_show: ?*const fn () void = null,

    pub fn init(allocator: std.mem.Allocator) !WaylandContext {
        // Create main loop
        const main_loop = c.g_main_loop_new(null, 0);
        if (main_loop == null) return error.MainLoopCreationFailed;

        return WaylandContext{
            .allocator = allocator,
            .window = undefined, // Will be set in realize()
            .main_loop = @ptrCast(main_loop),
        };
    }

    pub fn deinit(_: *WaylandContext) void {
        // GTK handles cleanup
    }

    pub fn realize(self: *WaylandContext, gtk_widget: *c.GtkWidget) !void {
        // Create GTK4 window
        self.window = @ptrCast(c.gtk_window_new());
        c.gtk_window_set_decorated(self.window, 0);
        c.gtk_window_set_default_size(self.window, 640, 610);
        c.gtk_window_set_child(self.window, gtk_widget);

        // Make window transparent with CSS
        const css_provider = c.gtk_css_provider_new();
        c.gtk_css_provider_load_from_string(css_provider, "window { background: transparent; }");
        const display = c.gtk_widget_get_display(@ptrCast(self.window));
        c.gtk_style_context_add_provider_for_display(
            display,
            @ptrCast(css_provider),
            c.GTK_STYLE_PROVIDER_PRIORITY_APPLICATION,
        );

        // Initialize layer-shell for this window
        c.gtk_layer_init_for_window(self.window);

        // Configure layer-shell
        // Set to overlay layer (top layer)
        c.gtk_layer_set_layer(self.window, c.GTK_LAYER_SHELL_LAYER_OVERLAY);

        // Set keyboard interactivity to exclusive (capture all keyboard input)
        c.gtk_layer_set_keyboard_mode(self.window, c.GTK_LAYER_SHELL_KEYBOARD_MODE_EXCLUSIVE);

        // Don't anchor to any edges (this centers the window)
        c.gtk_layer_set_anchor(self.window, c.GTK_LAYER_SHELL_EDGE_TOP, 0);
        c.gtk_layer_set_anchor(self.window, c.GTK_LAYER_SHELL_EDGE_BOTTOM, 0);
        c.gtk_layer_set_anchor(self.window, c.GTK_LAYER_SHELL_EDGE_LEFT, 0);
        c.gtk_layer_set_anchor(self.window, c.GTK_LAYER_SHELL_EDGE_RIGHT, 0);

        // Set top margin (100px from top)
        c.gtk_layer_set_margin(self.window, c.GTK_LAYER_SHELL_EDGE_TOP, 100);

        // Set namespace
        c.gtk_layer_set_namespace(self.window, "waylight");

        // Add keyboard event controller for Escape key
        const key_controller = c.gtk_event_controller_key_new();
        _ = c.g_signal_connect_data(
            key_controller,
            "key-pressed",
            @ptrCast(&onKeyPressed),
            self,
            null,
            0,
        );
        c.gtk_widget_add_controller(@ptrCast(self.window), key_controller);

        // Initialize window as hidden (will be shown via toggle)
        c.gtk_widget_set_visible(@ptrCast(self.window), 0);
    }

    // Static callback for key press events
    fn onKeyPressed(
        _: *c.GtkEventControllerKey,
        keyval: c_uint,
        _: c_uint,
        _: c_uint,
        user_data: ?*anyopaque,
    ) callconv(.c) c_int {
        if (keyval == c.GDK_KEY_Escape) {
            if (user_data) |data| {
                const ctx: *WaylandContext = @ptrCast(@alignCast(data));
                ctx.hide();
            }
            return 1; // Event handled
        }
        return 0; // Event not handled
    }

    pub fn run(self: *WaylandContext) !void {
        c.g_main_loop_run(self.main_loop);
    }

    pub fn quit(self: *WaylandContext) void {
        c.g_main_loop_quit(self.main_loop);
    }

    pub fn show(self: *WaylandContext) void {
        if (self.visible) return;
        c.gtk_widget_set_visible(@ptrCast(self.window), 1);
        c.gtk_window_present(self.window);
        self.visible = true;
        // Notify handler to reset UI
        if (self.on_show) |callback| {
            callback();
        }
    }

    pub fn hide(self: *WaylandContext) void {
        if (!self.visible) return;
        c.gtk_widget_set_visible(@ptrCast(self.window), 0);
        self.visible = false;
    }

    pub fn toggle(self: *WaylandContext) void {
        if (self.visible) {
            self.hide();
        } else {
            self.show();
        }
    }

    pub fn setOnShowCallback(self: *WaylandContext, callback: *const fn () void) void {
        self.on_show = callback;
    }
};
