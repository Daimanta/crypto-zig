const std = @import("std");
const version = @import("version.zig");
const builtin = std.builtin;

const Step = std.Build.Step;
const Builder = std.Build;

pub fn build(b: *Builder) void {
    const current_zig_version = @import("builtin").zig_version;
    if (current_zig_version.major != 0 or current_zig_version.minor < 14) {
        std.debug.print("This project does not compile with a Zig version <0.14.x. Exiting.", .{});
        std.os.exit(1);
    }

    const target = b.standardTargetOptions(.{});

    const lib = b.addStaticLibrary(.{
        .name = "crypto",
        .root_source_file = b.path("src/std.zig"),
        .optimize = .ReleaseSafe,
        .version = .{.major = version.major, .minor = version.minor, .patch = version.patch},
        .target = target
    });
    b.installArtifact(lib);

    const main_tests = addTests(b, &.{
        .{.root_source_file = b.path("src/has160.zig")},
        .{.root_source_file = b.path("src/md4.zig")},
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
