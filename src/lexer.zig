const std = @import("std");
const cursor = @import("cursor.zig");
const token = @import("token.zig");

const mem = std.mem;
const Allocator = mem.Allocator;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;
const fs = std.fs;
const ascii = std.ascii;
const fmt = std.fmt;

/// Creates and identifies tokens using the underlying cursor.
pub const Lexer = struct {
    allocator: Allocator,
    cursor: cursor.Cursor,

    pub fn init(allocator: Allocator, input: []const u8, pointer: usize, char: u8) !Lexer {
        const c = cursor.Cursor.init(input, pointer, char);
        return .{
            .allocator = allocator,
            .cursor = c,
        };
    }

    pub fn tokenNameAtIndex(_: Lexer, i: usize) []const u8 {
        if (i >= token.token_names.len) return "";
        return token.token_names[i];
    }

    pub fn isNotEndOfLine(self: Lexer) bool {
        return !(self.cursor.current_char == '\u{ff}' or
            self.cursor.current_char == cursor.eof or
            self.cursor.current_char == '\n' or
            self.cursor.current_char == ascii.control_code.vt or
            self.cursor.current_char == ascii.control_code.ff);
    }

    pub fn isAliasName(self: Lexer) bool {
        return ascii.isAlphanumeric(self.cursor.current_char) or
            self.cursor.current_char == cursor.underscore or
            self.cursor.current_char == cursor.hyphen;
    }

    pub fn isGlob(self: Lexer) bool {
        return self.cursor.current_char == cursor.asterisk;
    }

    pub fn whitespace(self: *Lexer) void {
        while (ascii.isWhitespace(self.cursor.current_char)) {
            self.cursor.consume();
        }
    }

    pub fn alias(self: *Lexer) !token.Token {
        var list = ArrayList(u8).init(self.allocator);
        while (self.isAliasName()) {
            try list.append(self.cursor.current_char);
            self.cursor.consume();
        }

        const text = try list.toOwnedSlice();
        return token.Token{
            .allocator = self.allocator,
            .kind = .alias,
            .text = text,
        };
    }

    pub fn path(self: *Lexer) !token.Token {
        var list = ArrayList(u8).init(self.allocator);
        defer list.deinit();

        while (self.isNotEndOfLine()) {
            try list.append(self.cursor.current_char);
            self.cursor.consume();
        }

        const text = try list.toOwnedSlice();
        return token.Token{
            .allocator = self.allocator,
            .kind = .path,
            .text = text,
        };
    }

    pub fn glob(self: *Lexer) !token.Token {
        self.cursor.consume();
        return token.Token{
            .allocator = self.allocator,
            .kind = .glob,
            .text = "*",
        };
    }

    pub fn nextToken(self: *Lexer) !token.Token {
        while (self.cursor.current_char != cursor.eof) {
            switch (self.cursor.current_char) {
                ' ',
                '\t',
                '\n',
                '\r',
                ascii.control_code.vt,
                ascii.control_code.ff,
                => {
                    self.whitespace();
                    continue;
                },
                '[' => {
                    self.cursor.consume();
                    return token.Token.init(self.allocator, .lbrack, "[");
                },
                ']' => {
                    self.cursor.consume();
                    return token.Token.init(self.allocator, .rbrack, "]");
                },
                else => {
                    // Prioritize parsing aliases over paths that **DO NOT** start with a
                    // forward slash.
                    if (self.isAliasName()) {
                        return try self.alias();
                    } else if (self.isGlob()) {
                        return try self.glob();
                    } else if (self.isNotEndOfLine()) {
                        return try self.path();
                    }
                },
            }
        }
        const idx = @intFromEnum(token.TokenKind.eof);
        return token.Token.init(self.allocator, .eof, token.token_names[idx]);
    }
};

test "expect Lexer initialization" {
    const testing = std.testing;
    const lexer = try Lexer.init(testing.allocator, "test", 0, 't');

    try testing.expectEqualStrings("test", lexer.cursor.input);
    try testing.expectEqual(0, lexer.cursor.pointer);
    try testing.expectEqual('t', lexer.cursor.current_char);
}

test "expect Lexer returns token names by index" {
    const testing = std.testing;
    const lexer = try Lexer.init(testing.allocator, "test", 0, 't');

    const test_cases = [_]struct {
        arg: usize,
        expected: []const u8,
    }{
        .{ .arg = 0, .expected = "n/a" },
        .{ .arg = 2, .expected = "LBRACK" },
        .{ .arg = token.token_names.len, .expected = "" },
    };

    for (test_cases) |tc| {
        const token_name = lexer.tokenNameAtIndex(tc.arg);
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
        .{ .arg = cursor.eof },
        .{ .arg = '\n' },
        .{ .arg = '\u{ff}' },
        .{ .arg = ascii.control_code.vt },
        .{ .arg = ascii.control_code.ff },
    };

    for (test_cases) |tc| {
        const lexer = try Lexer.init(testing.allocator, "test", 0, tc.arg);
        try testing.expectEqual(tc.expected, lexer.isNotEndOfLine());
    }
}

test "expect Lexer can check characters belong to aliases" {
    const testing = std.testing;

    const test_cases = [_]struct {
        arg: u8,
        expected: bool = false,
    }{
        .{ .arg = 't', .expected = true },
        .{ .arg = 'T', .expected = true },
        .{ .arg = '0', .expected = true },
        .{ .arg = '\n' },
        .{ .arg = '\u{ff}' },
    };

    for (test_cases) |tc| {
        const lexer = try Lexer.init(testing.allocator, "test", 0, tc.arg);
        try testing.expectEqual(tc.expected, lexer.isAliasName());
    }
}

test "expect Lexer can check asterisk is for glob aliases" {
    const testing = std.testing;

    const test_cases = [_]struct {
        arg: u8,
        expected: bool,
    }{
        .{ .arg = 't', .expected = false },
        .{ .arg = '*', .expected = true },
    };

    for (test_cases) |tc| {
        const lexer = try Lexer.init(testing.allocator, "test", 0, tc.arg);
        try testing.expectEqual(tc.expected, lexer.isGlob());
    }
}

test "expect Lexer can consume whitespace" {
    const testing = std.testing;

    const test_cases = [_]struct {
        arg: []const u8,
        expected: u8,
    }{
        .{ .arg = "test", .expected = 't' },
        .{ .arg = " test", .expected = 't' },
        .{ .arg = "   test", .expected = 't' },
        .{ .arg = "   ", .expected = cursor.eof },
    };

    for (test_cases) |tc| {
        var lexer = try Lexer.init(testing.allocator, tc.arg, 0, tc.arg[0]);
        lexer.whitespace();
        try testing.expectEqual(tc.expected, lexer.cursor.current_char);
    }
}

test "expect Lexer to consume alias tokens" {
    const testing = std.testing;

    var lexer = try Lexer.init(testing.allocator, "test", 0, 't');

    const actual = try lexer.alias();
    defer actual.deinit();

    try testing.expectEqualStrings("test", actual.text);
    try testing.expectEqual(.alias, actual.kind);
}

test "expect Lexer to consume path tokens" {
    const testing = std.testing;

    const input = "/some/test/path";
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);

    const actual = try lexer.path();
    defer actual.deinit();

    try testing.expectEqualStrings("/some/test/path", actual.text);
    try testing.expectEqual(.path, actual.kind);
}

test "expect Lexer to consume glob tokens" {
    const testing = std.testing;

    const input = "*";
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);

    const actual = try lexer.glob();
    defer actual.deinit();

    try testing.expectEqualStrings("*", actual.text);
    try testing.expectEqual(.glob, actual.kind);
}

test "expect Lexer to parse valid alias and path tokens" {
    const testing = std.testing;

    const input =
        \\[test]/some/test/path
        \\/another/test/path
    ;
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);

    var tokens = ArrayList(token.Token).init(testing.allocator);
    defer {
        for (tokens.items) |t| t.deinit();
        tokens.deinit();
    }

    while (true) {
        const t = try lexer.nextToken();
        try tokens.append(t);
        if (t.kind == .eof) {
            break;
        }
    }

    try testing.expectEqual(6, tokens.items.len);
    try testing.expectEqual(.lbrack, tokens.items[0].kind);
    try testing.expectEqualStrings("[", tokens.items[0].text);

    try testing.expectEqual(.alias, tokens.items[1].kind);
    try testing.expectEqualStrings("test", tokens.items[1].text);

    try testing.expectEqual(.rbrack, tokens.items[2].kind);
    try testing.expectEqualStrings("]", tokens.items[2].text);

    try testing.expectEqual(.path, tokens.items[3].kind);
    try testing.expectEqualStrings("/some/test/path", tokens.items[3].text);

    try testing.expectEqual(.path, tokens.items[4].kind);
    try testing.expectEqualStrings("/another/test/path", tokens.items[4].text);

    try testing.expectEqual(.eof, tokens.items[5].kind);
    try testing.expectEqualStrings("<EOF>", tokens.items[5].text);
}

test "expect Lexer to parse relative path tokens" {
    const testing = std.testing;

    const input = "some/test/path";
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);

    var tokens = ArrayList(token.Token).init(testing.allocator);
    defer {
        for (tokens.items) |t| t.deinit();
        tokens.deinit();
    }

    while (true) {
        const t = try lexer.nextToken();
        try tokens.append(t);
        if (t.kind == .eof) {
            break;
        }
    }

    try testing.expectEqual(3, tokens.items.len);
    try testing.expectEqual(.alias, tokens.items[0].kind);
    try testing.expectEqualStrings("some", tokens.items[0].text);

    try testing.expectEqual(.path, tokens.items[1].kind);
    try testing.expectEqualStrings("/test/path", tokens.items[1].text);

    try testing.expectEqual(.eof, tokens.items[2].kind);
    try testing.expectEqualStrings("<EOF>", tokens.items[2].text);
}

test "expect Lexer to parse glob token tokens" {
    const testing = std.testing;

    const input = "[*]/some/test/path";
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);

    var tokens = ArrayList(token.Token).init(testing.allocator);
    defer {
        for (tokens.items) |t| t.deinit();
        tokens.deinit();
    }

    while (true) {
        const t = try lexer.nextToken();
        try tokens.append(t);
        if (t.kind == .eof) {
            break;
        }
    }

    try testing.expectEqual(5, tokens.items.len);
    try testing.expectEqual(.lbrack, tokens.items[0].kind);
    try testing.expectEqualStrings("[", tokens.items[0].text);

    try testing.expectEqual(.glob, tokens.items[1].kind);
    try testing.expectEqualStrings("*", tokens.items[1].text);

    try testing.expectEqual(.rbrack, tokens.items[2].kind);
    try testing.expectEqualStrings("]", tokens.items[2].text);

    try testing.expectEqual(.path, tokens.items[3].kind);
    try testing.expectEqualStrings("/some/test/path", tokens.items[3].text);

    try testing.expectEqual(.eof, tokens.items[4].kind);
    try testing.expectEqualStrings("<EOF>", tokens.items[4].text);
}
