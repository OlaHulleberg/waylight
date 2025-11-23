const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create executable
    const exe = b.addExecutable(.{
        .name = "waylight",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link C libraries
    exe.linkLibC();
    exe.linkSystemLibrary2("gtk4", .{ .use_pkg_config = .force });
    exe.linkSystemLibrary2("gtk4-layer-shell-0", .{ .use_pkg_config = .force });
    exe.linkSystemLibrary2("webkitgtk-6.0", .{ .use_pkg_config = .force });

    // Add build options for conditional asset loading
    const build_options = b.addOptions();
    build_options.addOption(bool, "embed_assets", optimize != .Debug);
    exe.root_module.addImport("build_options", build_options.createModule());

    // Install artifact
    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run waylight");
    run_step.dependOn(&run_cmd.step);
}
