const std = @import("std");
const c = @import("c.zig");
const posix = std.posix;

pub const Command = enum(u8) {
    toggle = 0x01,
    quit = 0x02,
    show = 0x03,
    hide = 0x04,
};

pub const IpcError = error{
    SocketCreationFailed,
    BindFailed,
    ListenFailed,
    ConnectFailed,
    AlreadyRunning,
    SendFailed,
};

/// Get socket path, using XDG_RUNTIME_DIR or fallback
fn getSocketPath(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("XDG_RUNTIME_DIR")) |runtime_dir| {
        return std.fmt.allocPrint(allocator, "{s}/waylight.sock", .{runtime_dir});
    }
    const uid = std.os.linux.getuid();
    return std.fmt.allocPrint(allocator, "/tmp/waylight-{d}.sock", .{uid});
}

// ============================================================================
// IPC Server (runs in daemon)
// ============================================================================

pub const IpcServer = struct {
    allocator: std.mem.Allocator,
    socket_fd: posix.socket_t,
    socket_path: []const u8,
    gio_channel: ?*c.GIOChannel = null,
    watch_id: c_uint = 0,
    on_command: ?*const fn (Command) void = null,

    pub fn init(allocator: std.mem.Allocator) !IpcServer {
        const socket_path = try getSocketPath(allocator);
        errdefer allocator.free(socket_path);

        // Check for stale socket
        if (tryConnect(socket_path)) {
            allocator.free(socket_path);
            return IpcError.AlreadyRunning;
        }

        // Remove stale socket file if it exists
        std.fs.deleteFileAbsolute(socket_path) catch {};

        // Create socket
        const fd = posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0) catch {
            return IpcError.SocketCreationFailed;
        };
        errdefer posix.close(fd);

        // Bind to path
        var addr: posix.sockaddr.un = .{
            .family = posix.AF.UNIX,
            .path = undefined,
        };
        @memset(&addr.path, 0);
        const path_bytes = socket_path[0..@min(socket_path.len, addr.path.len - 1)];
        @memcpy(addr.path[0..path_bytes.len], path_bytes);

        posix.bind(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un)) catch {
            return IpcError.BindFailed;
        };

        // Listen
        posix.listen(fd, 5) catch {
            return IpcError.ListenFailed;
        };

        return IpcServer{
            .allocator = allocator,
            .socket_fd = fd,
            .socket_path = socket_path,
        };
    }

    pub fn deinit(self: *IpcServer) void {
        // Remove GLib watch
        if (self.watch_id != 0) {
            _ = c.g_source_remove(self.watch_id);
        }
        if (self.gio_channel) |channel| {
            c.g_io_channel_unref(channel);
        }

        // Close socket and remove file
        posix.close(self.socket_fd);
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
        self.allocator.free(self.socket_path);
    }

    pub fn setCommandCallback(self: *IpcServer, callback: *const fn (Command) void) void {
        self.on_command = callback;
    }

    /// Integrate with GLib main loop
    pub fn integrateWithGLib(self: *IpcServer) void {
        self.gio_channel = c.g_io_channel_unix_new(self.socket_fd);
        self.watch_id = c.g_io_add_watch(
            self.gio_channel,
            c.G_IO_IN | c.G_IO_ERR | c.G_IO_HUP,
            onSocketReady,
            self,
        );
    }

    fn onSocketReady(
        _: ?*c.GIOChannel,
        _: c_uint,
        user_data: ?*anyopaque,
    ) callconv(.c) c_int {
        const self: *IpcServer = @ptrCast(@alignCast(user_data));

        // Accept connection
        const client_fd = posix.accept(self.socket_fd, null, null, 0) catch {
            return 1; // Keep watching
        };
        defer posix.close(client_fd);

        // Read command (single byte)
        var buf: [1]u8 = undefined;
        const n = posix.read(client_fd, &buf) catch {
            return 1;
        };

        if (n == 1) {
            if (std.meta.intToEnum(Command, buf[0])) |cmd| {
                if (self.on_command) |callback| {
                    callback(cmd);
                }
            } else |_| {}
        }

        return 1; // Keep watching
    }
};

// ============================================================================
// IPC Client (runs in waylight --toggle)
// ============================================================================

pub const IpcClient = struct {
    /// Check if daemon is running by trying to connect
    pub fn isDaemonRunning(allocator: std.mem.Allocator) bool {
        const socket_path = getSocketPath(allocator) catch return false;
        defer allocator.free(socket_path);
        return tryConnect(socket_path);
    }

    /// Send a command to the running daemon
    pub fn sendCommand(allocator: std.mem.Allocator, cmd: Command) !void {
        const socket_path = try getSocketPath(allocator);
        defer allocator.free(socket_path);

        // Create socket
        const fd = posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0) catch {
            return IpcError.SocketCreationFailed;
        };
        defer posix.close(fd);

        // Connect
        var addr: posix.sockaddr.un = .{
            .family = posix.AF.UNIX,
            .path = undefined,
        };
        @memset(&addr.path, 0);
        const path_bytes = socket_path[0..@min(socket_path.len, addr.path.len - 1)];
        @memcpy(addr.path[0..path_bytes.len], path_bytes);

        posix.connect(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un)) catch {
            return IpcError.ConnectFailed;
        };

        // Send command
        const buf = [_]u8{@intFromEnum(cmd)};
        _ = posix.write(fd, &buf) catch {
            return IpcError.SendFailed;
        };
    }
};

/// Try to connect to socket, returns true if successful (daemon running)
fn tryConnect(socket_path: []const u8) bool {
    const fd = posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0) catch return false;
    defer posix.close(fd);

    var addr: posix.sockaddr.un = .{
        .family = posix.AF.UNIX,
        .path = undefined,
    };
    @memset(&addr.path, 0);
    const path_bytes = socket_path[0..@min(socket_path.len, addr.path.len - 1)];
    @memcpy(addr.path[0..path_bytes.len], path_bytes);

    posix.connect(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un)) catch return false;
    return true;
}
