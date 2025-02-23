const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;

pub fn main() void {}

/// Token identifies a text and the kind of token it represents.
const Token = struct {
    /// The specific atom this token represents.
    kind: TokenKind,

    /// The particular text associated with this token when it was parsed.
    text: []const u8,

    pub fn init(kind: TokenKind, text: []const u8) Token {
        return .{ .kind = kind, .text = text };
    }

    /// Formats this Token for display.
    pub fn fmt(self: Token, allocator: mem.Allocator) ![]const u8 {
        const idx = @intFromEnum(self.kind);
        return std.fmt.allocPrint(allocator, "<'{s}', {s}>", .{
            self.text,
            token_names[idx],
        });
    }
};

const token_names = [_][]const u8{
    "n/a",
    "<EOF>",
    "LBRACK",
    "RBRACK",
    "ALIAS",
    "PATH",
    "GLOB",
};

const TokenKind = enum(u8) {
    eof = 1,
    lbrack,
    rbrack,
    alias,
    path,
    glob,
};

const eof: u8 = 0;

/// Cursor allows traversing through an input String character by character while lexing.
const Cursor = struct {
    input: []const u8,
    /// The input String being processed.
    pointer: usize,
    /// The current character being processed.
    current_char: u8,

    pub fn init(input: []const u8, pointer: usize, current_char: u8) Cursor {
        return .{ .input = input, .pointer = pointer, .current_char = current_char };
    }

    /// Consumes one character moving forward and detects "end of file".
    pub fn consume(self: *Cursor) void {
        self.pointer += 1;
        if (self.pointer >= self.input.len) {
            self.current_char = eof;
            return;
        }
        self.current_char = self.input[self.pointer];
    }
};

/// Creates and identifies tokens using the underlying cursor.
const Lexer = struct {
    cursor: Cursor,
    token_names: ArrayList([]const u8),

    pub fn init(allocator: mem.Allocator, input: []const u8, pointer: usize, char: u8) !Lexer {
        var all_tokens = ArrayList([]const u8).init(allocator);
        for (token_names) |tn| {
            try all_tokens.append(tn);
        }
        return .{
            .cursor = Cursor.init(input, pointer, char),
            .token_names = all_tokens,
        };
    }

    pub fn deinit(self: Lexer) void {
        self.token_names.deinit();
    }

    pub fn token_name_at_index(self: Lexer, i: usize) []const u8 {
        if (i >= self.token_names.items.len) return "";
        return self.token_names.items[i];
    }

    pub fn is_not_end_of_line(self: Lexer) bool {
        return !(self.cursor.current_char == '\u{ff}' or
            self.cursor.current_char == '0' or
            self.cursor.current_char == '\n');
    }
};

test "expect Token formatting" {
    const testing = std.testing;
    const test_allocator = std.testing.allocator;

    const test_cases = [_]struct {
        args: struct { kind: TokenKind, text: []const u8 },
        expected: []const u8,
    }{
        .{
            .args = .{ .kind = .eof, .text = "0" },
            .expected = "<'0', <EOF>>",
        },
        .{
            .args = .{ .kind = .lbrack, .text = "[" },
            .expected = "<'[', LBRACK>",
        },
        .{
            .args = .{ .kind = .rbrack, .text = "]" },
            .expected = "<']', RBRACK>",
        },
        .{
            .args = .{ .kind = .alias, .text = "alias" },
            .expected = "<'alias', ALIAS>",
        },
        .{
            .args = .{ .kind = .path, .text = "/some/path" },
            .expected = "<'/some/path', PATH>",
        },
        .{
            .args = .{ .kind = .glob, .text = "*" },
            .expected = "<'*', GLOB>",
        },
    };

    for (test_cases) |tc| {
        const token = Token.init(tc.args.kind, tc.args.text);
        const actual = try token.fmt(test_allocator);
        defer test_allocator.free(actual);
        try testing.expectEqualStrings(tc.expected, actual);
    }
}

test "expect Cursor consumes" {
    const testing = std.testing;

    const test_cases = [_]struct {
        args: struct {
            input: []const u8,
            pointer: usize,
            current_char: u8,
        },
        expected_input: []const u8 = "",
        expected_pointer: usize = 0,
        expected_current_char: u8 = '0',
        consume_count: u8 = 1,
    }{
        // Test initialize cursor.
        .{
            .args = .{ .input = "", .pointer = 0, .current_char = '0' },
            .consume_count = 0,
        },
        // Test cursor can consume 2 characters.
        .{
            .args = .{ .input = "test", .pointer = 0, .current_char = '0' },
            .expected_input = "test",
            .expected_pointer = 2,
            .expected_current_char = 's',
            .consume_count = 2,
        },
        // Test cursor can consume characters until final character of input.
        .{
            .args = .{ .input = "test", .pointer = 0, .current_char = '0' },
            .expected_input = "test",
            .expected_pointer = 3,
            .expected_current_char = 't',
            .consume_count = 3,
        },
        // Test cursor can consume all characters in input.
        .{
            .args = .{ .input = "test", .pointer = 0, .current_char = '0' },
            .expected_input = "test",
            .expected_pointer = 4,
            .expected_current_char = 0,
            .consume_count = 4,
        },
    };

    for (test_cases) |tc| {
        var cursor = Cursor.init(tc.args.input, tc.args.pointer, tc.args.current_char);
        var i: u8 = 0;
        while (i < tc.consume_count) : (i += 1) {
            cursor.consume();
        }
        try testing.expectEqualStrings(tc.expected_input, cursor.input);
        try testing.expectEqual(tc.expected_pointer, cursor.pointer);
        try testing.expectEqual(tc.expected_current_char, cursor.current_char);
    }
}

test "expect Lexer initialization" {
    const testing = std.testing;
    const lexer = try Lexer.init(testing.allocator, "test", 0, 't');
    defer lexer.deinit();

    try testing.expectEqualDeep(token_names[0..], lexer.token_names.items);
    try testing.expectEqualStrings("test", lexer.cursor.input);
    try testing.expectEqual(0, lexer.cursor.pointer);
    try testing.expectEqual('t', lexer.cursor.current_char);
}

test "expect Lexer returns token names by index" {
    const testing = std.testing;
    const lexer = try Lexer.init(testing.allocator, "test", 0, 't');
    defer lexer.deinit();

    const test_cases = [_]struct {
        arg: usize,
        expected: []const u8,
    }{
        .{ .arg = 0, .expected = "n/a" },
        .{ .arg = 2, .expected = "LBRACK" },
        .{ .arg = token_names.len, .expected = "" },
    };

    for (test_cases) |tc| {
        const token_name = lexer.token_name_at_index(tc.arg);
        try testing.expectEqualStrings(tc.expected, token_name);
    }
}

test "expect Lexer detects end-of-line" {
    const testing = std.testing;

    const test_cases = [_]struct {
        arg: u8,
        expected: bool = false,
    }{
        .{ .arg = 't', .expected = true },
        .{ .arg = '0' },
        .{ .arg = '\n' },
        .{ .arg = '\u{ff}' },
    };

    for (test_cases) |tc| {
        const lexer = try Lexer.init(testing.allocator, "test", 0, tc.arg);
        defer lexer.deinit();
        try testing.expectEqual(tc.expected, lexer.is_not_end_of_line());
    }
}
