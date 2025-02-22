const std = @import("std");
const mem = std.mem;

pub fn main() void {
    std.debug.print("Hello, dalia!", .{});
}

/// Token identifies a text and the kind of token it represents.
const Token = struct {
    /// The specific atom this token represents.
    kind: TokenType,

    /// The particular text associated with this token when it was parsed.
    text: []const u8,

    pub fn init(kind: TokenType, text: []const u8) Token {
        return .{ .kind = kind, .text = text };
    }

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

test "token display" {
    const testing = std.testing;
    const test_allocator = std.testing.allocator;

    const test_cases = [_]struct {
        args: struct { kind: TokenType, text: []const u8 },
        actual: []const u8,
    }{
        .{
            .args = .{ .kind = .eof, .text = "<EOF>" },
            .actual = "<'<EOF>', <EOF>>",
        },
        .{
            .args = .{ .kind = .lbrack, .text = "LBRACK" },
            .actual = "<'LBRACK', LBRACK>",
        },
        .{
            .args = .{ .kind = .rbrack, .text = "RBRACK" },
            .actual = "<'RBRACK', RBRACK>",
        },
        .{
            .args = .{ .kind = .alias, .text = "ALIAS" },
            .actual = "<'ALIAS', ALIAS>",
        },
        .{
            .args = .{ .kind = .path, .text = "PATH" },
            .actual = "<'PATH', PATH>",
        },
        .{
            .args = .{ .kind = .glob, .text = "GLOB" },
            .actual = "<'GLOB', GLOB>",
        },
    };

    for (test_cases) |tc| {
        const token = Token.init(tc.args.kind, tc.args.text);
        const actual = try token.fmt(test_allocator);
        defer test_allocator.free(actual);
        try testing.expectEqualStrings(tc.actual, actual);
    }
}
