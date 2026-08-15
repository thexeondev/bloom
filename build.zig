const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{ .default_target = .{
        .os_tag = .windows,
        .cpu_arch = .x86_64,
    } });

    const launcher = b.addExecutable(.{
        .name = "red_rose",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/launcher.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(launcher);

    const dynlib = b.addLibrary(.{
        .name = "bloom",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bloom.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });
    dynlib.root_module.addAnonymousImport(
        "offsets",
        .{ .root_source_file = b.path("config/offsets.zon") },
    );
    dynlib.root_module.addAnonymousImport(
        "overrides",
        .{ .root_source_file = b.path("config/overrides.zon") },
    );
    b.installArtifact(dynlib);
}
