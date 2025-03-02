const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Allocator = mem.Allocator;
const ascii = std.ascii;
const ArrayList = std.ArrayList;
const StringArrayHashMap = std.StringArrayHashMap;
const fs = std.fs;
const cursor = @import("cursor.zig");
const token = @import("token.zig");
const lexer = @import("lexer.zig");

pub const path_max = 1024;

const ParseError = error{
    EmptyInput,
    LexerInitFailed,
    LexerNextTokenFailed,
    ConsumeTokenFailed,
    UnexpectedTokenMatched,
    GlobExpansionFailed,
    AddIntRepItemFailed,
    ProcessingFileFailed,
    Unexpected,
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

        var input = lexer.Lexer.init(allocator, trimmed_s, 0, s[0]) catch {
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
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.int_rep.deinit();
        self.input.deinit();
        self.lookahead.deinit();
    }

    /// Returns a copy of the aliases parsed from the input file.
    ///
    /// Callers must free the memory referenced by the returned hashmap
    /// to avoid memory leaks.
    fn aliases(self: Parser) !StringArrayHashMap([]const u8) {
        return try self.int_rep.clone();
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
        while (true) {
            try self.line();
            if (self.lookahead.kind == .eof) {
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
        try self.path();

        if (is_glob) {
            try self.expandGlobPaths(path_value);
        } else {
            try self.addPathAlias(alias_name, path_value);
        }
    }

    fn expandGlobPaths(self: *Parser, path_value: []const u8) ParseError!void {
        if (path_value.len == 0) return;

        var dir = fs.openDirAbsolute(path_value, .{ .iterate = true }) catch {
            return ParseError.GlobExpansionFailed;
        };
        defer dir.close();

        var iterator = dir.walk(self.allocator) catch return ParseError.Unexpected;
        while (iterator.next() catch return ParseError.GlobExpansionFailed) |entry| {
            if (entry.kind == .file) continue;
            const full_path = fs.path.join(self.allocator, &[_][]const u8{ path_value, entry.path }) catch return ParseError.Unexpected;
            defer self.allocator.free(full_path);

            try self.insertAliasFromPath(full_path);
        }
    }

    fn addPathAlias(self: *Parser, alias_name: ?[]const u8, path_value: []const u8) ParseError!void {
        if (path_value.len == 0) return;
        if (alias_name) |an| {
            self.int_rep.put(an, path_value) catch return ParseError.AddIntRepItemFailed;
        } else {
            try self.insertAliasFromPath(path_value);
        }
    }

    fn insertAliasFromPath(self: *Parser, path_value: []const u8) ParseError!void {
        if (path_value.len == 0) return;
        const alias_name = fs.path.stem(path_value);
        const new_alias_name = self.allocator.dupe(u8, alias_name) catch return ParseError.Unexpected;
        self.int_rep.put(new_alias_name, path_value) catch return ParseError.AddIntRepItemFailed;
    }
};

// test "expect Parser is created successfully" {
//     const testing = std.testing;
//
//     var parser = try Parser.init(testing.allocator, "test");
//     defer parser.deinit();
//
//     try testing.expectEqual(0, parser.int_rep.count());
//     try testing.expectEqualStrings("test", parser.input.cursor.input);
//     try testing.expectEqual(4, parser.input.cursor.pointer);
//     try testing.expectEqual(cursor.eof, parser.input.cursor.current_char);
//     try testing.expectEqualDeep(.alias, parser.lookahead.kind);
//     try testing.expectEqualDeep("test", parser.lookahead.text);
// }
//
// test "expect Parser initialization fails when input is the empty string or blank" {
//     const testing = std.testing;
//
//     {
//         const parser = Parser.init(testing.allocator, "");
//         try testing.expectError(ParseError.EmptyInput, parser);
//     }
//
//     {
//         const parser = Parser.init(testing.allocator, "  ");
//         try testing.expectError(ParseError.EmptyInput, parser);
//     }
// }
//
// test "expect Parser returns intermediate representation" {
//     const testing = std.testing;
//     var parser = try Parser.init(testing.allocator, "test");
//     defer parser.deinit();
//
//     var aliases = try parser.aliases();
//     defer aliases.deinit();
//
//     try testing.expect(aliases.count() == 0);
// }
//
// test "expect Parser consumes" {
//     const testing = std.testing;
//
//     var parser = try Parser.init(testing.allocator, "[test]/some/test/path");
//     defer parser.deinit();
//
//     try parser.consume();
//
//     try testing.expectEqualDeep(.alias, parser.lookahead.kind);
//     try testing.expectEqualDeep("test", parser.lookahead.text);
// }
//
// test "expect Parser matches token kinds" {
//     const testing = std.testing;
//
//     var parser = try Parser.init(testing.allocator, "[test]/some/test/path");
//     defer parser.deinit();
//
//     {
//         try parser.matches(.lbrack);
//         try testing.expectEqualDeep(.alias, parser.lookahead.kind);
//         try testing.expectEqualDeep("test", parser.lookahead.text);
//     }
//
//     {
//         const actual = parser.matches(.rbrack);
//         try testing.expectError(ParseError.UnexpectedTokenMatched, actual);
//     }
// }
//
// test "expect Parser to process input of only aliases in single line file" {
//     const testing = std.testing;
//
//     const test_cases = [_]struct {
//         arg: []const u8,
//         expected_alias: []const u8,
//         expected_path: []const u8,
//     }{
//         .{
//             .arg = "/some/test/path",
//             .expected_alias = "path",
//             .expected_path = "/some/test/path",
//         },
//         .{
//             .arg = "[alias]/some/test/path",
//             .expected_alias = "alias",
//             .expected_path = "/some/test/path",
//         },
//         .{
//             .arg = "~/some/test/path2",
//             .expected_alias = "path2",
//             .expected_path = "~/some/test/path2",
//         },
//     };
//
//     for (test_cases) |tc| {
//         var parser = try Parser.init(testing.allocator, tc.arg);
//         defer parser.deinit();
//
//         try parser.file();
//
//         var actual = try parser.aliases();
//         defer actual.deinit();
//
//         try testing.expectEqualStrings(tc.expected_path, actual.get(tc.expected_alias) orelse "");
//     }
// }
//
// test "expect Parser to process input of only aliases in multiline file" {
//     const testing = std.testing;
//     const input =
//         \\/some/test/path
//         \\[alias]/some/test/path
//         \\~/some/test/path2
//     ;
//
//     var parser = try Parser.init(testing.allocator, input);
//     defer parser.deinit();
//
//     try parser.file();
//
//     var actual = try parser.aliases();
//     defer actual.deinit();
//
//     try testing.expectEqualStrings("/some/test/path", actual.get("path") orelse "");
//     try testing.expectEqualStrings("/some/test/path", actual.get("alias") orelse "");
//     try testing.expectEqualStrings("~/some/test/path2", actual.get("path2") orelse "");
// }

test "expect Parser to process glob aliases" {
    const testing = std.testing;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("child");

    const realpath = try tmp.parent_dir.realpathAlloc(testing.allocator, &tmp.sub_path);
    defer testing.allocator.free(realpath);

    const file = try fmt.allocPrint(testing.allocator, "[*]{s}", .{realpath});
    defer testing.allocator.free(file);

    var parser = try Parser.init(testing.allocator, file);
    defer parser.deinit();

    // try parser.file();
    //
    // var actual = try parser.aliases();
    // defer actual.deinit();
    //
    // const childpath = try fmt.allocPrint(testing.allocator, "{s}/{s}", .{ realpath, "child" });
    // defer testing.allocator.free(childpath);

    // try testing.expectEqualStrings(childpath, actual.get("child") orelse "");
}
