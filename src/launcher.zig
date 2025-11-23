const std = @import("std");

/// Launch a desktop application
pub fn launch(allocator: std.mem.Allocator, exec: []const u8) !void {
    // Parse the Exec field from .desktop file
    // %f, %F, %u, %U - file/URL arguments (we ignore these)
    // %i - icon (ignore)
    // %c - translated name (ignore)
    // %k - location of .desktop file (ignore)

    var clean_exec = std.ArrayListUnmanaged(u8){};
    defer clean_exec.deinit(allocator);

    var i: usize = 0;
    while (i < exec.len) {
        if (exec[i] == '%' and i + 1 < exec.len) {
            const next = exec[i + 1];
            // Skip field codes
            if (next == 'f' or next == 'F' or next == 'u' or next == 'U' or
                next == 'i' or next == 'c' or next == 'k' or next == 'd' or
                next == 'D' or next == 'n' or next == 'N' or next == 'v' or
                next == 'm')
            {
                i += 2;
                // Skip trailing space after field code
                while (i < exec.len and exec[i] == ' ') {
                    i += 1;
                }
                continue;
            } else if (next == '%') {
                // %% means literal %
                try clean_exec.append(allocator, '%');
                i += 2;
                continue;
            }
        }
        try clean_exec.append(allocator, exec[i]);
        i += 1;
    }

    // Trim trailing whitespace
    while (clean_exec.items.len > 0 and clean_exec.items[clean_exec.items.len - 1] == ' ') {
        _ = clean_exec.pop();
    }

    if (clean_exec.items.len == 0) {
        return error.EmptyCommand;
    }

    const command = clean_exec.items;

    // Use sh -c to handle complex commands with arguments
    const argv = [_][]const u8{
        "/bin/sh",
        "-c",
        command,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    // Spawn and detach - don't wait for the child
    try child.spawn();

    // We intentionally don't wait for the child process
    // It will be reaped by init when it exits
}
