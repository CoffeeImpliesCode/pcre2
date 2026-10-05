// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.

const std = @import("std");

/// The library's `-Dcode-unit-width`, in the three spellings its own enum uses.
///
/// Declared here rather than imported because a dependent may not read the
/// dependency's `build.zig`: the only supported route in is `b.dependency`. The
/// tags are the library's own and are forwarded verbatim, so the value this
/// package accepts and the value the library parses are one spelling.
const CodeUnitWidth = enum {
    @"8",
    @"16",
    @"32",
};

/// A package that consumes `pcre2` from outside.
///
/// This exists to prove one thing: that a dependent needs nothing but
/// `dep.module("pcre2")` and gets a working, correctly linked PCRE2 at the
/// width, linkage and dispatch the dependency was asked for.
/// If the published module stopped carrying the compiled C core, or the
/// translated `pcre2.h` stopped matching the C the module was built from,
/// this would stop building or stop producing the right byte offsets, and
/// nothing inside the library would notice.
///
/// It also proves the two delivery variants, the two dispatch routes and all
/// three code-unit widths a dependent can be handed. The library's own default
/// linkage is dynamic on a GNU libc target and static everywhere else, so a
/// plain `zig build run` here exercises whichever that is; `-Dlinkage=static` and
/// `-Dlinkage=dynamic` name the other one explicitly. `-Druntime=true` selects
/// the runtime-loaded dispatch instead of the linked one.
/// `-Dcode-unit-width=16|32` asks the dependency for the artifact, the installed
/// name, the soname and the generic aliases of that width, and `src/main.zig`
/// works in whatever code unit compiled, so the same hand-worked offsets are the
/// answer at every width. All four options are forwarded rather than
/// reinterpreted: each is the library's own option, read here and passed on, so
/// there is one definition of what each value means.
///
/// **No default is supplied here for any of them.** An option this package does
/// not name is not forwarded at all, so the dependency resolves its own, and a
/// plain `zig build run` proves what the library would have built on its own
/// rather than what a second copy of its defaults says.
///
/// The shared route is the one this package exists to check. A static archive
/// is resolved by the linker from the file the build graph names, so it cannot
/// be confused with anything; a shared object is resolved by the platform
/// loader from the **soname** at run time, which is the name the machine may
/// already have installed under `libpcre2-8.so.0`. What makes this a real proof
/// rather than a build that happens to succeed is that `src/main.zig` prints
/// the version string the library reports about itself: a run that resolved
/// some other `libpcre2-8` on the machine would print that library's version
/// and nothing here would object.
///
/// Run it with `zig build run`. Every expected value in `src/main.zig` is worked
/// out by hand, so a mismatch is a real fault and not a restatement of what the
/// library just did. Any mismatch exits non-zero.
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
        // The published module compiles the 8-bit core from this repository's
        // own `src/`, and that core allocates through malloc. Stating libc
        // here keeps the consumer's own requirement visible instead of leaving
        // it implicit in the dependency. Under `-Druntime=true` the module links
        // no native library, so this is then the consumer's own only libc
        // requirement rather than an inherited one.
        .link_libc = true,
    });
    exe_mod.addImport("pcre2", dep.module("pcre2"));

    const exe = b.addExecutable(.{
        .name = "pcre2-consumer",
        .root_module = exe_mod,
    });
    // `zig build` compiles the program and installs nothing; `zig build run`
    // executes it. That is this package's own rule for a proof, and it is the
    // same arrangement the library uses for its smoke example: a proof is not a
    // deliverable.
    //
    // The reason is the loader entry this program would carry. The published
    // module is the build-cache flavour, so the ordinary `linkLibrary` inside
    // the dependency records the directory `libpcre2-8.so.0.16.1` was emitted
    // into and this compilation gets an `-rpath` for it. That is the only entry
    // that can resolve the library here: this program runs out of *this*
    // package's build cache, where no `lib/` sits beside it, so a program
    // carrying the install tree's `$ORIGIN/../lib` instead resolves nothing of
    // its own and the loader falls through to `/lib64` and whatever
    // `libpcre2-8.so.0` the host installed -- a *different* PCRE2, reached
    // through the same soname, with none of this package's bytes in it.
    //
    // `installArtifact` would copy that cache directory into an installed
    // file's `DT_RUNPATH`: a path that is gone once the cache is, and one Nix
    // refuses to package. So the install step hangs on this **Compile** step
    // rather than on the `Run` step `run` gets, and the default build compiles
    // the program without running it or writing it anywhere.
    b.getInstallStep().dependOn(&exe.step);

    const run_exe = b.addRunArtifact(exe);
    // Forwarded so `zig build run -Druntime=true -- --provider <path>` reaches
    // `src/main.zig`, which reads exactly that and otherwise falls through to
    // `PCRE2_TEST_PROVIDER`. With no arguments this is inert, so a linked run
    // is unchanged.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
