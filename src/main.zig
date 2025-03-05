const std = @import("std");
const Command = @import("command.zig").Command;
const fatal = @import("output.zig").fatal;
const heap = std.heap;
const ArenaAllocator = heap.ArenaAllocator;
const page_allocator = heap.page_allocator;
const process = std.process;
const config = @import("config");
const SemanticVersion = std.SemanticVersion;

pub fn main() !void {
    var arena_allocator = ArenaAllocator.init(page_allocator);
    defer arena_allocator.deinit();

    const arena = arena_allocator.allocator();
    const args = process.argsAlloc(arena) catch fatal("dalia: argument parsing failed.\n");
    defer process.argsFree(arena, args);

    const version = SemanticVersion.parse(config.version) catch fatal("dalia: failed to parse version.\n");
    var cmd = Command.init(arena, version) catch fatal("dalia: init failed.\n");
    cmd.run(args) catch fatal("dalia: unexpected failure running subcommand.\n");
}
