const std = @import("std");

pub const eof: u8 = 0;
pub const underscore = '_';
pub const hyphen = '-';
pub const asterisk = '*';

/// Cursor allows traversing through an input String character by character while lexing.
pub const Cursor = struct {
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
        .{
            .args = .{ .input = "", .pointer = 0, .current_char = '0' },
            .consume_count = 0,
        },
        .{
            .args = .{ .input = "test", .pointer = 0, .current_char = '0' },
            .expected_input = "test",
            .expected_pointer = 2,
            .expected_current_char = 's',
            .consume_count = 2,
        },
        .{
            .args = .{ .input = "test", .pointer = 0, .current_char = '0' },
            .expected_input = "test",
            .expected_pointer = 3,
            .expected_current_char = 't',
            .consume_count = 3,
        },
        .{
            .args = .{ .input = "test", .pointer = 0, .current_char = '0' },
            .expected_input = "test",
            .expected_pointer = 4,
            .expected_current_char = 0,
            .consume_count = 4,
        },
    };

    for (test_cases) |tc| {
        var cur = Cursor.init(tc.args.input, tc.args.pointer, tc.args.current_char);
        var i: u8 = 0;
        while (i < tc.consume_count) : (i += 1) {
            cur.consume();
        }
        try testing.expectEqualStrings(tc.expected_input, cur.input);
        try testing.expectEqual(tc.expected_pointer, cur.pointer);
        try testing.expectEqual(tc.expected_current_char, cur.current_char);
    }
}
