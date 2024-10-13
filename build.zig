const std = @import("std");

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});
    const parser_unit_tests = builder.addTest(.{
        .root_source_file = builder.path("src/parser.zig"),
    });

    const errors_unit_tests = builder.addTest(.{
        .root_source_file = builder.path("src/errors.zig"),
    });

    const stylist_unit_tests = builder.addTest(.{
        .root_source_file = builder.path("src/stylist.zig"),
    });

    const codegen_unit_tests = builder.addTest(.{
        .root_source_file = builder.path("src/codegen.zig"),
    });

    const template_unit_tests = builder.addTest(.{
        .root_source_file = builder.path("src/linker.zig"),
    });

    const frontend_unit_tests = builder.addTest(.{
        .root_source_file = builder.path("src/frontend.zig"),
    });

    const drivers_unit_tests = builder.addTest(.{
        .root_source_file = builder.path("src/drivers.zig"),
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

    build_step.dependOn(&builder.addRunArtifact(parser_unit_tests).step);
    build_step.dependOn(&builder.addRunArtifact(errors_unit_tests).step);
    build_step.dependOn(&builder.addRunArtifact(stylist_unit_tests).step);
    build_step.dependOn(&builder.addRunArtifact(codegen_unit_tests).step);
    build_step.dependOn(&builder.addRunArtifact(template_unit_tests).step);
    build_step.dependOn(&builder.addRunArtifact(frontend_unit_tests).step);
    build_step.dependOn(&builder.addRunArtifact(drivers_unit_tests).step);
    builder.installArtifact(frontend_exe);
}
