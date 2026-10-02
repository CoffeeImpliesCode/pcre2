const std = @import("std");

/// A package that consumes `pcre2` from outside.
///
/// This exists to prove one thing: that a dependent needs nothing but
/// `dep.module("pcre2")` and gets a working, correctly linked 8-bit PCRE2.
/// If the published module stopped carrying the compiled C core, or the
/// translated `pcre2.h` stopped matching the C the module was built from,
/// this would stop building or stop producing the right byte offsets, and
/// nothing inside the library would notice.
///
/// Run it with `zig build run`. Every expected value is worked out by hand
/// below, so a mismatch is a real fault and not a restatement of what the
/// library just did. Any mismatch exits non-zero.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // The published module compiles the 8-bit core from this repository's
        // own `src/`, and that core allocates through malloc. Stating libc
        // here keeps the consumer's own requirement visible instead of leaving
        // it implicit in the dependency.
        .link_libc = true,
    });
    exe_mod.addImport("pcre2", dep.module("pcre2"));

    const exe = b.addExecutable(.{
        .name = "pcre2-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
