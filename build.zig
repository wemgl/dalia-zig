const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "dalia",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = true,
        .strip = true,
    });

    const version = b.option(
        []const u8,
        "version",
        "The semantic version of this CLI",
    ) orelse "2.0.0";
    const options = b.addOptions();
    options.addOption([]const u8, "version", version);
    exe.root_module.addOptions("config", options);
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_exe.addArgs(args);

    const run_step = b.step("run", "Run dalia");
    run_step.dependOn(&run_exe.step);
}
