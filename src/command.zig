const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;
const process = std.process;
const Allocator = mem.Allocator;
const Parser = @import("parser.zig").Parser;
const fs = std.fs;
const fatal = @import("output.zig").fatal;
const ascii = std.ascii;
const io = std.io;
const SemanticVersion = std.SemanticVersion;

const dalia_config_env_var: []const u8 = "DALIA_CONFIG_PATH";
const config_filename: []const u8 = "config";
const default_dalia_config_dir: []const u8 = ".dalia";

/// The maximum config file size of 1MiB
const max_file_size_bytes = 1 << 20;

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
    \\by square brackets (i.e. `[` and `]`). Custom aliases are all converted to lowercase with spaces replaced
    \\with hyphens (i.e. `-`).
    \\
    \\This command also expands a single directory into multiple aliases when the configured line starts with
    \\an asterisk surrounded by square brackets (i.e. `[*]`), which tells the parser to traverse the immediate
    \\children of the given directory and create lowercase named aliases for only the items that are directories.
    \\All children that are files are ignored.
    \\
    \\Examples:
    \\Simple path
    \\/some/path => alias path="cd /some/path"
    \\
    \\Custom name
    \\[my-path]/some/path => alias my-path="cd /some/path"
    \\[MyPath]/some/path => alias mypath="cd /some/path"
    \\
    \\Directory expansion
    \\[*]/some/path =>
    \\alias one="cd /some/path/one"
    \\alias two="cd /some/path/two"
    \\alias three="cd /some/path/three"
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
    version: SemanticVersion,

    pub fn init(allocator: Allocator, version: SemanticVersion) !Command {
        return .{ .allocator = allocator, .version = version };
    }

    pub fn run(self: *Command, args: []const []const u8, writer: fs.File) !void {
        const subcommands = args[1..];
        var should_print_usage = false;
        if (subcommands.len == 0) {
            should_print_usage = true;
        } else if (subcommands.len > 2) {
            fatal("dalia: incorrect number of arguments.\n");
        } else if (mem.eql(u8, "help", subcommands[0])) {
            var subcommand: ?[]const u8 = null;
            if (subcommands.len == 2) {
                subcommand = subcommands[1];
            }

            if (subcommand) |subcmd| {
                if (mem.eql(u8, "aliases", subcmd)) {
                    self.print_aliases_usage(writer) catch fatal("dalia: help aliases failed to run.\n");
                } else if (mem.eql(u8, "version", subcmd)) {
                    self.print_version_usage(writer) catch fatal("dalia: help version failed to run.\n");
                } else {
                    const msg = try fmt.allocPrint(
                        self.allocator,
                        "'{s}' is not a dalia command.\n",
                        .{subcmd},
                    );
                    fatal(msg);
                    should_print_usage = true;
                }
            } else {
                should_print_usage = true;
            }
        }

        if (mem.eql(u8, "version", subcommands[0])) {
            if (subcommands.len == 2) {
                fatal("dalia: version doesn't take any arguments.\n");
            }
            self.print_version(writer) catch fatal("dalia: version command failed to run.\n");
        } else if (mem.eql(u8, "aliases", subcommands[0])) {
            if (subcommands.len == 2) {
                fatal("dalia: aliases doesn't take any arguments.\n");
            }
            self.generate_aliases(writer) catch fatal("dalia: aliases command failed to run.\n");
        } else {
            should_print_usage = true;
        }

        if (should_print_usage) {
            self.print_usage(writer) catch fatal("dalia: help command failed to run.\n");
        }
    }

    fn generate_aliases(self: *Command, writer: fs.File) !void {
        const dalia_config_path = process.getEnvVarOwned(
            self.allocator,
            dalia_config_env_var,
        ) catch blk: {
            const home_path = try process.getEnvVarOwned(self.allocator, "HOME");
            const default_dalia_config_path = try fs.path.join(self.allocator, &[_][]const u8{
                home_path,
                default_dalia_config_dir,
            });
            break :blk default_dalia_config_path;
        };

        var config_dir = try fs.openDirAbsolute(dalia_config_path, .{});
        defer config_dir.close();

        const file = try config_dir.openFile(config_filename, .{});
        defer file.close();

        const contents = try file.readToEndAlloc(self.allocator, max_file_size_bytes);
        if (contents.len == 0) return error.EmptyConfigFileContents;

        var p = try Parser.init(self.allocator, contents);
        defer p.deinit();

        try p.processInput();

        var aliases = try p.aliases();
        defer {
            var iterator = aliases.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.value_ptr.*);
                self.allocator.free(entry.key_ptr.*);
            }
            aliases.deinit();
        }

        var iterator = aliases.iterator();
        while (iterator.next()) |entry| {
            const key = try ascii.allocLowerString(self.allocator, entry.key_ptr.*);
            const output = try fmt.allocPrint(
                self.allocator,
                "alias {s}=\"cd {s}\"\n",
                .{ key, entry.value_ptr.* },
            );
            try writer.writeAll(output);
        }
    }

    fn print_version(self: *Command, writer: fs.File) !void {
        const output = try fmt.allocPrint(
            self.allocator,
            "dalia version {d}.{d}.{d}\n",
            .{ self.version.major, self.version.minor, self.version.patch },
        );
        defer self.allocator.free(output);

        try writer.writeAll(output);
    }

    fn print_aliases_usage(_: *Command, writer: fs.File) !void {
        try writer.writeAll(aliases_usage);
    }

    fn print_version_usage(_: *Command, writer: fs.File) !void {
        try writer.writeAll(version_usage);
    }

    fn print_usage(_: *Command, writer: fs.File) !void {
        try writer.writeAll(usage);
    }
};

test "expect Command to print the version" {
    const testing = std.testing;

    const test_cases = [_]struct {
        args: []const []const u8,
        expected: []const u8,
    }{
        .{ .args = &.{ "dalia", "version" }, .expected = "dalia version 0.1.0" },
        .{ .args = &.{ "dalia", "help" }, .expected = "Usage: dalia <command> [arguments]" },
        .{ .args = &.{ "dalia", "help", "aliases" }, .expected = "Usage: dalia aliases" },
        .{ .args = &.{ "dalia", "help", "version" }, .expected = "Usage: dalia version" },
    };

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const version = try SemanticVersion.parse("0.1.0");
    var cmd = try Command.init(testing.allocator, version);

    const out = try tmp.dir.createFile("out", .{ .read = true, .mode = 0o777 });
    defer out.close();

    for (test_cases) |tc| {
        try cmd.run(tc.args, out);
        try out.seekTo(0);

        const actual = try out.readToEndAlloc(testing.allocator, max_file_size_bytes);
        defer testing.allocator.free(actual);

        try testing.expect(mem.containsAtLeast(u8, actual, 1, tc.expected));
    }
}
