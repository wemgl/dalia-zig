const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const ascii = std.ascii;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;
const fs = std.fs;
const cursor = @import("cursor.zig");
const token = @import("token.zig");
const lexer = @import("lexer.zig");

const ParseError = error{
    EmptyInput,
    LexerInitFailed,
    LexerNextTokenFailed,
    ConsumeTokenFailed,
    UnexpectedTokenMatched,
    GlobExpansionFailed,
    AddIntRepItemFailed,
    ProcessingFileFailed,
};

pub const Parser = struct {
    allocator: Allocator,
    /// The lexer responsible for returning tokenized input.
    input: lexer.Lexer,
    /// The current lookahead token used by this parser.
    lookahead: token.Token,
    /// The internal representation of a parsed configuration file.
    int_rep: StringArrayHashMap([]const u8),

    pub fn init(allocator: Allocator, s: []const u8) ParseError!Parser {
        const trimmed_s = mem.trim(u8, s, " ");
        if (trimmed_s.len == 0) {
            return ParseError.EmptyInput;
        }

        var input = lexer.Lexer.init(allocator, s, 0, s[0]) catch {
            return ParseError.LexerInitFailed;
        };

        const lookahead = input.nextToken() catch {
            return ParseError.LexerNextTokenFailed;
        };

        return .{
            .allocator = allocator,
            .input = input,
            .lookahead = lookahead,
            .int_rep = StringArrayHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        var iterator = self.int_rep.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.int_rep.deinit();
        self.input.deinit();
        self.lookahead.deinit();
    }

    fn aliases(self: Parser) StringArrayHashMap([]const u8) {
        return self.int_rep.clone() catch {
            return StringArrayHashMap([]const u8).init(self.allocator);
        };
    }

    fn consume(self: *Parser) !void {
        self.lookahead = try self.input.nextToken();
    }

    fn alias(self: *Parser) !void {
        try self.matches(.alias);
    }

    fn matches(self: *Parser, kind: token.TokenKind) ParseError!void {
        if (self.lookahead.kind == kind) {
            self.consume() catch return ParseError.ConsumeTokenFailed;
            return;
        }
        return ParseError.UnexpectedTokenMatched;
    }

    fn glob(self: *Parser) !void {
        try self.matches(.glob);
    }

    fn path(self: *Parser) !void {
        try self.matches(.path);
    }

    pub fn processInput(self: *Parser) ParseError!void {
        try self.file();
    }

    fn file(self: *Parser) ParseError!void {
        std.debug.print("\nstart processing file…\n", .{});
        while (true) {
            try self.line();
            if (self.lookahead.kind == .eof) {
                std.debug.print("end processing file…\n", .{});
                try self.matches(.eof);
                break;
            }
        }
    }

    fn line(self: *Parser) ParseError!void {
        var alias_name: ?[]const u8 = null;
        var is_glob = false;

        if (self.lookahead.kind == .lbrack) {
            try self.matches(.lbrack);

            if (self.lookahead.kind == .glob) {
                is_glob = true;
                try self.glob();
            } else if (self.lookahead.kind == .alias) {
                alias_name = self.lookahead.text;
                try self.alias();
            }

            try self.matches(.rbrack);
        }

        const path_value = self.lookahead.text;
        std.debug.print("path_value is {s}\n", .{path_value});
        try self.path();

        if (is_glob) {
            try self.expandGlobPaths(path_value);
        } else {
            try self.addPathAlias(alias_name, path_value);
        }
    }

    fn expandGlobPaths(self: *Parser, path_value: []const u8) ParseError!void {
        var dir = fs.openDirAbsolute(path_value, .{ .iterate = true }) catch {
            return ParseError.GlobExpansionFailed;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (iter.next() catch return ParseError.GlobExpansionFailed) |entry| {
            if (entry.kind == .file) continue;
            try self.insertAliasFromPath(entry.name);
        }
    }

    fn addPathAlias(self: *Parser, alias_name: ?[]const u8, path_value: []const u8) ParseError!void {
        std.debug.print("\nattempt adding path to alias\n", .{});
        if (alias_name) |an| {
            std.debug.print("\nadd path to alias: {s}, path: {s}\n", .{ an, path_value });
            self.int_rep.put(an, path_value) catch return ParseError.AddIntRepItemFailed;
        } else {
            std.debug.print("\nthere was no alias name\n", .{});
            try self.insertAliasFromPath(path_value);
        }
    }

    fn insertAliasFromPath(self: *Parser, path_value: []const u8) ParseError!void {
        std.debug.print("\nget alias name from path stem\n", .{});
        const alias_name = fs.path.stem(path_value);
        std.debug.print("\nalias name is {s}\n", .{alias_name});
        self.int_rep.put(alias_name, path_value) catch return ParseError.AddIntRepItemFailed;
    }
};

test "expect Parser is created successfully" {
    const testing = std.testing;

    var parser = try Parser.init(testing.allocator, "test");
    defer parser.deinit();

    try testing.expectEqual(0, parser.int_rep.values().len);
    try testing.expectEqualStrings("test", parser.input.cursor.input);
    try testing.expectEqual(4, parser.input.cursor.pointer);
    try testing.expectEqual(cursor.eof, parser.input.cursor.current_char);
    try testing.expectEqualDeep(.alias, parser.lookahead.kind);
    try testing.expectEqualDeep("test", parser.lookahead.text);
}

test "expect Parser initialization fails when input is the empty string or blank" {
    const testing = std.testing;

    {
        const parser = Parser.init(testing.allocator, "");
        try testing.expectError(ParseError.EmptyInput, parser);
    }

    {
        const parser = Parser.init(testing.allocator, "  ");
        try testing.expectError(ParseError.EmptyInput, parser);
    }
}

test "expect Parser returns intermediate representation" {
    const testing = std.testing;
    var parser = try Parser.init(testing.allocator, "test");
    defer parser.deinit();

    var aliases = parser.aliases();
    defer aliases.deinit();

    try testing.expect(aliases.count() == 0);
}

test "expect Parser consumes" {
    const testing = std.testing;

    var parser = try Parser.init(testing.allocator, "[test]/some/test/path");
    defer parser.deinit();

    try parser.consume();

    try testing.expectEqualDeep(.alias, parser.lookahead.kind);
    try testing.expectEqualDeep("test", parser.lookahead.text);
}

test "expect Parser matches token kinds" {
    const testing = std.testing;

    var parser = try Parser.init(testing.allocator, "[test]/some/test/path");
    defer parser.deinit();

    {
        try parser.matches(.lbrack);
        try testing.expectEqualDeep(.alias, parser.lookahead.kind);
        try testing.expectEqualDeep("test", parser.lookahead.text);
    }

    {
        const actual = parser.matches(.rbrack);
        try testing.expectError(ParseError.UnexpectedTokenMatched, actual);
    }
}

test "expect Parser to process input" {
    const testing = std.testing;

    const test_cases = [_]struct {
        file_content: []const u8,
    }{
        .{ .file_content = "/some/test/path" },
        // .{ .file_content = "[alias]/some/test/path" },
    };

    for (test_cases) |tc| {
        var parser = try Parser.init(testing.allocator, tc.file_content);
        defer parser.deinit();

        // try parser.file();

        // var actual_aliases = parser.aliases();
        // defer actual_aliases.deinit();

        // if (actual_aliases.get("path")) |actual_alias| {
        //     try testing.expectEqualStrings("/some/test/path", actual_alias);
        // }
    }
}
