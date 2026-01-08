const std = @import("std");
const c = @import("c.zig");
const posix = std.posix;

/// Watches .desktop file directories for changes using inotify.
/// Integrates with GLib main loop and debounces rapid changes.
pub const DesktopWatcher = struct {
    allocator: std.mem.Allocator,
    inotify_fd: posix.fd_t,
    watch_descriptors: std.ArrayListUnmanaged(WatchEntry),
    gio_channel: ?*c.GIOChannel = null,
    watch_id: c_uint = 0,
    debounce_timeout_id: c_uint = 0,
    on_change: ?*const fn () void = null,
    pending_reload: bool = false,

    const WatchEntry = struct {
        wd: i32,
        path: []const u8,
    };

    // Debounce delay in milliseconds
    const DEBOUNCE_MS: c_uint = 300;

    pub fn init(allocator: std.mem.Allocator) !DesktopWatcher {
        const fd = try posix.inotify_init1(.{ .NONBLOCK = true, .CLOEXEC = true });
        errdefer posix.close(fd);

        return DesktopWatcher{
            .allocator = allocator,
            .inotify_fd = fd,
            .watch_descriptors = .{},
        };
    }

    pub fn deinit(self: *DesktopWatcher) void {
        // Cancel pending debounce timer
        if (self.debounce_timeout_id != 0) {
            _ = c.g_source_remove(self.debounce_timeout_id);
        }

        // Remove GLib watch
        if (self.watch_id != 0) {
            _ = c.g_source_remove(self.watch_id);
        }
        if (self.gio_channel) |channel| {
            c.g_io_channel_unref(channel);
        }

        // Remove inotify watches
        for (self.watch_descriptors.items) |entry| {
            _ = posix.inotify_rm_watch(self.inotify_fd, entry.wd);
            self.allocator.free(entry.path);
        }
        self.watch_descriptors.deinit(self.allocator);

        posix.close(self.inotify_fd);
    }

    /// Set callback for when desktop files change
    pub fn setChangeCallback(self: *DesktopWatcher, callback: *const fn () void) void {
        self.on_change = callback;
    }

    /// Add all standard .desktop directories to watch
    pub fn watchDesktopDirs(self: *DesktopWatcher) !void {
        const dirs = [_][]const u8{
            "/usr/share/applications",
            "/usr/local/share/applications",
        };

        for (dirs) |dir| {
            self.addWatch(dir) catch |err| {
                std.log.debug("Could not watch {s}: {}", .{ dir, err });
            };
        }

        // Watch user directory (~/.local/share/applications)
        if (std.posix.getenv("HOME")) |home| {
            var buf: [512]u8 = undefined;
            const user_dir = std.fmt.bufPrint(&buf, "{s}/.local/share/applications", .{home}) catch return;
            self.addWatch(user_dir) catch |err| {
                std.log.debug("Could not watch {s}: {}", .{ user_dir, err });
            };
        }
    }

    fn addWatch(self: *DesktopWatcher, path: []const u8) !void {
        // Check if directory exists
        std.fs.accessAbsolute(path, .{}) catch return error.DirectoryNotFound;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        @memcpy(path_buf[0..path.len], path);
        path_buf[path.len] = 0;

        const wd = try posix.inotify_add_watch(
            self.inotify_fd,
            path_buf[0..path.len :0],
            std.os.linux.IN{ .CREATE = true, .DELETE = true, .MODIFY = true, .MOVED_FROM = true, .MOVED_TO = true, .CLOSE_WRITE = true },
        );

        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        try self.watch_descriptors.append(self.allocator, .{
            .wd = wd,
            .path = path_copy,
        });

        std.log.info("Watching for .desktop changes: {s}", .{path});
    }

    /// Integrate with GLib main loop
    pub fn integrateWithGLib(self: *DesktopWatcher) void {
        self.gio_channel = c.g_io_channel_unix_new(self.inotify_fd);
        self.watch_id = c.g_io_add_watch(
            self.gio_channel,
            c.G_IO_IN | c.G_IO_ERR | c.G_IO_HUP,
            onInotifyReady,
            self,
        );
    }

    fn onInotifyReady(
        _: ?*c.GIOChannel,
        _: c_uint,
        user_data: ?*anyopaque,
    ) callconv(.c) c_int {
        const self: *DesktopWatcher = @ptrCast(@alignCast(user_data));
        self.processEvents();
        return 1; // Keep watching
    }

    fn processEvents(self: *DesktopWatcher) void {
        var buf: [4096]u8 align(@alignOf(InotifyEvent)) = undefined;

        while (true) {
            const n = posix.read(self.inotify_fd, &buf) catch |err| {
                if (err == error.WouldBlock) break;
                std.log.err("inotify read error: {}", .{err});
                break;
            };

            if (n == 0) break;

            var offset: usize = 0;
            while (offset < n) {
                const event: *const InotifyEvent = @ptrCast(@alignCast(&buf[offset]));
                offset += @sizeOf(InotifyEvent) + event.len;

                // Check if it's a .desktop file
                if (event.len > 0) {
                    const name_ptr: [*]const u8 = @ptrCast(&event.name);
                    const name = std.mem.sliceTo(name_ptr, 0);

                    if (std.mem.endsWith(u8, name, ".desktop")) {
                        self.scheduleReload();
                        return; // One reload handles all pending changes
                    }
                }
            }
        }
    }

    fn scheduleReload(self: *DesktopWatcher) void {
        // If already pending, don't add another timer
        if (self.pending_reload) return;

        self.pending_reload = true;

        // Cancel any existing debounce timer
        if (self.debounce_timeout_id != 0) {
            _ = c.g_source_remove(self.debounce_timeout_id);
        }

        // Schedule debounced reload
        self.debounce_timeout_id = c.g_timeout_add(DEBOUNCE_MS, onDebounceTimeout, self);
    }

    fn onDebounceTimeout(user_data: ?*anyopaque) callconv(.c) c_int {
        const self: *DesktopWatcher = @ptrCast(@alignCast(user_data));
        self.debounce_timeout_id = 0;
        self.pending_reload = false;

        std.log.info("Desktop files changed, reloading...", .{});

        if (self.on_change) |callback| {
            callback();
        }

        return 0; // Don't repeat
    }
};

// inotify_event structure
const InotifyEvent = extern struct {
    wd: i32,
    mask: u32,
    cookie: u32,
    len: u32,
    name: [0]u8, // Variable length
};
