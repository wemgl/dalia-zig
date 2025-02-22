const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const test_allocator = std.testing.allocator;

pub fn main() void {
    std.debug.print("Hello, dalia!", .{});
}

const Token = struct {
    kind: TokenType,
    text: []const u8,

    pub fn init(kind: TokenType, text: []const u8) Token {
        return .{
            .kind = kind,
            .text = text,
        };
    }

    pub fn fmt(self: Token, allocator: mem.Allocator) ![]const u8 {
        const idx = @intFromEnum(self.kind);
        return std.fmt.allocPrint(allocator, "<'{s}', {s}>", .{
            self.text,
            TokenNames[idx],
        });
    }
};

const TokenNames = [_][]const u8{
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
    const token = Token{ .kind = .eof, .text = "<EOF>" };
    const actual = try token.fmt(test_allocator);
    defer test_allocator.free(actual);
    try testing.expectEqualStrings("<'<EOF>', <EOF>>", actual);
}
