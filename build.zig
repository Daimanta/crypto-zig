const std = @import("std");
const Builder = std.Build;
const version = @import("version.zig");
const builtin = std.builtin;

pub fn build(b: *Builder) void {
    const current_zig_version = @import("builtin").zig_version;
    if (current_zig_version.major != 0 or current_zig_version.minor < 13) {
        std.debug.print("This project does not compile with a Zig version <0.13.x. Exiting.", .{});
        std.os.exit(1);
    }

    const lib = b.addStaticLibrary(.{
        .name = "hashes",
        .root_source_file = b.path("src/std.zig"),
        .optimize = .ReleaseSafe,
        .version = .{.major = version.major, .minor = version.minor, .patch = version.patch},
        .target = b.host
        });
        b.installArtifact(lib);


    var main_tests = b.addTest(.{ .root_source_file = b.path("src/gost.zig")});
    _ = b.addTest(.{ .root_source_file = b.path("src/has160.zig")});
    _ = b.addTest(.{ .root_source_file = b.path("src/md4.zig")});

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
