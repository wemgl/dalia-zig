const std = @import("std");

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .aarch64, .os_tag = .windows },
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const version = b.option(
        []const u8,
        "version",
        "The semantic version of this CLI",
    ) orelse "2.0.0";
    const run_step = b.step("run", "Run dalia");

    for (targets) |target| {
        const exe = b.addExecutable(.{
            .name = "dalia",
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(target),
            .optimize = optimize,
            .single_threaded = true,
            .strip = true,
        });

        const options = b.addOptions();
        options.addOption([]const u8, "version", version);
        exe.root_module.addOptions("config", options);

        if (target.os_tag == .macos) {
            const run_exe = b.addRunArtifact(exe);
            run_exe.step.dependOn(b.getInstallStep());
            if (b.args) |args| run_exe.addArgs(args);
            run_step.dependOn(&run_exe.step);
        }

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try target.zigTriple(b.allocator),
                },
            },
        });

        b.getInstallStep().dependOn(&target_output.step);
    }
}
