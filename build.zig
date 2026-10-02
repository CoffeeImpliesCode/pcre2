//! Zig build graph for this PCRE2 fork.
//!
//! This extends the working upstream Zig 0.16 graph that shipped with
//! pcre2-10.49 rather than replacing it. What upstream already did is kept
//! and still does the work: the `src/pcre2.h.generic` -> `pcre2.h` copy through
//! `addWriteFiles`, the `config.h` generation from `src/config-cmake.h.in`
//! through `addConfigHeader`, the explicit translation-unit list, and the
//! `linkage` / `sanitize_c` / `code-unit-width` options.
//!
//! What this fork adds:
//!
//!   * `zig/root.zig` published as the module `pcre2`, with the raw C
//!     reachable as `pcre2.c`. It is registered as a package module so a
//!     dependent needs only `dep.module("pcre2")`.
//!   * `tests.zig`, `smoke.zig` and the `check` step.
//!   * `-fsys=pcre2-8`, a real `b.systemIntegrationOption` that links an
//!     installed libpcre2-8 and translates the *installed* `<pcre2.h>` rather
//!     than this tree's header: in that mode the generated aggregate includes
//!     it by angle brackets, resolves through the target's own system include
//!     search, and no include path of this graph is added, so the declarations
//!     come from the header that was installed rather than from the 10.49 copy
//!     under `src/`. The `PCRE2_STATIC` declaration macro follows the kind of
//!     installed library the linker is asked for, which `-Dlinkage` names in
//!     that mode.
//!   * `translate.h`, the fork-authored aggregate the bundled translation reads,
//!     through the front end the target's C library needs: Aro's own
//!     preprocessor where Aro can read that library, and the target's own
//!     `zig cc -E -dD` in front of it everywhere else. `aggregateRoute` says which.
//!
//! What this fork removes, and why:
//!
//!   * The `sljit` package dependency and the `-Dsupport_jit` option.
//!     `deps/sljit` is a git submodule and is empty in this checkout, so
//!     upstream's option resolves the source either from that submodule or from
//!     `b.lazyDependency("sljit", ...)`, which is a network fetch. Neither is
//!     available to a fork whose contract is that the primary core compiles from
//!     its own tree with no build-time download, so the option would be a knob
//!     that only works with a populated submodule. It is gone rather than left
//!     to fail later. JIT is off, so `SUPPORT_JIT` is 0 in `config.h` and
//!     `src/pcre2_jit_compile.c` contributes nothing to the archive; the
//!     translation unit stays in the list because it is part of upstream's
//!     source set and must compile whether or not it defines anything.
//!
//! Everything below is derived from `target.result` or from a build option.
//! Nothing is derived from the machine running the build: the cross-target
//! matrix configures six targets from one host and each one gets its own
//! `config.h`, its own header copy and its own translation.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// The upstream release this fork carries: tag `pcre2-10.49`, commit
/// 6f9d7c1373262c541324a16a358785b33ef116cf of
/// https://github.com/PCRE2Project/pcre2.git.
///
/// Only the version is a value the build can act on, so only the version is a
/// value here: build.zig refuses to configure when build.zig.zon drifts away
/// from it. The tag and the commit are stated in this comment and belong in the
/// fork's provenance record; a SHA kept in a second file that the build reads
/// would be a second place to forget to update.
const upstream_version: std.SemanticVersion = .{ .major = 10, .minor = 49, .patch = 0 };

/// `PCRE2_CODE_UNIT_WIDTH`, spelled the way the option is spelled on the
/// command line. Upstream's build.zig already exposed this enum.
pub const CodeUnitWidth = enum {
    @"8",
    @"16",
    @"32",
};

/// The width the published facade, tests and smoke are written against.
///
/// `pcre2.h.generic:1064` makes `PCRE2_SUFFIX(a)` paste the width into every
/// exported name, so a facade over the 16-bit build would be a different set of
/// functions, not a different configuration of the same ones. One width is
/// therefore the whole public surface of this fork. The 16- and 32-bit
/// libraries are still buildable and installable here as upstream's own
/// artifacts; the steps that need the facade say so instead of quietly doing
/// nothing.
const facade_width: CodeUnitWidth = .@"8";

/// The PCRE2 library sources, in the order upstream's build.zig lists them.
///
/// Explicit rather than globbed, so a new upstream translation unit cannot slip
/// into the archive without a decision here. This is the full 8-bit core: the
/// interpreter (`pcre2_match.c`), the DFA matcher (`pcre2_dfa_match.c`) and the
/// complete Unicode property machinery (`pcre2_ucd.c`, `pcre2_extuni.c`,
/// `pcre2_script_run.c`, `pcre2_xclass.c`, `pcre2_valid_utf.c`, `pcre2_ord2utf.c`)
/// that `SUPPORT_UNICODE` turns on. `pcre2_tables.c` is the compiled-in UCP
/// table. `pcre2_chartables.c` is added separately because it ships as
/// `src/pcre2_chartables.c.dist` and is copied, not compiled in place.
const core_sources = [_][]const u8{
    "src/pcre2_auto_possess.c",
    "src/pcre2_chkdint.c",
    "src/pcre2_compile.c",
    "src/pcre2_compile_cgroup.c",
    "src/pcre2_compile_class.c",
    "src/pcre2_config.c",
    "src/pcre2_context.c",
    "src/pcre2_convert.c",
    "src/pcre2_dfa_match.c",
    "src/pcre2_error.c",
    "src/pcre2_extuni.c",
    "src/pcre2_find_bracket.c",
    "src/pcre2_jit_compile.c",
    "src/pcre2_maketables.c",
    "src/pcre2_match.c",
    "src/pcre2_match_data.c",
    "src/pcre2_match_next.c",
    "src/pcre2_newline.c",
    "src/pcre2_ord2utf.c",
    "src/pcre2_pattern_info.c",
    "src/pcre2_script_run.c",
    "src/pcre2_serialize.c",
    "src/pcre2_string_utils.c",
    "src/pcre2_study.c",
    "src/pcre2_substitute.c",
    "src/pcre2_substring.c",
    "src/pcre2_tables.c",
    "src/pcre2_ucd.c",
    "src/pcre2_valid_utf.c",
    "src/pcre2_xclass.c",
};

/// Required compile-only targets. `zig build check` compiles the C core, the
/// facade, the tests and the smoke for every one of them without running
/// anything.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// Upstream's own C flags. `-fvisibility=hidden` is not cosmetic: the exported
/// names get `__attribute__((visibility("default")))` from `PCRE2_EXPORT` in
/// the generated `config.h`, and everything else stays internal so a static
/// archive linked into somebody else's shared library does not re-export PCRE2
/// internals. This is the same reason upstream applies it to both the static and
/// the dynamic build.
const core_c_flags = [_][]const u8{
    "-fvisibility=hidden",
};

/// The root of the behavioural tests. One file, because it is the file the
/// cross-target matrix compiles: a root that only re-exported per-topic files
/// would prove nothing unless every topic file were compiled too.
const test_root = "tests.zig";

/// The root of the runnable example.
const smoke_root = "smoke.zig";

/// The fork's independent fixtures. A named module rather than a relative
/// import, because a Zig module's root is its root source file's directory:
/// `tests.zig` sits at the repository root, and `smoke.zig` sits next to it, so
/// neither can reach `testdata/` by a path that is stable from both. The
/// fixtures reach the facade through the same `pcre2` module the tests use.
const fixtures_root = "testdata/foundation-fixtures.zig";

const Pcre2Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sanitize_c: std.zig.SanitizeC,
    linkage: std.builtin.LinkMode,
    /// The kind of installed library `use_system` binds to, kept apart from
    /// `linkage` because that one describes what this graph builds and system
    /// mode builds nothing. Only the main graph sets it; a cross-target check
    /// always builds from the in-tree sources and reads nothing.
    system_linkage: std.builtin.LinkMode = .dynamic,
    width: CodeUnitWidth,
    use_system: bool,
    /// Register the facade in the package's public module set. Only the main
    /// graph does; a cross target check needs the private form, because modules
    /// are registered by name against the whole build and registering `pcre2`
    /// once per target would leave only the last one reachable and silently
    /// stop checking the rest.
    register_module: bool,
};

/// The inputs this graph generates rather than reading from the tree.
///
/// They are created per target and handed to the callers that need them, so
/// `pcre2-posix` and `pcre2test` are compiled against the same `config.h` and
/// the same `pcre2.h` copy as the core they link, rather than against a second
/// set that could differ.
const Generated = struct {
    /// The `pcre2.h` every translation unit and every dependent includes.
    header: std.Build.LazyPath,
    /// The directory that holds it, for `addIncludePath`.
    header_dir: std.Build.LazyPath,
    config_header: *std.Build.Step.ConfigHeader,
};

/// Everything a dependent needs.
const Pcre2Package = struct {
    /// The facade module, with `c` bound to the translation of the same header
    /// the archive was compiled against.
    module: *std.Build.Module,
    /// The compiled core. Null in `-fsys=pcre2-8` mode, where the library comes
    /// from the system instead.
    artifact: ?*std.Build.Step.Compile,
    /// The generated inputs. Null in `-fsys=pcre2-8` mode: nothing is compiled
    /// there, so nothing is generated either.
    generated: ?Generated,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const rt = target.result;

    const linkage_option = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Link the PCRE2 artifacts statically or dynamically. In -fsys=pcre2-8 " ++
            "mode this graph builds no artifact at all, so there the option names " ++
            "the kind of installed library to bind to instead, and the " ++
            "PCRE2_STATIC declaration macro follows it.",
    );
    const linkage = linkage_option orelse @as(std.builtin.LinkMode, if (rt.isGnuLibC()) .dynamic else .static);
    // The kind of installed library `-fsys=pcre2-8` binds to. Both the linker
    // search mode and the PCRE2_STATIC declaration macro are derived from this
    // one value, so the declaration decoration and the library it binds to
    // cannot end up describing two different things. It defaults to dynamic
    // rather than to `linkage`, because `linkage` is about artifacts compiled
    // out of this repository's own `src/` and system mode compiles none;
    // `Module.linkSystemLibrary` prefers dynamic when the option is not passed
    // at all (`lib/std/Build/Module.zig:359`), so naming the default changes
    // what a default system build links not one thing.
    const system_linkage = linkage_option orelse std.builtin.LinkMode.dynamic;

    const sanitize_c = b.option(
        std.zig.SanitizeC,
        "sanitize_c",
        "Undefined behaviour sanitizer for the C sources",
    ) orelse .off;
    const width = b.option(
        CodeUnitWidth,
        "code-unit-width",
        "PCRE2_CODE_UNIT_WIDTH to build. 8 is the default and the only width " ++
            "this fork's Zig facade, tests and smoke are written against; 16 and " ++
            "32 build and install upstream's library of that width, and the " ++
            "facade steps then fail with that stated rather than passing empty.",
    ) orelse facade_width;
    const use_system = b.systemIntegrationOption("pcre2-8", .{ .default = false });

    const package_version = std.SemanticVersion.parse(manifest.version) catch {
        @panic("build.zig.zon: .version is not a semantic version");
    };
    if (package_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the pinned upstream release");
    }
    if (use_system and width != facade_width) {
        @panic("-fsys=pcre2-8 links libpcre2-8, which is the 8-bit library; it cannot be combined with a different -Dcode-unit-width");
    }
    if (use_system and !target.query.isNative()) {
        @panic("-fsys=pcre2-8 names a library installed on this machine; it has no meaning for a foreign -Dtarget");
    }

    const pcre2 = addPcre2(b, .{
        .target = target,
        .optimize = optimize,
        .sanitize_c = sanitize_c,
        .linkage = linkage,
        .width = width,
        .system_linkage = system_linkage,
        .use_system = use_system,
        .register_module = true,
    });

    // ---- Installed artifacts ---------------------------------------------
    //
    // `zig build` installs the compiled C artifacts and their public headers,
    // and compiles the smoke example. The example is not installed: it is the
    // cheapest proof that the facade and the C agree on types, symbols and
    // link-time dependencies, and a proof is not a deliverable.

    if (pcre2.artifact) |artifact| {
        const generated = pcre2.generated.?;
        b.installArtifact(artifact);
        // Installing a header also puts it on the include path of every
        // compilation that links this artifact, so a dependent that wants the C
        // API does not have to reach into this repository's tree.
        artifact.installHeader(generated.header, "pcre2.h");

        const shared: SharedOptions = .{
            .target = target,
            .optimize = optimize,
            .sanitize_c = sanitize_c,
            .linkage = linkage,
            .width = width,
            .generated = generated,
            .core = artifact,
        };

        // The POSIX wrapper is 8-bit by construction and not by preference:
        // `regexec` takes a `char *` subject and `regmatch_t::rm_so` counts
        // bytes, so a wrapper compiled against a 16- or 32-bit core would
        // reinterpret every subject byte as a wide code unit and produce
        // answers that are wrong rather than absent. Upstream's build.zig
        // builds it only for the 8-bit library and this fork keeps that.
        var posix: ?*std.Build.Step.Compile = null;
        if (width == .@"8") {
            const wrapper = addPosixLibrary(b, shared);
            b.installArtifact(wrapper);
            wrapper.installHeader(b.path("src/pcre2posix.h"), "pcre2posix.h");
            // Upstream's named lazy paths, kept so a consumer written against
            // upstream's build.zig still resolves them.
            b.addNamedLazyPath("pcre2posix.h", b.path("src/pcre2posix.h"));
            posix = wrapper;
        }

        b.installArtifact(addPcre2Test(b, .{ .options = shared, .posix = posix }));
    }

    // ---- Tests, smoke, cross-target check --------------------------------

    const test_step = b.step("test", "Run the behavioural tests");
    const smoke_step = b.step("smoke", "Run the deterministic example");
    const check_step = b.step(
        "check",
        "Compile the C core, the facade, the tests and the smoke without running them",
    );

    if (width != facade_width) {
        // Said out loud rather than left as a step with no dependencies: a step
        // that succeeds having compiled nothing is worse than one that refuses.
        const why = b.fmt(
            "-Dcode-unit-width={t} builds upstream's {d}-bit library, but this fork's facade, " ++
                "tests and smoke are the {d}-bit API. `zig build` still installs that library " ++
                "and its header; drop the option to get the full gate.",
            .{ width, @intFromEnum(width), @intFromEnum(facade_width) },
        );
        test_step.dependOn(&b.addFail(why).step);
        smoke_step.dependOn(&b.addFail(why).step);
        check_step.dependOn(&b.addFail(why).step);
    } else {
        const unit_tests = b.addTest(.{ .root_module = testModule(b, target, optimize, pcre2.module) });
        test_step.dependOn(&b.addRunArtifact(unit_tests).step);

        const smoke = b.addExecutable(.{
            .name = "pcre2-smoke",
            .root_module = smokeModule(b, target, optimize, pcre2.module),
        });
        smoke_step.dependOn(&b.addRunArtifact(smoke).step);
        b.getInstallStep().dependOn(&smoke.step);

        // `zig build check` never executes a target binary. An explicit
        // -Dtarget narrows the matrix to that one target; without one, all six
        // are built. Neither path skips a target silently.
        if (!target.query.isNative()) {
            addTargetCheck(b, check_step, target.query, optimize, sanitize_c, linkage);
        } else {
            for (check_targets) |query| {
                addTargetCheck(b, check_step, query, optimize, sanitize_c, linkage);
            }
        }
    }

    // ---- Formatting -------------------------------------------------------

    const fmt_paths = [_][]const u8{
        "build.zig",
        "build.zig.zon",
        "zig",
        "tests.zig",
        "smoke.zig",
        "consumer",
        fixtures_root,
    };
    const fmt_check = b.step("fmt-check", "Check Zig formatting");
    fmt_check.dependOn(&b.addFmt(.{ .paths = &fmt_paths, .check = true }).step);
    const fmt = b.step("fmt", "Format this fork's Zig sources in place");
    fmt.dependOn(&b.addFmt(.{ .paths = &fmt_paths }).step);
}

/// Compiles, but never runs, the public surface for one target.
///
/// Compiling the test binary is what makes this a check of the facade rather
/// than of an unreferenced archive: Zig analyses a function body only when
/// something calls it, `tests.zig` calls every public facade entry point, and so
/// compiling it for a target analyses all of them for that target. The full C
/// source list is compiled by the same graph, for that same target, with that
/// target's `config.h`. Nothing is run, so every result here is compile
/// evidence and not a claim that a cross-built binary executed.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    sanitize_c: std.zig.SanitizeC,
    linkage: std.builtin.LinkMode,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const triple = cross_target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);

    const cross = addPcre2(b, .{
        .target = cross_target,
        .optimize = optimize,
        .sanitize_c = sanitize_c,
        .linkage = linkage,
        .width = facade_width,
        // The system library path is meaningless for a foreign target, so the
        // cross matrix always builds from the in-tree sources.
        .use_system = false,
        .register_module = false,
    });

    const cross_test = b.createModule(.{
        .root_source_file = b.path(test_root),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "pcre2", .module = cross.module },
            .{ .name = "foundation_fixtures", .module = fixturesModule(b, cross_target, optimize, cross.module) },
        },
    });
    step.dependOn(&b.addTest(.{ .name = b.fmt("check-{s}-tests", .{triple}), .root_module = cross_test }).step);

    const cross_smoke = b.createModule(.{
        .root_source_file = b.path(smoke_root),
        .target = cross_target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "pcre2", .module = cross.module }},
    });
    step.dependOn(&b.addExecutable(.{
        .name = b.fmt("check-{s}-smoke", .{triple}),
        .root_module = cross_smoke,
    }).step);
}

/// Compiles the core and publishes the facade for one target.
fn addPcre2(b: *std.Build, options: Pcre2Options) Pcre2Package {
    var artifact: ?*std.Build.Step.Compile = null;
    var generated: ?Generated = null;

    // ---- Generated inputs -------------------------------------------------
    //
    // Both of these are per target and are created in the build function, so
    // they are resolved in the make step that needs them rather than during
    // configuration. `config.h` in particular encodes the target's OS and libc,
    // and handing a foreign target the host's answers would compile a library
    // that believes it is running on the machine that configured it.

    if (!options.use_system) {
        // `src/pcre2.h.generic` is upstream's width-independent public header.
        // The copy is named `pcre2.h` because that is the name every upstream
        // source file includes: `pcre2_internal.h:173` does
        // `#include "pcre2.h"`, quoted, from `src/`, and there is no
        // `src/pcre2.h` in the repository. Naming the copy `pcre2.h` is
        // therefore what makes that bare include resolve, and it is the same
        // file `translate.h` reads, so the translated declarations and the
        // compiled archive cannot be two different revisions.
        const header_files = b.addWriteFiles();
        const header = header_files.addCopyFile(b.path("src/pcre2.h.generic"), "pcre2.h");
        generated = .{
            .header = header,
            .header_dir = header_files.getDirectory(),
            .config_header = addConfigHeader(b, options),
        };

        const core_mod = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            .sanitize_c = options.sanitize_c,
            .link_libc = true,
        });
        core_mod.addCMacro("HAVE_CONFIG_H", "");
        core_mod.addCMacro("PCRE2_CODE_UNIT_WIDTH", @tagName(options.width));
        switch (options.linkage) {
            // Without PCRE2_STATIC the Windows build declares the whole API
            // `extern __declspec(dllexport)` (`pcre2_internal.h:154-160`) and a
            // translation declares it `__declspec(dllimport)`
            // (`pcre2.h.generic:56-59`); the two have to agree with whatever
            // was actually produced.
            .static => core_mod.addCMacro("PCRE2_STATIC", ""),
            .dynamic => {},
        }
        core_mod.addConfigHeader(generated.?.config_header);
        core_mod.addIncludePath(generated.?.header_dir);
        core_mod.addIncludePath(b.path("src"));

        // The character tables ship as a `.dist` file upstream copies into
        // place; this is that copy. It is added on its own because its name in
        // the repository is not the name it is compiled under, and because a
        // `.dist` entry in the source list would be a build that breaks the
        // moment upstream renames it.
        core_mod.addCSourceFile(.{
            .file = b.addWriteFiles().addCopyFile(b.path("src/pcre2_chartables.c.dist"), "pcre2_chartables.c"),
            .flags = &core_c_flags,
        });
        core_mod.addCSourceFiles(.{ .files = &core_sources, .flags = &core_c_flags });

        artifact = b.addLibrary(.{
            .name = b.fmt("pcre2-{t}", .{options.width}),
            .root_module = core_mod,
            .linkage = options.linkage,
        });
    }

    // ---- The translated C -------------------------------------------------
    //
    // One aggregate header, and which header it names is the whole point of
    // the two modes. Bundled mode reads `translate.h`, which includes the
    // `pcre2.h` copy this graph just made, so the translation and the archive
    // describe one revision. System mode reads a generated wrapper that
    // includes `<pcre2.h>` by angle brackets, so the translation sees the
    // header that is actually installed beside the library it links;
    // translating this repository's 10.49 header against an older installed
    // library would bind an ABI that may not be the one on disk.
    //
    // Bundled mode reads `translate.h` through one of two front ends, and
    // `aggregateRoute` says which one this target gets and why. Either way the
    // header the translator reads is this repository's own 10.49 header
    // expanded for the target being built, and each of the two declaration
    // macros reaches it exactly once: on the preprocessing line where there is
    // one, because `-dD` keeps the `#define` lines in the file the translator
    // parses, and on the translation line where there is not.
    // `systemAggregate` says why system mode is not treated the same way again.

    const route = aggregateRoute(options);
    const translate_c = b.addTranslateC(.{
        .root_source_file = switch (options.use_system) {
            true => systemAggregate(b),
            false => switch (route) {
                .aro => b.path("translate.h"),
                .preprocessed => preprocessedAggregate(b, options, generated.?.header_dir),
            },
        },
        .target = options.target,
        .optimize = options.optimize,
        .link_libc = true,
    });
    if (options.use_system) {
        // The two declaration macros, on the line that reads the header. In
        // bundled mode they are on the preprocessing line or, on the route that
        // has none, on this one, so in every mode they are defined exactly
        // once, on exactly one line.
        //
        // `src/pcre2.h.generic:56-63` reads PCRE2_STATIC only under
        // `defined(_WIN32)`. Without it every declaration is
        // `extern __declspec(dllimport)`, which is how a translation declares
        // a symbol it expects a DLL to provide; with it every declaration is
        // plain `extern`. That `#if` is false on an ELF target and on macOS,
        // so the macro is never read there and this says nothing about them.
        // Upstream states the rule the same way for its own builds:
        // `configure.ac:728-738` defines PCRE2_STATIC only when the static
        // library is the one being built. Here it follows the kind of installed
        // library this mode was asked to bind to, which is the one value the
        // linker below is asked for.
        translate_c.defineCMacro("PCRE2_CODE_UNIT_WIDTH", @tagName(options.width));
        if (options.system_linkage == .static) translate_c.defineCMacro("PCRE2_STATIC", "1");
    } else if (route == .aro) {
        // The same two macros and the same rule as the block above, for the
        // same reason: Aro preprocesses `translate.h` for itself on this
        // route, so there is no `-dD` output in which the macros would
        // already be defined. `PCRE2_STATIC` follows this graph's own linkage
        // here, which is the archive the translation is bound to, exactly as
        // it does on the C compile line above.
        translate_c.defineCMacro("PCRE2_CODE_UNIT_WIDTH", @tagName(options.width));
        if (options.linkage == .static) translate_c.defineCMacro("PCRE2_STATIC", "1");
        // The `pcre2.h` copy. `translate.h` includes it with quotes from the
        // repository root, where there is no such file, so this is the path it
        // is found on - the same copy the C core above was compiled against,
        // which is what keeps the translation and the archive one revision.
        translate_c.addIncludePath(generated.?.header_dir);
    }

    // ---- The published module --------------------------------------------

    // `b.addModule` when this graph is the one a dependent resolves, so
    // `dep.module("pcre2")` finds it; `b.createModule` for a cross target
    // check, where a second registration of the same name would shadow the
    // first. The module carries a resolved target because
    // `Module.linkSystemLibrary` calls `requireKnownTarget`, so a module built
    // with only a root source file panics at configure time the moment a system
    // library is linked through it.
    const module = if (options.register_module)
        b.addModule("pcre2", .{
            .root_source_file = b.path("zig/root.zig"),
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path("zig/root.zig"),
            .target = options.target,
            .optimize = options.optimize,
            .link_libc = true,
        });
    module.addImport("c", translate_c.createModule());

    if (options.use_system) {
        // The linker name, not the project name. Debian, Ubuntu, Fedora,
        // Homebrew and MSYS2 all install this as `libpcre2-8`, which is the
        // only name `-l` can resolve, and no pkg-config query is needed to
        // find it. Asking pkg-config for `pcre2-8` would find nothing: the
        // `.pc` file is named after the library (`libpcre2-8.pc`), not after
        // the project.

        // Which kind to look for, named rather than left to the default. It
        // maps to the linker flag `-search_paths_first` for dynamic and
        // `-search_paths_first_static` for static
        // (`lib/std/Build/Step/Compile.zig:1109-1112`), so the default system
        // build's linker line is unchanged and the static case says out loud
        // that a static archive is what is wanted. Both flags still let the
        // linker fall back to the other kind when a machine has only that one
        // installed; which kind a machine has installed is its own
        // arrangement, not a fact this build graph can read, so the macro
        // above describes the kind that was asked for and not the kind that
        // was found.
        module.linkSystemLibrary("pcre2-8", .{
            .use_pkg_config = .no,
            .preferred_link_mode = options.system_linkage,
        });
    } else {
        // A dependent that compiles its own C against this module needs the
        // same header the library was compiled with, on the compile line and
        // not only on the installation line.
        module.addIncludePath(generated.?.header_dir);
        module.linkLibrary(artifact.?);
        if (options.register_module) b.addNamedLazyPath("pcre2.h", generated.?.header);
    }

    return .{ .module = module, .artifact = artifact, .generated = generated };
}

/// Which of the two front ends reads the bundled aggregate for one target.
const AggregateRoute = enum {
    /// Aro, the parser `zig translate-c` drives, preprocesses `translate.h`
    /// for itself and parses what comes out.
    aro,
    /// The target's own C preprocessor expands `translate.h` first, and Aro
    /// parses what that produced.
    preprocessed,
};

/// Chooses the front end that reads `translate.h` for this target.
///
/// `zig translate-c` parses with Aro, and Aro preprocesses as well as parses,
/// so a header can be read either way round: Aro can do both jobs, or the
/// target's own C preprocessor (`zig cc -E -dD`) can do the first and Aro the
/// second. Both routes read the same `pcre2.h` copy on the same include path
/// with the same two declaration macros, so this decides which preprocessor has
/// to understand the target's C library and nothing else.
///
/// ## Aro, on a target whose C library is GNU libc
///
/// `OBSERVED`. Aro translated all three explicit GNU-libc targets from
/// `translate.h` as it stands, with no step in front of it: `check` 9/9, with
/// `translate-c success` and the header copy the only thing under it
/// (`local://foundation-expansion-pcre2-matrix-x86_64-linux-gnu-162.log:1-18`,
/// and the same for aarch64 and riscv64 in `-163.log` and `-166.log`).
///
/// ## The target's own preprocessor on every other target
///
/// Aro's preprocessor cannot read the C library on twelve of the published
/// 53-platform matrix targets. `preprocessedAggregate` names those twelve one
/// by one, with the header line that fails, and those targets get the extra
/// front end.
///
/// ## Why GNU libc is not one of those twelve
///
/// Aro reads the glibc headers. The target's own preprocessor reads the same
/// headers, expands them, and leaves five lines in the file Aro then reads
/// that Aro cannot parse. glibc hands a compiler with no native `_FloatN` type
/// a `typedef` for one, and the `!__GNUC_PREREQ (7, 0)` guard on each of those
/// lines held for the compiler that expands them here: the four in
/// `generic-glibc/bits/floatn-common.h:213-215`, `:250-252`, `:267-269` and
/// `:284-286`, where that guard is the whole condition, and `_Float128` at
/// `generic-glibc/bits/floatn.h:79-81` on aarch64 and riscv64 or
/// `x86-linux-gnu/bits/floatn.h:94-97` on x86, where it is the first of three.
/// So the `-E` output carries `typedef float _Float32;` and its four siblings.
/// Aro holds those five names as builtin type specifiers of its own, so on each
/// of those lines it has read one declaration specifier, then a second, and
/// then wants the name being declared: "cannot combine with previous 'float'
/// specifier" and "expected identifier or '('", eleven errors in all
/// (`baseline-pcre2-x86_64-linux-gnu.log:3-35`, and the same on aarch64 and
/// riscv64).
///
/// That is a disagreement between two preprocessors about one C library, not a
/// defect in `pcre2.h`, which names none of the five types and includes only
/// `<limits.h>`, `<stdlib.h>` and `<inttypes.h>` (`src/pcre2.h.generic:87-89`).
/// So this header goes to Aro unread rather than to a repair, because each
/// repair on offer is a worse answer: taking the typedefs out of the
/// preprocessed text edits a C library header this build does not own, spelling
/// `typedef float _Float32` as anything else renames a standard type, and
/// `-D__GNUC__=7` or a `-D__clang_major__` on the preprocessing line describes
/// a compiler this target does not have - which is the substitute that each of
/// the NetBSD, MIPS and Windows repairs below refuses.
fn aggregateRoute(options: Pcre2Options) AggregateRoute {
    return if (options.target.result.isGnuLibC()) .aro else .preprocessed;
}

/// The system-mode aggregate.
///
/// Angle brackets, and nothing else. `#include <pcre2.h>` resolves through the
/// target's own system include search, which is how the header that ships with
/// the library being linked gets read; a quoted include would be a guess about
/// where a distribution puts it.
///
/// It is read as it stands, with no step in front of it and no include path of
/// this graph on the translation line: the header is the one the machine
/// holding the installed library put where its own system include search finds
/// it, and that machine's Aro reads it from there. `translate.h` on the
/// GNU-libc route is read as it stands too, but for the other reason
/// `aggregateRoute` gives. `-fsys=pcre2-8` refuses a foreign
/// `-Dtarget`, so this mode is always the native target's, and no
/// failure of this aggregate has been observed; narrowing its input further
/// would be a change with no observed cause behind it.
fn systemAggregate(b: *std.Build) std.Build.LazyPath {
    return b.addWriteFiles().add("pcre2_system.h",
        \\#ifndef FOUNDATION_PCRE2_SYSTEM_AGGREGATE_H
        \\#define FOUNDATION_PCRE2_SYSTEM_AGGREGATE_H
        \\#include <pcre2.h>
        \\#endif
        \\
    );
}

/// The bundled translation root, preprocessed for the target being built.
///
/// One of the two routes `aggregateRoute` chooses between: this one is the
/// target's own C preprocessor in front of the translator, the other is the
/// translator alone. `aggregateRoute` says which target gets which and why, so
/// this says what the extra front end is for.
///
/// ## Why these targets get an extra front end
///
/// `zig translate-c` reads C with Aro, and Aro is not the preprocessor this
/// repository's C is compiled by. `src/pcre2.h.generic:87-89` includes
/// `<limits.h>`, `<stdlib.h>` and `<inttypes.h>` for `size_t` and the
/// fixed-width integer types, so every translation drags in the target's real
/// C library headers. On twelve of the published 53-platform matrix targets
/// those headers do not survive Aro's own read of them:
///
///   * every NetBSD target, which is nine of them. NetBSD defines
///     `__BEGIN_PUBLIC_DECLS` and `__END_PUBLIC_DECLS` with the `_Pragma`
///     operator (`generic-netbsd/sys/cdefs.h:411-416`), and Aro 0.16 leaves the
///     pragma in the token stream, so the trailing `__END_DECLS` of
///     `sys/types.h`, `sys/endian.h`, `sys/bswap.h`, `<stdlib.h>` and
///     `<inttypes.h>` each stop parsing with "unknown type name 'pragma'"
///     (`local://foundation-cross-test-matrix-pcre2-*-netbsd.log`).
///   * `mips64-openbsd` and `mips64el-openbsd`. `generic-openbsd/mips64/endian.h:32-41`
///     refuses to define `BYTE_ORDER` unless `__MIPSEL__` or `__MIPSEB__` is
///     defined, and Aro's MIPS predefined macro table defines neither.
///   * `x86-windows`. `any-windows-any/malloc.h:183-187` derives
///     `_ALLOCA_S_MARKER_SIZE` from `_ARM_`, `_X86_`, `__ia64__`, `__x86_64`
///     or `__aarch64__`, and Aro's Windows-x86 predefined macro table defines
///     none of them, so the two inline functions in that header that mention it
///     do not compile.
///
/// Each is a property of the translator rather than of this repository's
/// header, and the local repair in every case would be to invent the predefine
/// the real compiler supplies: `-D__MIPSEB__`, `-D_X86_`, or a replacement for
/// `_Pragma`. Those macros decide what the C library headers mean, so faking
/// them would describe a target that does not exist. Reading the same header
/// through the preprocessor that also compiles the C core is not a substitute
/// for any of them: the target, the include path, the width and the linkage
/// macro are the ones the archive was built with, so the declarations the
/// translator reads are the ones that archive answers to.
///
/// ## What is on this line, and what the translator then reads
///
/// `-dD` keeps the `#define` lines beside the expanded text, so a macro a C
/// caller reads as a macro still reaches Zig as a constant. Without it the
/// macro is expanded away and `pcre2.c.PCRE2_INFO_CAPTURECOUNT` and
/// `pcre2.c.PCRE2_CONFIG_VERSION`, which `zig/root.zig` names, would stop
/// existing; the `_Pragma` directives the NetBSD headers carry come through as
/// the `#pragma` lines a preprocessor emits, which is the form the translator
/// already reads from `<stdlib.h>` on a Windows target.
///
/// `PCRE2_CODE_UNIT_WIDTH` is defined here rather than on the translation line
/// on this route, for the same reason `PCRE2_STATIC` is: `-dD` dumps both with
/// everything else, so defining them again there would define each of them
/// twice. The width is the value the C core is compiled with, because
/// `src/pcre2.h.generic:1064` pastes it into every exported name and the name
/// it produces is the symbol the archive defines. `PCRE2_STATIC` is defined
/// when, and only when, the entry points this translation declares are the ones
/// a static archive provides.
///
/// `core_c_flags` is not repeated here. It is a code-generation flag, and the
/// preprocessor neither needs it nor acts on it.
///
/// ## Why this line also says `-fno-blocks`
///
/// The preprocessing and the translation are two front ends, and they have to
/// be asked for the same language. Otherwise the second one reads a header the
/// first one wrote in a dialect it does not have.
///
/// Aro, which is what `zig translate-c` parses with, has no block pointers.
/// Clang's driver enables the blocks extension by default for a Darwin target,
/// and Clang defines `__BLOCKS__` only while it is enabled
/// (`clang/lib/Frontend/InitPreprocessor.cpp:1019-1022` in upstream LLVM, `if
/// (LangOpts.Blocks) { Builder.defineMacro("__BLOCKS__"); }`), with
/// `LangOpts.Blocks` decided by whether `-fblocks` was passed
/// (`clang/lib/Frontend/CompilerInvocation.cpp:4301`). The Darwin C library
/// then declares six entry points that take a block pointer - `atexit_b`,
/// `bsearch_b`, `heapsort_b`, `mergesort_b`, `psort_b` and `qsort_b` - each of
/// them under `#ifdef __BLOCKS__` in `any-darwin-any/_stdlib.h`, and Aro stops
/// on every one with "expected ')', found '^'": 23 errors on `aarch64-macos`
/// by itself (`local://foundation-cross-test-corrected-pcre2-aarch64-macos.log:8-91`),
/// and the same on `x86_64-macos`, `aarch64-maccatalyst` and
/// `x86_64-maccatalyst`.
///
/// `-fno-blocks` is the switch that puts the two front ends in one dialect, so
/// this line expands the header the way the translator would have expanded it
/// for itself. It takes nothing from PCRE2: `src/pcre2.h.generic:87-89`
/// includes `<limits.h>`, `<stdlib.h>` and `<inttypes.h>` and names no block
/// type anywhere, so what leaves the file is six declarations of the target's
/// C library that the translator could never have held - which is where they
/// were before this step existed, when the translator preprocessed for itself.
///
/// The flag is on the line for every target that reaches this route, and not
/// only for the four Darwin ones, because it describes the translator rather
/// than the target. On every other target Clang leaves blocks off by default,
/// so there it changes nothing.
fn preprocessedAggregate(
    b: *std.Build,
    options: Pcre2Options,
    header_dir: std.Build.LazyPath,
) std.Build.LazyPath {
    // `-fno-blocks` is a language choice and not a code-generation one: it is
    // what keeps this line and the translator in the same dialect. The section
    // of the comment above that names it says which declarations it keeps out
    // and why none of them is PCRE2's.
    const run = b.addSystemCommand(&[_][]const u8{ b.graph.zig_exe, "cc", "-E", "-dD", "-fno-blocks", "-x", "c" });
    run.setName("preprocess pcre2.h");
    if (!options.target.query.isNative()) {
        const triple = options.target.query.zigTriple(b.allocator) catch @panic("out of memory");
        run.addArg("-target");
        run.addArg(triple);
    }
    // The generated `pcre2.h` copy, the same one every C translation unit of
    // the core includes, so the header that is preprocessed is the header the
    // archive was compiled against rather than a second revision of it.
    run.addPrefixedDirectoryArg("-I", header_dir);
    run.addArg(b.fmt("-DPCRE2_CODE_UNIT_WIDTH={s}", .{@tagName(options.width)}));
    if (options.linkage == .static) run.addArg("-DPCRE2_STATIC=1");
    run.addArg("-o");
    const preprocessed = run.addOutputFileArg("pcre2_preprocessed.h");
    run.addFileArg(b.path("translate.h"));
    return preprocessed;
}

/// Generates `config.h` for the target being built.
///
/// The template is upstream's `src/config-cmake.h.in` and the value set is the
/// one upstream's Zig graph already used; every decision in it is made from
/// `target.result`, never from the host, so a foreign target gets a `config.h`
/// describing the foreign target. The options listed here are exactly the ones
/// the template's `@VAR@` substitutions need; the `#cmakedefine` entries it
/// also declares are left undefined on purpose, because none of them is
/// available in a build that uses Zig's bundled C compiler and Zig's libc.
fn addConfigHeader(b: *std.Build, options: Pcre2Options) *std.Build.Step.ConfigHeader {
    const rt = options.target.result;
    const is_unix = rt.os.tag != .windows;
    const is_mingw = rt.isMinGW();
    const is_musl = rt.isMuslLibC();
    const is_glibc = rt.isGnuLibC();
    const is_freebsd = rt.isFreeBSDLibC();

    return b.addConfigHeader(
        .{
            .style = .{ .cmake = b.path("src/config-cmake.h.in") },
            .include_path = "config.h",
        },
        .{
            .HAVE_ASSERT_H = true,
            .HAVE_DIRENT_H = is_unix or is_mingw,
            .HAVE_SYS_STAT_H = true,
            .HAVE_SYS_TYPES_H = true,
            .HAVE_UNISTD_H = is_unix or is_mingw,
            .HAVE_WINDOWS_H = rt.os.tag == .windows,

            .HAVE_MEMFD_CREATE = is_musl or is_glibc or is_freebsd,
            .HAVE_SECURE_GETENV = is_musl or is_glibc or is_freebsd,
            .HAVE_SETRLIMIT = is_unix and !is_mingw,

            // All compilation uses Zig's bundled C compiler, so these are known
            // rather than probed. HAVE_BUILTIN_ASSUME stays null because
            // `zig cc` has no `__builtin_assume` spelling this code can use,
            // while the overflow, unreachable and uninitialized attributes all
            // exist.
            .HAVE_BUILTIN_ASSUME = null,
            .HAVE_BUILTIN_MUL_OVERFLOW = true,
            .HAVE_BUILTIN_UNREACHABLE = true,
            .HAVE_ATTRIBUTE_UNINITIALIZED = true,

            .SUPPORT_PCRE2_8 = options.width == .@"8",
            .SUPPORT_PCRE2_16 = options.width == .@"16",
            .SUPPORT_PCRE2_32 = options.width == .@"32",
            // The full Unicode property machinery: the interpreter and the DFA
            // matcher over UCP rather than the locale tables alone.
            .SUPPORT_UNICODE = true,
            // Off unconditionally in this fork: the JIT's source is a git
            // submodule this package does not ship and must not fetch.
            .SUPPORT_JIT = false,

            // As for CMake builds, use visibility attributes for both shared
            // and static builds. Internal symbols stay hidden even in a static
            // build, because the user could be statically linking PCRE2 into
            // their own shared library.
            .PCRE2_EXPORT = "__attribute__ ((visibility (\"default\")))",

            // Upstream's defaults for a build with no configure script.
            .PCRE2_LINK_SIZE = 2,
            .PCRE2_PARENS_NEST_LIMIT = 250,
            .PCRE2_HEAP_LIMIT = 20000000,
            .PCRE2_MAX_VARLOOKBEHIND = 255,
            .PCRE2_MATCH_LIMIT = 10000000,
            .PCRE2_MATCH_LIMIT_DEPTH = "MATCH_LIMIT",
            .PCRE2GREP_BUFSIZE = 20480,
            .PCRE2GREP_MAX_BUFSIZE = 1048576,
            .NEWLINE_DEFAULT = 2,
        },
    );
}

const SharedOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    sanitize_c: std.zig.SanitizeC,
    linkage: std.builtin.LinkMode,
    width: CodeUnitWidth,
    generated: Generated,
    core: *std.Build.Step.Compile,
};

/// Applies the same include paths, generated header and config.h the core got,
/// which is what keeps the wrapper and the library it links in one build
/// configuration.
fn addSharedIncludes(m: *std.Build.Module, options: SharedOptions) void {
    m.addConfigHeader(options.generated.config_header);
    m.addIncludePath(options.generated.header_dir);
    m.addIncludePath(m.owner.path("src"));
}

/// `src/pcre2posix.c`: upstream's POSIX `regcomp`/`regexec` emulation, built as
/// its own artifact against the core this graph compiled. It is not part of the
/// `pcre2` facade module and is not translated; a caller that wants it takes
/// `dep.artifact("pcre2-posix")` and the installed `pcre2posix.h`.
fn addPosixLibrary(b: *std.Build, options: SharedOptions) *std.Build.Step.Compile {
    const posix_mod = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .sanitize_c = options.sanitize_c,
        .link_libc = true,
    });
    posix_mod.addCMacro("HAVE_CONFIG_H", "");
    posix_mod.addCMacro("PCRE2_CODE_UNIT_WIDTH", @tagName(options.width));
    switch (options.linkage) {
        .static => posix_mod.addCMacro("PCRE2_STATIC", ""),
        // PCRE2POSIX_SHARED is what `src/pcre2posix.c` checks before exporting
        // its own symbols; the wrapper's visibility has to follow the same
        // linkage decision the core's does.
        .dynamic => posix_mod.addCMacro("PCRE2POSIX_SHARED", ""),
    }
    addSharedIncludes(posix_mod, options);
    posix_mod.addCSourceFiles(.{ .files = &.{"src/pcre2posix.c"}, .flags = &core_c_flags });

    const posix = b.addLibrary(.{
        .name = "pcre2-posix",
        .root_module = posix_mod,
        .linkage = options.linkage,
    });
    posix_mod.linkLibrary(options.core);
    return posix;
}

/// `src/pcre2test.c`: upstream's own test driver, built as an application.
///
/// It is an application rather than a library, so it gets the
/// application's-eye view of the API: it defines `PCRE2_CODE_UNIT_WIDTH` as 0
/// itself (`src/pcre2test.c:313`) before including `pcre2.h`, which is why this
/// module gets no `-D` for the width, and it links every library this graph
/// built.
///
/// `posix` is absent for the 16- and 32-bit libraries, for the reason given at
/// the wrapper's construction site. Upstream's build.zig links nothing there
/// either.
const Pcre2TestOptions = struct {
    options: SharedOptions,
    posix: ?*std.Build.Step.Compile,
};

fn addPcre2Test(b: *std.Build, args: Pcre2TestOptions) *std.Build.Step.Compile {
    const options = args.options;
    const test_mod = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .sanitize_c = options.sanitize_c,
        .link_libc = true,
    });
    test_mod.addCMacro("HAVE_CONFIG_H", "");
    // A consumer linking the static library has to define PCRE2_STATIC itself;
    // a shared build marks its imports the way upstream's CMake does. On
    // non-Windows targets PCRE2_STATIC is not read by the public header, so
    // this is a no-op there and a requirement on Windows.
    switch (options.linkage) {
        .static => test_mod.addCMacro("PCRE2_STATIC", ""),
        .dynamic => test_mod.addCMacro("PCRE2POSIX_SHARED", ""),
    }
    addSharedIncludes(test_mod, options);
    test_mod.addCSourceFile(.{ .file = b.path("src/pcre2test.c"), .flags = &core_c_flags });
    test_mod.linkLibrary(options.core);

    const pcre2test = b.addExecutable(.{ .name = "pcre2test", .root_module = test_mod });
    if (args.posix) |wrapper| test_mod.linkLibrary(wrapper);
    return pcre2test;
}

fn testModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    facade: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(test_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "pcre2", .module = facade },
            .{ .name = "foundation_fixtures", .module = fixturesModule(b, target, optimize, facade) },
        },
    });
}

fn smokeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    facade: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(smoke_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "pcre2", .module = facade }},
    });
}

fn fixturesModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    facade: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(fixtures_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // The fixtures publish values typed by the facade, so they need the
        // facade module itself, exactly as the test roots already have it.
        .imports = &.{.{ .name = "pcre2", .module = facade }},
    });
}
