const std = @import("std");
const mem = std.mem;

pub fn main() void {}

/// Token identifies a text and the kind of token it represents.
const Token = struct {
    /// The specific atom this token represents.
    kind: TokenType,

    /// The particular text associated with this token when it was parsed.
    text: []const u8,

    pub fn init(kind: TokenType, text: []const u8) Token {
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

const TokenType = enum(u8) {
    eof = 1,
    lbrack,
    rbrack,
    alias,
    path,
    glob,
};

test "test token" {
    const testing = std.testing;
    const test_allocator = std.testing.allocator;

    const test_cases = [_]struct {
        args: struct { kind: TokenType, text: []const u8 },
        expected: []const u8,
    }{
        .{
            .args = .{ .kind = .eof, .text = "<EOF>" },
            .expected = "<'<EOF>', <EOF>>",
        },
        .{
            .args = .{ .kind = .lbrack, .text = "LBRACK" },
            .expected = "<'LBRACK', LBRACK>",
        },
        .{
            .args = .{ .kind = .rbrack, .text = "RBRACK" },
            .expected = "<'RBRACK', RBRACK>",
        },
        .{
            .args = .{ .kind = .alias, .text = "ALIAS" },
            .expected = "<'ALIAS', ALIAS>",
        },
        .{
            .args = .{ .kind = .path, .text = "PATH" },
            .expected = "<'PATH', PATH>",
        },
        .{
            .args = .{ .kind = .glob, .text = "GLOB" },
            .expected = "<'GLOB', GLOB>",
        },
    };

    for (test_cases) |tc| {
        const token = Token.init(tc.args.kind, tc.args.text);
        const actual = try token.fmt(test_allocator);
        defer test_allocator.free(actual);
        try testing.expectEqualStrings(tc.expected, actual);
    }
}

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

test "test cursor" {
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
        while (i < tc.consume_count) {
            cursor.consume();
            i += 1;
        }
        try testing.expectEqualStrings(tc.expected_input, cursor.input);
        try testing.expectEqual(tc.expected_pointer, cursor.pointer);
        try testing.expectEqual(tc.expected_current_char, cursor.current_char);
    }
}
