const std = @import("std");
const command = @import("command.zig");
const Command = command.Command;
const config_env_var = command.config_env_var;
const default_config_dir = command.default_config_dir;
const fatal = @import("output.zig").fatal;
const heap = std.heap;
const ArenaAllocator = heap.ArenaAllocator;
const page_allocator = heap.page_allocator;
const process = std.process;
const config = @import("config");
const SemanticVersion = std.SemanticVersion;
const io = std.io;
const fs = std.fs;

pub fn main() !void {
    var arena_allocator = ArenaAllocator.init(page_allocator);
    defer arena_allocator.deinit();

    const arena = arena_allocator.allocator();
    const args = process.argsAlloc(arena) catch fatal("dalia: argument parsing failed.\n");
    defer process.argsFree(arena, args);

    const config_path = process.getEnvVarOwned(arena, config_env_var) catch blk: {
        const home_path = try process.getEnvVarOwned(arena, "HOME");
        const default_config_path = try fs.path.join(arena, &[_][]const u8{
            home_path,
            default_config_dir,
        });
        break :blk default_config_path;
    };

    const version = SemanticVersion.parse(config.version) catch fatal("dalia: version parse failed.\n");
    var cmd = Command.init(
        arena,
        version,
        config_path,
    ) catch fatal("dalia: init failed.\n");

    const stdout = io.getStdOut();
    cmd.run(args, stdout) catch fatal("dalia: unexpected failure running subcommand.\n");
}
