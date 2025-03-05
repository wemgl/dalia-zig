const std = @import("std");
const fmt = std.fmt;
const parser = @import("parser.zig");

pub fn println(comptime format: []const u8, args: anytype) !void {
    var buf: [parser.path_max]u8 = undefined;
    const slice = try fmt.bufPrint(&buf, format, args);
    std.debug.print("\r{s}\n", .{slice});
}

pub fn fatal(msg: []const u8) noreturn {
    std.io.getStdErr().writeAll(msg) catch unreachable;
    std.process.exit(1);
}
