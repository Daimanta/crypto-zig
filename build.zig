const std = @import("std");
const version = @import("version.zig");
const builtin = std.builtin;

const Step = std.Build.Step;
const Builder = std.Build;

pub fn build(b: *Builder) void {
    const current_zig_version = @import("builtin").zig_version;
    if (current_zig_version.major != 0 or current_zig_version.minor < 15) {
        std.debug.print("This project does not compile with a Zig version <0.15.x. Exiting.", .{});
        std.os.exit(1);
    }

    const target = b.standardTargetOptions(.{});
    const module = b.createModule(.{
        .root_source_file = b.path("src/std.zig"),
        .optimize = .ReleaseSafe,
        .target = target
    });


    const lib = b.addLibrary(.{
        .name = "crypto",
        .root_module = module,
        .version = .{.major = version.major, .minor = version.minor, .patch = version.patch}
    });
    b.installArtifact(lib);

    const main_tests = addTests(b, &.{
        .{.root_module = b.createModule(.{.root_source_file = b.path("src/has160.zig"), .optimize = .ReleaseSafe, .target = target})},
        .{.root_module = b.createModule(.{.root_source_file = b.path("src/md4.zig"), .optimize = .ReleaseSafe, .target = target})},
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

}

fn addTests(b: *Builder, tests: []const std.Build.TestOptions) *Step.Compile {
    var result: *Step.Compile = undefined;
    for (tests) |testElem| {
        result = b.addTest(testElem);
    }
    return result;
}
