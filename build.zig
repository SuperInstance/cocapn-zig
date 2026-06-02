const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Static library
    const lib = b.addStaticLibrary(.{
        .name = "cocapn",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Test configuration
    const test_exe = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run all CoCapn tests");
    test_step.dependOn(&run_test.step);

    // Documentation step
    const docs_step = b.step("docs", "Build documentation");
    const docs_install = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .{ .custom = "docs" },
        .install_subdir = ".",
    });
    docs_step.dependOn(&docs_install.step);
}
