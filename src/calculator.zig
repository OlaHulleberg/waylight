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

    // Check for digit + operator
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

    // Lowercase the query for keyword matching
    var buf: [256]u8 = undefined;
    const len = @min(query.len, buf.len);
    for (query[0..len], 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    const query_lower = buf[0..len];

    // Standalone math keywords - must match as whole words
    const standalone_keywords = [_][]const u8{
        "pi", "e", "sqrt", "sin", "cos", "tan", "log", "ln", "exp",
        "abs", "floor", "ceil", "round", "hex", "bin", "oct",
        "deg", "rad", "mod", "and", "or", "xor", "not",
    };

    for (standalone_keywords) |keyword| {
        if (isWholeWord(query_lower, keyword)) return true;
    }

    // Unit keywords - only match if preceded by digit
    const unit_keywords = [_][]const u8{
        "g", "kg", "mg", "lb", "oz", "km", "mi", "cm", "mm", "m",
        "ft", "inch", "liter", "gal", "ml", "usd", "eur", "gbp", "jpy", "btc",
    };

    if (has_digit) {
        for (unit_keywords) |keyword| {
            if (hasUnitAfterNumber(query_lower, keyword)) return true;
        }
    }

    // Number followed by " to " or " in " (unit conversion like "5 kg to g")
    if (has_digit and std.mem.indexOf(u8, query_lower, " to ") != null) return true;
    if (has_digit and std.mem.indexOf(u8, query_lower, " in ") != null) return true;

    return false;
}

/// Check if word appears as a whole word in text (not as substring of another word)
fn isWholeWord(text: []const u8, word: []const u8) bool {
    if (std.mem.eql(u8, text, word)) return true;

    var i: usize = 0;
    while (std.mem.indexOfPos(u8, text, i, word)) |pos| {
        const before_ok = pos == 0 or !std.ascii.isAlphanumeric(text[pos - 1]);
        const after_pos = pos + word.len;
        const after_ok = after_pos >= text.len or !std.ascii.isAlphanumeric(text[after_pos]);
        if (before_ok and after_ok) return true;
        i = pos + 1;
    }
    return false;
}

/// Check if unit appears directly after a digit
fn hasUnitAfterNumber(text: []const u8, unit: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, text, i, unit)) |pos| {
        if (pos > 0 and std.ascii.isDigit(text[pos - 1])) {
            const after_pos = pos + unit.len;
            const after_ok = after_pos >= text.len or !std.ascii.isAlphanumeric(text[after_pos]);
            if (after_ok) return true;
        }
        i = pos + 1;
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
