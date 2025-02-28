const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const Allocator = mem.Allocator;

/// Token identifies a text and the kind of token it represents.
pub const Token = struct {
    allocator: Allocator,

    /// The specific atom this token represents.
    kind: TokenKind,

    /// The particular text associated with this token when it was parsed.
    text: []const u8,

    pub fn init(allocator: Allocator, kind: TokenKind, text: []const u8) Token {
        return .{ .allocator = allocator, .kind = kind, .text = text };
    }

    /// Formats this Token for display.
    pub fn print(self: Token) ![]const u8 {
        const idx = @intFromEnum(self.kind);
        return fmt.allocPrint(self.allocator, "<'{s}', {s}>", .{
            self.text,
            token_names[idx],
        });
    }

    pub fn deinit(self: Token) void {
        if (mem.eql(u8, "[", self.text) or
            mem.eql(u8, "]", self.text) or
            mem.eql(u8, "<EOF>", self.text))
            return;
        self.allocator.free(self.text);
    }
};

pub const token_names = [_][]const u8{
    "n/a",
    "<EOF>",
    "LBRACK",
    "RBRACK",
    "ALIAS",
    "PATH",
    "GLOB",
};

pub const TokenKind = enum(u8) {
    eof = 1,
    lbrack,
    rbrack,
    alias,
    path,
    glob,
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
        const t = Token.init(testing.allocator, tc.args.kind, tc.args.text);
        const actual = try t.print();
        defer testing.allocator.free(actual);
        try testing.expectEqualStrings(tc.expected, actual);
    }
}
