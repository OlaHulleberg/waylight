const std = @import("std");

/// Calculator result
pub const CalcResult = struct {
    query: []const u8,
    result: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CalcResult) void {
        self.allocator.free(self.query);
        self.allocator.free(self.result);
    }
};

/// Detect if a query looks like a math expression
pub fn isMathExpression(query: []const u8) bool {
    if (query.len == 0) return false;

    // Quick check - must contain at least one digit or mathematical function
    var has_digit = false;
    var has_operator = false;

    for (query) |char| {
        if (std.ascii.isDigit(char)) {
            has_digit = true;
        } else if (char == '+' or char == '-' or char == '*' or char == '/' or
            char == '^' or char == '(' or char == ')' or char == '=' or char == '%')
        {
            has_operator = true;
        }
    }

    // Simple expression: has digit and operator
    if (has_digit and has_operator) return true;

    // Check for common math functions
    const math_keywords = [_][]const u8{
        "sqrt",  "sin",   "cos",   "tan",  "log",   "ln",
        "exp",   "abs",   "floor", "ceil", "round", "pi",
        "e",     "to ",   " to ",  "in ",  " in ",  "mod",
        "and",   "or",    "xor",   "not",  "hex",   "bin",
        "oct",   "deg",   "rad",   "km",   "mi",    "cm",
        "mm",    "inch",  "ft",    "kg",   "lb",    "oz",
        "g",     "mg",    "liter", "gal",  "ml",    "usd",
        "eur",   "gbp",   "jpy",   "btc",
    };

    const query_lower = blk: {
        var buf: [256]u8 = undefined;
        const len = @min(query.len, buf.len);
        for (query[0..len], 0..) |c, i| {
            buf[i] = std.ascii.toLower(c);
        }
        break :blk buf[0..len];
    };

    for (math_keywords) |keyword| {
        if (std.mem.indexOf(u8, query_lower, keyword) != null) {
            return true;
        }
    }

    // If it's just a number, it could be a conversion
    if (has_digit) {
        // Check if query starts with a number (potential unit conversion)
        var i: usize = 0;
        while (i < query.len and (std.ascii.isDigit(query[i]) or query[i] == '.' or query[i] == ',')) {
            i += 1;
        }
        // If we have a number followed by a space and more text, it might be a unit
        if (i > 0 and i < query.len and query[i] == ' ') {
            return true;
        }
    }

    return false;
}

/// Evaluate a math expression using qalc
pub fn evaluate(allocator: std.mem.Allocator, query: []const u8) !CalcResult {
    const result = try runQalc(allocator, query);
    errdefer allocator.free(result);

    return CalcResult{
        .query = try allocator.dupe(u8, query),
        .result = result,
        .allocator = allocator,
    };
}

fn runQalc(allocator: std.mem.Allocator, expression: []const u8) ![]const u8 {
    // Build qalc command with -t flag for terse output
    const argv = [_][]const u8{
        "qalc",
        "-t", // terse output (just the result)
        expression,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Read stdout
    var stdout_buf: [4096]u8 = undefined;
    const stdout_bytes = child.stdout.?.readAll(&stdout_buf) catch 0;

    const term = try child.wait();

    if (term.Exited != 0) {
        return error.QalcFailed;
    }

    // Trim whitespace from result
    const result = std.mem.trim(u8, stdout_buf[0..stdout_bytes], " \t\r\n");
    if (result.len == 0) {
        return error.EmptyResult;
    }

    return try allocator.dupe(u8, result);
}

/// Format calculator result as JSON
pub fn formatResultJson(allocator: std.mem.Allocator, calc: *const CalcResult) ![]u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);
    const writer = result.writer(allocator);

    try writer.writeAll("{\"type\":\"results\",\"results\":[{\"type\":\"calc\",\"query\":\"");
    try writeJsonEscaped(writer, calc.query);
    try writer.writeAll("\",\"value\":\"");
    try writeJsonEscaped(writer, calc.result);
    try writer.writeAll("\"}]}");

    return result.toOwnedSlice(allocator);
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
