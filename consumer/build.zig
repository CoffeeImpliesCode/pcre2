// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.

const std = @import("std");

/// PCRE2 code-unit width forwarded to the dependency.
const CodeUnitWidth = enum {
    @"8",
    @"16",
    @"32",
};

/// Build an external consumer using only the published `pcre2` module.
/// Runtime-loaded runs require an explicit provider request.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Which kind of PCRE2 artifact the dependency delivers. Forwarded to " ++
            "the library's own -Dlinkage option; omitting it leaves the " ++
            "library's default in place, which is dynamic on a GNU libc target " ++
            "and static everywhere else.",
    );

    const runtime = b.option(
        bool,
        "runtime",
        "Build the dependency with its runtime-loading dispatch, so the facade " ++
            "reaches the native entry points through an explicit load(source) " ++
            "instead of a link line. Forwarded to the library's own -Druntime " ++
            "option; omitting it leaves the library's default, which is the " ++
            "linked dispatch. Either way the native artifact is still compiled " ++
            "and installed by the dependency.",
    );

    const width = b.option(
        CodeUnitWidth,
        "code-unit-width",
        "Which code-unit width the dependency names its primary artifact, " ++
            "installed name, soname, pkg-config file and generic aliases for. " ++
            "Forwarded to the library's own -Dcode-unit-width option; omitting it " ++
            "leaves the library's default in place. The artifact carries all " ++
            "three widths' entry points either way; this names the primary one.",
    );

    const sanitize_c = b.option(
        std.zig.SanitizeC,
        "sanitize_c",
        "Undefined behaviour sanitizer for the dependency's C sources. " ++
            "Forwarded to the library's own -Dsanitize_c option; omitting it " ++
            "leaves the library's default in place.",
    );

    const dep = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
        .@"code-unit-width" = width,
        .sanitize_c = sanitize_c,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // The C core allocates through libc; runtime mode also needs libc.
        // Expose that requirement on the consumer module.
        .link_libc = true,
    });
    exe_mod.addImport("pcre2", dep.module("pcre2"));

    const exe = b.addExecutable(.{
        .name = "pcre2-consumer",
        .root_module = exe_mod,
    });
    // The default build compiles only; `run` executes with the build-cache library rpath.
    b.getInstallStep().dependOn(&exe.step);

    const run_exe = b.addRunArtifact(exe);
    // Forward caller arguments for explicit runtime provider selection.
    run_exe.addPassthruArgs();
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
