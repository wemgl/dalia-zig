const std = @import("std");
const config = @import("config");
const SemanticVersion = std.SemanticVersion;
const mem = std.mem;
const fmt = std.fmt;
const Allocator = mem.Allocator;
const Parser = @import("parser.zig").Parser;
const fs = std.fs;
const fatal = std.zig.fatal;

const dalia_config_env_var: []const u8 = "DALIA_CONFIG_PATH";
const config_file: []const u8 = "config";
const default_dalia_config_path: []const u8 = "~/.dalia";
const version = SemanticVersion.parse(config.version) catch unreachable;

const usage: []const u8 =
    \\Usage: dalia <command> [arguments]
    \\
    \\Commands:
    \\aliases: Generates all shell aliases for each configured directory at DALIA_CONFIG_PATH
    \\version: The current build version
    \\help: Prints this usage message
    \\
    \\Examples:
    \\$ dalia aliases
    \\
    \\Environment:
    \\DALIA_CONFIG_PATH
    \\The location where dalia looks for alias configurations. This is set to $HOME/dalia by default.
    \\Put the alias configurations in a file named `config` here.
    \\
    \\Use "dalia help <command>" for more information about that command.
    \\
;

const aliases_usage: []const u8 =
    \\Usage: dalia aliases
    \\
    \\Description:
    \\Aliases generates shell aliases for each directory listed in DALIA_CONFIG_PATH/config.
    \\The aliases are only for changing directories to the specified locations. No other types
    \\of aliases are supported.
    \\
    \\Each alias outputted by this command is of the form `alias path="cd /some/path"`.
    \\
    \\The configuration file uses its own format to generate aliases. The simplest way to generate
    \\an alias to a directory is to provide its absolute path on disk. The generated alias will use
    \\the lowercase name of directory at the end of the absolute path as the name of the alias. The
    \\alias name can be customized as well, by prepending the absolute path with a custom name surrounded
    \\by square brackets (i.e. `[` and `]`). The casing of the custom name doesn't change, so if it's
    \\provided in titlecase, snakecase, or any other case, the alias will be created with that case in
    \\tact.
    \\
    \\This command also expands a single directory into multiple aliases when the configured line starts with
    \\an asterisk surrounded by square brackets (i.e. `[*]`), which tells the parser to traverse the immediate
    \\children of the given directory and create lowercase named aliases for only the items that are directories.
    \\All children that are files are ignored.
    \\
    \\Examples:
    \\Simple path
    \\/some/path => alias path='cd /some/path'
    \\
    \\Custom name
    \\[my-path]/some/path => alias my-path='cd /some/path'
    \\[MyPath]/some/path => alias MyPath='cd /some/path'
    \\
    \\Directory expansion
    \\[*]/some/path =>
    \\alias one='cd /some/path/one'
    \\alias two='cd /some/path/two'
    \\alias three='cd /some/path/three'
    \\
    \\when /some/path has contents /one, /two, file.txt, and /three. Note that no alias is created for file.txt.
    \\
;

const version_usage: []const u8 =
    \\Usage: dalia version
    \\
    \\Description:
    \\Version prints the current semantic version of the dalia executable."
    \\
;

pub const Command = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) !Command {
        return .{ .allocator = allocator };
    }

    pub fn run(self: *Command, args: [][]const u8) !void {
        const subcommands = args[1..];
        var should_print_usage = false;
        if (subcommands.len == 0) {
            should_print_usage = true;
        } else if (subcommands.len > 2) {
            try std.io.getStdErr().writer().writeAll("incorrect number of arguments.\n\n");
            should_print_usage = true;
        } else if (mem.eql(u8, "help", subcommands[0])) {
            var subcommand: ?[]const u8 = null;
            if (subcommands.len == 2) {
                subcommand = subcommands[1];
            }
            if (subcommand) |subcmd| {
                if (mem.eql(u8, "aliases", subcmd)) {
                    self.print_aliases_usage() catch fatal("dalia: help aliases failed to run.", .{});
                } else if (mem.eql(u8, "version", subcmd)) {
                    self.print_version_usage() catch fatal("dalia: help version failed to run.", .{});
                } else {
                    const msg = try fmt.allocPrint(
                        self.allocator,
                        "'{s}' is not a dalia command.\n\n",
                        .{subcmd},
                    );
                    try std.io.getStdErr().writer().writeAll(msg);
                    should_print_usage = true;
                }
            } else {
                should_print_usage = true;
            }
        } else if (mem.eql(u8, "version", subcommands[0])) {
            self.print_version() catch fatal("dalia: version command failed to run.", .{});
        } else if (mem.eql(u8, "aliases", subcommands[0])) {
            self.generate_aliases() catch fatal("dalia: aliases command failed to run.", .{});
        } else {
            should_print_usage = true;
        }

        if (should_print_usage) {
            self.print_usage() catch fatal("dalia: help command failed to run.", .{});
        }
    }

    fn generate_aliases(self: *Command) !void {
        _ = self;
        // const p = Parser.init(self.allocator, s) catch {
        //     return error.CommandParserInitFailed;
        // };
        // defer p.deinit();
        // p.processInput() catch return error.CommandParseProcessInputFailed;
    }

    fn print_version(self: *Command) !void {
        const output = try fmt.allocPrint(
            self.allocator,
            "dalia version {d}.{d}.{d}\n",
            .{ version.major, version.minor, version.patch },
        );
        const stdout = std.io.getStdOut();
        try stdout.writer().writeAll(output);
    }

    fn print_aliases_usage(_: *Command) !void {
        try std.io.getStdOut().writer().writeAll(aliases_usage);
    }

    fn print_version_usage(_: *Command) !void {
        try std.io.getStdOut().writer().writeAll(version_usage);
    }

    fn print_usage(_: *Command) !void {
        try std.io.getStdOut().writer().writeAll(usage);
    }
};
