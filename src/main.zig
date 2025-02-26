const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ascii = std.ascii;
const ArrayList = std.ArrayList;
const AutoArrayHashMap = std.AutoArrayHashMap;

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
    pub fn fmt(self: Token, allocator: Allocator) ![]const u8 {
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
const underscore = '_';
const hyphen = '-';
const asterisk = '*';

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

    pub fn init(allocator: Allocator, input: []const u8, pointer: usize, char: u8) !Lexer {
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

    pub fn tokenNameAtIndex(self: Lexer, i: usize) []const u8 {
        if (i >= self.token_names.items.len) return "";
        return self.token_names.items[i];
    }

    pub fn isNotEndOfLine(self: Lexer) bool {
        return !(self.cursor.current_char == '\u{ff}' or
            self.cursor.current_char == eof or
            self.cursor.current_char == '\n');
    }

    pub fn isAliasName(self: Lexer) bool {
        return ascii.isAlphanumeric(self.cursor.current_char) or
            self.cursor.current_char == underscore or
            self.cursor.current_char == hyphen;
    }

    pub fn isGlob(self: Lexer) bool {
        return self.cursor.current_char == asterisk;
    }

    pub fn whitespace(self: *Lexer) void {
        while (ascii.isWhitespace(self.cursor.current_char)) {
            self.cursor.consume();
        }
    }

    pub fn alias(self: *Lexer, allocator: Allocator) !Token {
        var list = ArrayList(u8).init(allocator);
        while (self.isAliasName()) {
            try list.append(self.cursor.current_char);
            self.cursor.consume();
        }
        return .{
            .kind = .alias,
            .text = try list.toOwnedSlice(),
        };
    }

    pub fn path(self: *Lexer, allocator: Allocator) !Token {
        var list = ArrayList(u8).init(allocator);
        while (self.isNotEndOfLine()) {
            try list.append(self.cursor.current_char);
            self.cursor.consume();
        }
        return .{
            .kind = .path,
            .text = try list.toOwnedSlice(),
        };
    }

    pub fn glob(self: *Lexer, allocator: Allocator) !Token {
        var list = ArrayList(u8).init(allocator);
        try list.append(self.cursor.current_char);
        self.cursor.consume();
        return .{
            .kind = .glob,
            .text = try list.toOwnedSlice(),
        };
    }

    pub fn nextToken(self: *Lexer, allocator: Allocator) !Token {
        while (self.cursor.current_char != eof) {
            switch (self.cursor.current_char) {
                ' ', '\t', '\n', '\r' => {
                    self.whitespace();
                    continue;
                },
                '[' => {
                    self.cursor.consume();
                    return Token.init(.lbrack, "[");
                },
                ']' => {
                    self.cursor.consume();
                    return Token.init(.rbrack, "]");
                },
                else => {
                    // Prioritize parsing aliases over paths that **DO NOT** start with a
                    // forward slash.
                    if (self.isAliasName()) {
                        return try self.alias(allocator);
                    } else if (self.isGlob()) {
                        return try self.glob(allocator);
                    } else if (self.isNotEndOfLine()) {
                        return try self.path(allocator);
                    }
                },
            }
        }
        const idx = @intFromEnum(TokenKind.eof);
        return Token.init(.eof, token_names[idx]);
    }
};

const ParserError = error{
    EmptyInput,
    LexerInitFailed,
    LexerNextTokenFailed,
};

pub const Parser = struct {
    allocator: Allocator,
    /// The lexer responsible for returning tokenized input.
    input: Lexer,
    /// The current lookahead token used by this parser.
    lookahead: Token,
    /// The internal representation of a parsed configuration file.
    int_rep: AutoArrayHashMap([]const u8, []const u8),

    pub fn init(allocator: Allocator, s: []const u8) ParserError!Parser {
        const trimmed_s = mem.trim(u8, s, " ");
        if (trimmed_s.len == 0) {
            return ParserError.EmptyInput;
        }

        var lexer = Lexer.init(allocator, s, 0, s[0]) catch return ParserError.LexerInitFailed;
        const lookahead = lexer.nextToken(allocator) catch return ParserError.LexerNextTokenFailed;

        return .{
            .allocator = allocator,
            .input = lexer,
            .lookahead = lookahead,
            .int_rep = AutoArrayHashMap([]const u8, []const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.int_rep.deinit();
        self.input.deinit();
        self.allocator.free(self.lookahead.text);
    }
};

test "expect Token formatting" {
    const testing = std.testing;

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
        const actual = try token.fmt(testing.allocator);
        defer testing.allocator.free(actual);
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
        .{ .arg = eof },
        .{ .arg = '\n' },
        .{ .arg = '\u{ff}' },
    };

    for (test_cases) |tc| {
        const lexer = try Lexer.init(testing.allocator, "test", 0, tc.arg);
        defer lexer.deinit();
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
        defer lexer.deinit();
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
        defer lexer.deinit();
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
        .{ .arg = "   ", .expected = eof },
    };

    for (test_cases) |tc| {
        var lexer = try Lexer.init(testing.allocator, tc.arg, 0, tc.arg[0]);
        defer lexer.deinit();
        lexer.whitespace();
        try testing.expectEqual(tc.expected, lexer.cursor.current_char);
    }
}

test "expect Lexer to consume alias tokens" {
    const testing = std.testing;

    var lexer = try Lexer.init(testing.allocator, "test", 0, 't');
    defer lexer.deinit();

    const actual = try lexer.alias(testing.allocator);
    defer {
        testing.allocator.free(actual.text);
    }

    try testing.expectEqualStrings("test", actual.text);
    try testing.expectEqual(TokenKind.alias, actual.kind);
}

test "expect Lexer to consume path tokens" {
    const testing = std.testing;

    const input = "/some/test/path";
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);
    defer lexer.deinit();

    const actual = try lexer.path(testing.allocator);
    defer {
        testing.allocator.free(actual.text);
    }

    try testing.expectEqualStrings("/some/test/path", actual.text);
    try testing.expectEqual(TokenKind.path, actual.kind);
}

test "expect Lexer to consume glob tokens" {
    const testing = std.testing;

    const input = "*";
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);
    defer lexer.deinit();

    const actual = try lexer.glob(testing.allocator);
    defer {
        testing.allocator.free(actual.text);
    }

    try testing.expectEqualStrings("*", actual.text);
    try testing.expectEqual(TokenKind.glob, actual.kind);
}

test "expect Lexer to parse valid alias and path tokens" {
    const testing = std.testing;

    const input =
        \\[test]/some/test/path
        \\/another/test/path
    ;
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);
    defer lexer.deinit();

    var tokens = ArrayList(Token).init(testing.allocator);
    defer {
        for (tokens.items, 0..) |token, i| {
            // Skip freeing memory for LBRACK, RBRACK, and <EOF>
            if (i == 0 or i == 2 or i == tokens.items.len - 1) continue;
            testing.allocator.free(token.text);
        }
        tokens.deinit();
    }

    while (true) {
        const token = try lexer.nextToken(testing.allocator);
        try tokens.append(token);
        if (token.kind == .eof) {
            break;
        }
    }

    try testing.expectEqual(6, tokens.items.len);
    try testing.expectEqual(tokens.items[0].kind, .lbrack);
    try testing.expectEqualStrings(tokens.items[0].text, "[");

    try testing.expectEqual(tokens.items[1].kind, .alias);
    try testing.expectEqualStrings(tokens.items[1].text, "test");

    try testing.expectEqual(tokens.items[2].kind, .rbrack);
    try testing.expectEqualStrings(tokens.items[2].text, "]");

    try testing.expectEqual(tokens.items[3].kind, .path);
    try testing.expectEqualStrings(tokens.items[3].text, "/some/test/path");

    try testing.expectEqual(tokens.items[4].kind, .path);
    try testing.expectEqualStrings(tokens.items[4].text, "/another/test/path");

    try testing.expectEqual(tokens.items[5].kind, .eof);
    try testing.expectEqualStrings(tokens.items[5].text, "<EOF>");
}

test "expect Lexer to parse invalid path tokens" {
    const testing = std.testing;

    const input = "some/test/path";
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);
    defer lexer.deinit();

    var tokens = ArrayList(Token).init(testing.allocator);
    defer {
        for (tokens.items, 0..) |token, i| {
            // Skip <EOF>
            if (i == tokens.items.len - 1) continue;
            testing.allocator.free(token.text);
        }
        tokens.deinit();
    }

    while (true) {
        const token = try lexer.nextToken(testing.allocator);
        try tokens.append(token);
        if (token.kind == .eof) {
            break;
        }
    }

    try testing.expectEqual(3, tokens.items.len);
    try testing.expectEqual(tokens.items[0].kind, .alias);
    try testing.expectEqualStrings(tokens.items[0].text, "some");

    try testing.expectEqual(tokens.items[1].kind, .path);
    try testing.expectEqualStrings(tokens.items[1].text, "/test/path");

    try testing.expectEqual(tokens.items[2].kind, .eof);
    try testing.expectEqualStrings(tokens.items[2].text, "<EOF>");
}

test "expect Lexer to parse glob token tokens" {
    const testing = std.testing;

    const input = "[*]/some/test/path";
    var lexer = try Lexer.init(testing.allocator, input, 0, input[0]);
    defer lexer.deinit();

    var tokens = ArrayList(Token).init(testing.allocator);
    defer {
        for (tokens.items, 0..) |token, i| {
            // Skip freeing memory for LBRACK, RBRACK, and <EOF>
            if (i == 0 or i == 2 or i == tokens.items.len - 1) continue;
            testing.allocator.free(token.text);
        }
        tokens.deinit();
    }

    while (true) {
        const token = try lexer.nextToken(testing.allocator);
        try tokens.append(token);
        if (token.kind == .eof) {
            break;
        }
    }

    try testing.expectEqual(5, tokens.items.len);
    try testing.expectEqual(tokens.items[0].kind, .lbrack);
    try testing.expectEqualStrings(tokens.items[0].text, "[");

    try testing.expectEqual(tokens.items[1].kind, .glob);
    try testing.expectEqualStrings(tokens.items[1].text, "*");

    try testing.expectEqual(tokens.items[2].kind, .rbrack);
    try testing.expectEqualStrings(tokens.items[2].text, "]");

    try testing.expectEqual(tokens.items[3].kind, .path);
    try testing.expectEqualStrings(tokens.items[3].text, "/some/test/path");

    try testing.expectEqual(tokens.items[4].kind, .eof);
    try testing.expectEqualStrings(tokens.items[4].text, "<EOF>");
}

test "expect Parser is created successfully" {
    const testing = std.testing;

    var parser = try Parser.init(testing.allocator, "test");
    defer parser.deinit();

    try testing.expectEqual(0, parser.int_rep.values().len);
    try testing.expectEqualStrings("test", parser.input.cursor.input);
    try testing.expectEqual(4, parser.input.cursor.pointer);
    try testing.expectEqual(eof, parser.input.cursor.current_char);
    try testing.expectEqualDeep(Token.init(.alias, "test"), parser.lookahead);
}

test "expect Parser initialization fails when input is the empty string or blank" {
    const testing = std.testing;

    {
        const parser = Parser.init(testing.allocator, "");
        try testing.expectError(ParserError.EmptyInput, parser);
    }

    {
        const parser = Parser.init(testing.allocator, "  ");
        try testing.expectError(ParserError.EmptyInput, parser);
    }
}
