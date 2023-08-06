const std = @import("std");
const version = @import("version.zig");
const builtin = std.builtin;

pub fn build(b: *std.build.Builder) void {

    const lib = b.addStaticLibrary(.{
        .name = "hashes",
        .root_source_file = .{.path = "src/std.zig"},
        .optimize = .ReleaseSafe,
        .version = .{.major = version.major, .minor = version.minor, .patch = version.patch},
        .target = .{}
        });
        b.installArtifact(lib);


    var main_tests = b.addTest(.{ .root_source_file = .{ .path = "src/gost.zig"}});
    _ = b.addTest(.{ .root_source_file = .{ .path = "src/has160.zig"}});
    _ = b.addTest(.{ .root_source_file = .{ .path = "src/md4.zig"}});

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
