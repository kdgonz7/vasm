const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const vasm_unit_tests = builder.addTest(.{
        .root_source_file = builder.path("src/vasm.zig"),
        .optimize = .Debug,
    });

    const frontend_exe = builder.addExecutable(.{
        .root_source_file = builder.path("src/frontend.zig"),
        .name = "vasm",
        .target = target,
        .optimize = optimize,
    });

    const build_step = builder.step("tests", "Runs and builds the test executable. --summary all gives a summary of completed and failed tests.");

    // builder => build_step => depends on running lexer unit tests
    //                                => and error unit tests
    //                                => and stylist unit tests
    // ...

    build_step.dependOn(&builder.addRunArtifact(vasm_unit_tests).step);
    builder.installArtifact(frontend_exe);
}
