// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.

//! PCRE2 10.49 build graph; the bundled core combines widths 8, 16, and 32 into one artifact.
//! `-Dcode-unit-width` selects the artifact name and facade aliases; runtime system integration needs all widths.
//! `-fsys=pcre2-8` links the installed 8-bit library. JIT support is disabled because SLJIT is unavailable.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// Runtime module builders. Share one core module so `LoadSource` and `LoadError` keep type identity.
/// `createModule` uses this graph's `TranslateC` step and its translated types.
const graph = @import("runtime/graph.zig");

/// Upstream PCRE2 10.49 at commit 6f9d7c1373262c541324a16a358785b33ef116cf.
/// The build rejects a `build.zig.zon` version that drifts from this value.
const upstream_version: std.SemanticVersion = .{ .major = 10, .minor = 49, .patch = 0 };

/// Version reported by pkg-config and `pcre2-config` (upstream's major.minor form).
const package_version = "10.49";

/// PCRE2 code-unit width, exposed as `-Dcode-unit-width`.
pub const CodeUnitWidth = enum {
    @"8",
    @"16",
    @"32",
};

/// Default width for facade aliases and cross-target checks; the artifact contains all widths.
const facade_width: CodeUnitWidth = .@"8";

/// Upstream libtool versions; `addLibrary` derives installed names and sonames from them.
const libtool = struct {
    /// `16:1:16` -> soversion 0, file `libpcre2-<width>.so.0.16.1`.
    pub const core: std.SemanticVersion = .{ .major = 0, .minor = 16, .patch = 1 };
    /// `3:9:0` -> soversion 3, file `libpcre2-posix.so.3.0.9`.
    pub const posix: std.SemanticVersion = .{ .major = 3, .minor = 0, .patch = 9 };
};

/// Explicit upstream core sources, compiled once per width; additions require a decision here.
/// Chartables and the `dftables` generator are handled separately because upstream ships default tables.
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

/// All widths included in the primary artifact, regardless of `-Dcode-unit-width`.
const all_widths = [_]CodeUnitWidth{ .@"8", .@"16", .@"32" };

/// Targets compiled by `zig build check`; none is run.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

/// Hide internal symbols; upstream's `PCRE2_EXPORT` marks public symbols visible.
const core_c_flags = [_][]const u8{
    "-fvisibility=hidden",
};

const test_root = "tests.zig";

const smoke_root = "smoke.zig";

/// Fixture module shared by the root-level tests and smoke example.
const fixtures_root = "testdata/foundation-fixtures.zig";

const man1_root = "share/man/man1";
const man3_root = "share/man/man3";
const doc_root = "share/doc/pcre2";
const doc_html_root = "share/doc/pcre2/html";
const licence_root = "share/licenses/pcre2";

/// Upstream documentation records installed beside the manual pages.
const upstream_records = [_][]const u8{
    "AUTHORS.md",
    "ChangeLog",
    "COPYING",
    "LICENCE.md",
    "NEWS",
    "README",
    "SECURITY.md",
    "SUPPORT-LIFECYCLE.md",
};

/// Fork provenance and licence records installed beside upstream's records.
const fork_records = [_][]const u8{
    "README.md",
    "README.zig.md",
    "README.upstream.md",
    "NOTICE.md",
    "UPSTREAM.md",
    "FORK-LICENSE.md",
    "FORK-NOTES.md",
    "CHANGELOG.md",
};

/// Licence and provenance records installed separately from documentation.
/// `cmake/COPYING-CMAKE-SCRIPTS` is excluded because `cmake/` is not in `.paths`.
const licence_records = [_][]const u8{
    "COPYING",
    "LICENCE.md",
    "AUTHORS.md",
    "README.upstream.md",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "FORK-NOTES.md",
    "UPSTREAM.sha256",
};

/// Maps library linkage to the declaration macros for the core and POSIX wrapper.
/// `PCRE2_STATIC` controls core declarations; `PCRE2POSIX_SHARED` controls wrapper declarations.
const Export = struct {
    static_core: bool,
    shared_posix: bool,
    static_cflags: []const u8,
    posix_cflags: []const u8,

    fn from(linkage: std.builtin.LinkMode) Export {
        return switch (linkage) {
            .static => .{
                .static_core = true,
                .shared_posix = false,
                .static_cflags = "-DPCRE2_STATIC",
                .posix_cflags = "",
            },
            .dynamic => .{
                .static_core = false,
                .shared_posix = true,
                .static_cflags = "",
                .posix_cflags = "-DPCRE2POSIX_SHARED",
            },
        };
    }

    /// Set the archive's width and linkage macros.
    fn addCoreLine(self: Export, m: *std.Build.Module, width: CodeUnitWidth) void {
        m.addCMacro("HAVE_CONFIG_H", "");
        m.addCMacro("PCRE2_CODE_UNIT_WIDTH", @tagName(width));
        if (self.static_core) m.addCMacro("PCRE2_STATIC", "1");
    }

    /// The POSIX wrapper consumes byte strings, so its core width is fixed at 8.
    fn addPosixLine(self: Export, m: *std.Build.Module) void {
        m.addCMacro("HAVE_CONFIG_H", "");
        m.addCMacro("PCRE2_CODE_UNIT_WIDTH", "8");
        if (self.shared_posix) m.addCMacro("PCRE2POSIX_SHARED", "1");
    }

    /// Set declaration macros for programs that call the selected libraries.
    fn addImportLine(self: Export, m: *std.Build.Module) void {
        m.addCMacro("HAVE_CONFIG_H", "");
        if (self.static_core) m.addCMacro("PCRE2_STATIC", "1");
        if (self.shared_posix) m.addCMacro("PCRE2POSIX_SHARED", "1");
    }
};

const Pcre2Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    sanitize_c: std.zig.SanitizeC,
    linkage: std.builtin.LinkMode,
    /// Linkage for an installed core; system integration builds no artifact.
    system_linkage: std.builtin.LinkMode = .dynamic,
    width: CodeUnitWidth,
    use_system: bool,
    /// Register the public module only in the main graph, not once per target check.
    register_module: bool,
    /// Route facade calls through the platform loader instead of a link line.
    runtime_loaded: bool = false,
    /// Loader route for linked facade users; installed programs use the install-tree path.
    loader: Loader = .build_cache,
};

/// Generated inputs shared by target-specific artifacts.
const Generated = struct {
    header: std.Build.LazyPath,
    header_dir: std.Build.LazyPath,
    config_header: *std.Build.Step.ConfigHeader,
};

const Pcre2Package = struct {
    /// Facade module translated against the same header as the archive.
    module: *std.Build.Module,
    /// Null when binding an installed core.
    artifact: ?*std.Build.Step.Compile,
    /// Null when system mode generates no inputs.
    generated: ?Generated,
};

const SharedOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    sanitize_c: std.zig.SanitizeC,
    linkage: std.builtin.LinkMode,
    width: CodeUnitWidth,
    generated: Generated,
    core: *std.Build.Step.Compile,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage_option = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Link the PCRE2 artifacts statically or dynamically. In -fsys=pcre2-8 " ++
            "mode this graph builds no artifact at all, so there the option names " ++
            "the kind of installed library to bind to instead, and the " ++
            "PCRE2_STATIC declaration macro follows it. The default is dynamic on " ++
            "a GNU libc target and static everywhere else, which is what this " ++
            "graph has always done, and it is decided for the target actually " ++
            "being built: `zig build check` resolves it once per target in its " ++
            "six-cell matrix rather than handing every cell the host build's " ++
            "answer. A value named on the command line applies to every one of " ++
            "them unchanged, and a target that cannot carry the artifact it asks " ++
            "for is refused by name rather than given the other linkage.",
    );
    const linkage = linkage_option orelse defaultLinkage(target);
    // System integration builds no artifact; its installed-library link mode defaults to dynamic.
    const system_linkage = linkage_option orelse std.builtin.LinkMode.dynamic;

    const sanitize_c = b.option(
        std.zig.SanitizeC,
        "sanitize_c",
        "Undefined behaviour sanitizer for the C sources",
    ) orelse .off;
    const width = b.option(
        CodeUnitWidth,
        "code-unit-width",
        "PCRE2_CODE_UNIT_WIDTH to name the primary artifact with. 8 is the " ++
            "default, and it is the width this fork's Zig facade, tests and " ++
            "smoke are written against. The artifact itself always carries " ++
            "upstream's genuine 8-, 16- and 32-bit closures, because the " ++
            "public header declares all three widths at any width; this " ++
            "option chooses the installed name, the soname, the pkg-config " ++
            "file and which width's generic aliases the facade speaks.",
    ) orelse facade_width;

    // Runtime loading bypasses the link line without changing the delivered artifact.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time instead of linking them. " ++
            "The facade keeps the same translated header and the same public " ++
            "types; each selected native function becomes a dispatch through one " ++
            "process-lifetime table that an explicit load(source) fills, with no " ++
            "fallback and no retry that is not the caller's. The native artifact " ++
            "this build delivers is unaffected - -Dlinkage still chooses its kind, " ++
            "and it is still installed - so a caller may equally name a provider " ++
            "this tree did not build.",
    ) orelse false;

    // Reject requested dynamic linkage when the target OS has no dynamic loader.
    if (!linkageSupported(linkage, target)) {
        @panic(unsupportedSharedMessage(b, target, "-Dlinkage=dynamic was requested"));
    }

    const use_system = b.systemIntegrationOption("pcre2-8", .{ .default = false });

    const manifest_version = std.SemanticVersion.parse(manifest.version) catch {
        @panic("build.zig.zon: .version is not a semantic version");
    };
    if (manifest_version.order(upstream_version) != .eq) {
        @panic("build.zig.zon .version no longer matches the pinned upstream release");
    }
    if (use_system and width != facade_width) {
        @panic("-fsys=pcre2-8 links libpcre2-8, which is the 8-bit library; it cannot be combined with a different -Dcode-unit-width");
    }
    // System integration can bind only the library installed for this machine.
    if (use_system and !isThisMachine(b, target)) {
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
        .runtime_loaded = runtime_loaded,
    });

    // Add a second `pcre2test` only when the build-cache and install-tree loader paths differ.
    // Installed programs cannot retain a build-cache rpath.
    const both_loaders = needsBothLoaders(if (runtime_loaded) null else pcre2.artifact, target);

    // Installation compiles the smoke program but never runs target binaries.
    // `zig build smoke` is the step that executes it.

    var pcre2test: ?*std.Build.Step.Compile = null;
    // Keep the POSIX wrapper beside programs that load it.
    var pcre2posix: ?*std.Build.Step.Compile = null;
    if (pcre2.artifact) |artifact| {
        const shared: SharedOptions = .{
            .target = target,
            .optimize = optimize,
            .sanitize_c = sanitize_c,
            .linkage = linkage,
            .width = width,
            .generated = pcre2.generated.?,
            .core = artifact,
        };

        b.installArtifact(artifact);
        // Expose the generated header to C dependents.
        artifact.installHeader(shared.generated.header, "pcre2.h");

        // The byte-oriented POSIX wrapper is installed only for width 8.
        var posix: ?*std.Build.Step.Compile = null;
        if (width == .@"8") {
            posix = addPosixLibrary(b, shared);
            b.installArtifact(posix.?);
            posix.?.installHeader(b.path("src/pcre2posix.h"), "pcre2posix.h");
            // Retain upstream's named path for build-script compatibility.
            b.addNamedLazyPath("pcre2posix.h", b.path("src/pcre2posix.h"));
        }
        pcre2posix = posix;

        const programs = addPrograms(b, shared, posix);
        // Install upstream's primary programs.
        b.installArtifact(programs.pcre2test);
        if (programs.pcre2grep) |grep| b.installArtifact(grep);
        // Install upstream's noninstalled POSIX test so the default graph compiles it.
        if (programs.posix_test) |pt| b.installArtifact(pt);

        installPkgConfig(b, .{ .linkage = linkage, .width = width });
        installConfigScript(b, .{ .linkage = linkage, .width = width });
        installDocumentation(b);

        installLicenceRecords(b);

        // Use the build-cache copy only when its loader path differs from the installed copy.
        pcre2test = if (both_loaders) addCachePcre2test(b, shared, posix) else programs.pcre2test;
    }

    const test_step = b.step("test", "Run the behavioural tests");
    const smoke_step = b.step("smoke", "Run the deterministic example");
    const check_step = b.step(
        "check",
        "Compile the C core, the facade, the tests and the smoke without running them",
    );

    // Run facade tests at every width; the tests gate byte-specific cases on the compiled width.
    {
        const unit_tests = b.addTest(.{ .root_module = testModule(b, target, optimize, pcre2.module) });
        test_step.dependOn(&b.addRunArtifact(unit_tests).step);
        const smoke = b.addExecutable(.{
            .name = "pcre2-smoke",
            .root_module = smokeModule(b, target, optimize, pcre2.module),
        });
        smoke_step.dependOn(&b.addRunArtifact(smoke).step);
        b.getInstallStep().dependOn(&smoke.step);

        // Checks compile only; explicit `-Dtarget` selects one target, otherwise all six.
        // Pass the original linkage option so each cell resolves its target-specific default.
        if (!target.query.isNative()) {
            addTargetCheck(b, check_step, target.query, optimize, sanitize_c, linkage_option, runtime_loaded);
        } else {
            for (check_targets) |query| {
                addTargetCheck(b, check_step, query, optimize, sanitize_c, linkage_option, runtime_loaded);
            }
        }
    }

    // Run upstream's full `RunTest` suite separately from the fork's facade tests.
    const upstream_step = b.step(
        "upstream-test",
        "Run upstream's own RunTest suite against this build's pcre2test",
    );
    if (pcre2test) |exe| {
        addUpstreamSuite(b, upstream_step, width, exe);
    } else {
        upstream_step.dependOn(&b.addFail(
            "-fsys=pcre2-8 builds no pcre2test of its own, so there is nothing for RunTest to drive",
        ).step);
    }

    // ---- Formatting -------------------------------------------------------

    const fmt_paths = b.pathList(&.{
        "build.zig",
        "build.zig.zon",
        "zig",
        "tests.zig",
        "smoke.zig",
        "consumer",
        fixtures_root,
    });
    const fmt_check = b.step("fmt-check", "Check Zig formatting");
    fmt_check.dependOn(&b.addFmt(.{ .paths = fmt_paths, .check = true }).step);
    const fmt = b.step("fmt", "Format this fork's Zig sources in place");
    fmt.dependOn(&b.addFmt(.{ .paths = fmt_paths }).step);
}

// Runtime mode builds dispatch from this graph's `TranslateC` step and omits native linking.
// Share one loader core so `LoadSource` and `LoadError` keep nominal type identity.
// The reusable loader implementation belongs to the driver.

/// Compile-only target check; tests reference the public facade declarations.
/// Each cell resolves its own default linkage; unsupported dynamic requests fail explicitly.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.lang.Optimize,
    sanitize_c: std.zig.SanitizeC,
    linkage_option: ?std.builtin.LinkMode,
    runtime_loaded: bool,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const triple = cross_target.query.zigTriple(b.allocator) catch @panic("OOM");
    defer b.allocator.free(triple);

    const linkage = linkage_option orelse defaultLinkage(cross_target);
    if (!linkageSupported(linkage, cross_target)) {
        const request = b.fmt("-Dlinkage=dynamic reaches the {s} check cell", .{triple});
        step.dependOn(&b.addFail(unsupportedSharedMessage(b, cross_target, request)).step);
        return;
    }

    const cross = addPcre2(b, .{
        .target = cross_target,
        .optimize = optimize,
        .sanitize_c = sanitize_c,
        .linkage = linkage,
        .width = facade_width,
        // Cross-checks always build from bundled sources.
        .use_system = false,
        .register_module = false,
        // Match the selected runtime route without executing or resolving a provider.
        .runtime_loaded = runtime_loaded,
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

    // Generate target-specific inputs; `config.h` must describe the build target, not the host.

    if (!options.use_system) {
        // Translate and compile against the same generated copy of upstream's generic header.
        const header_files = b.addWriteFiles();
        const header = header_files.addCopyFile(b.path("src/pcre2.h.generic"), "pcre2.h");
        generated = .{
            .header = header,
            .header_dir = header_files.getDirectory(),
            .config_header = addConfigHeader(b, options),
        };

        // Add width-specific objects directly; Zig does not fold static libraries into another archive.
        const core_mod = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            .sanitize_c = options.sanitize_c,
            .link_libc = true,
        });
        for (all_widths) |width| {
            for (addWidthObjects(b, options, generated.?, width)) |object| core_mod.addObject(object);
        }

        artifact = b.addLibrary(.{
            .name = b.fmt("pcre2-{t}", .{options.width}),
            .root_module = core_mod,
            .linkage = options.linkage,
            // Pass version numbers only on formats with sonames; Zig derives the installed name and soname.
            .version = if (options.linkage == .dynamic and hasSoname(options.target))
                libtool.core
            else
                null,
        });
        if (options.linkage == .dynamic and options.target.result.ofmt == .elf) {
            // Union upstream's three width export lists and POSIX names; hide all unlisted symbols.
            // Mach-O and COFF use visibility/export decorations instead of version scripts.
            artifact.?.setVersionScript(primaryVersionScript(b));
        }
    }

    // Bundled translation uses the generated header; system mode includes the installed header from pkg-config.
    // Keep declaration macros consistent with the compiled objects.

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
    // Define each declaration macro once on the line the translator reads; `-dD` preserves preprocessing definitions.
    // Use the same `Export` values as C compilation, including the POSIX wrapper's Windows decoration.
    const exports = Export.from(if (options.use_system) options.system_linkage else options.linkage);
    translate_c.defineCMacro("PCRE2_CODE_UNIT_WIDTH", @tagName(options.width));
    if (exports.static_core) translate_c.defineCMacro("PCRE2_STATIC", "1");
    if (exports.shared_posix) translate_c.defineCMacro("PCRE2POSIX_SHARED", "1");
    if (!options.use_system and route == .aro) {
        // Aro needs the generated header and upstream's `src/` path for the POSIX header.
        translate_c.addIncludePath(generated.?.header_dir);
        translate_c.addIncludePath(b.path("src"));
    }

    // Register the public module only in the main graph; checks use private target-specific modules.
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

    if (options.use_system and !options.runtime_loaded) {
        // Query pkg-config before creating the C module so it captures matching header and link flags.
        // Runtime mode skips this query to avoid a `DT_NEEDED` entry.
        translate_c.linkSystemLibrary("pcre2-8", .{
            .use_pkg_config = .force,
            .preferred_link_mode = options.system_linkage,
        });
    }

    var rt_core: ?*std.Build.Module = null;
    if (options.runtime_loaded) {
        module.addImport("c", graph.createModule(
            b,
            translate_c,
            options.target,
            options.optimize,
        ));
    } else {
        module.addImport("c", translate_c.createModule());
        // Share one loader core so callers and dispatch use the same `LoadSource` and `LoadError` types.
        rt_core = graph.createCoreModule(
            b,
            options.target,
            options.optimize,
        );
        module.addImport("rt", rt_core.?);
    }

    if (!options.use_system) {
        // Expose the generated header on dependents' compile lines.
        module.addIncludePath(generated.?.header_dir);
        // Runtime mode omits linkLibrary so the platform loader resolves the provider.
        // Linked facade users use the build-cache path; installed programs use the install-tree path.
        if (!options.runtime_loaded) {
            linkForLoader(module, artifact.?, options.target, options.loader);
        }
        if (options.register_module) b.addNamedLazyPath("pcre2.h", generated.?.header);
    }

    return .{
        .module = module,
        .artifact = artifact,
        .generated = generated,
    };
}

/// Compiles each width from the same explicit sources and target-specific generated headers.
/// The byte-oriented POSIX wrapper joins the width-8 core; `PCRE2_PCRE2POSIX` isolates its tables.
/// Shared COFF builds override imports on the wrapper object because it calls core symbols in the same DLL.
fn addWidthObjects(
    b: *std.Build,
    options: Pcre2Options,
    generated: Generated,
    width: CodeUnitWidth,
) []*std.Build.Step.Compile {
    // COFF requires one source per object; other formats accept a multi-source object.
    const one_at_a_time = switch (options.target.result.os.tag) {
        .windows, .uefi => true,
        else => false,
    };

    // Copy the upstream `.dist` tables once per width because the width macro renames their symbols.
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(b.allocator);
    if (width == .@"8") files.append(b.allocator, "src/pcre2posix.c") catch @panic("OOM");
    for (core_sources) |source| files.append(b.allocator, source) catch @panic("OOM");
    const chartables = b.addWriteFiles().addCopyFile(
        b.path("src/pcre2_chartables.c.dist"),
        "pcre2_chartables.c",
    );

    const exports = Export.from(options.linkage);
    const pic: ?bool = if (options.linkage == .dynamic and needsPic(options.target)) true else null;

    var objects: std.ArrayList(*std.Build.Step.Compile) = .empty;

    if (!one_at_a_time) {
        const m = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            .sanitize_c = options.sanitize_c,
            .link_libc = true,
            .pic = pic,
        });
        exports.addCoreLine(m, width);
        m.addConfigHeader(generated.config_header);
        m.addIncludePath(generated.header_dir);
        m.addIncludePath(b.path("src"));
        if (width == .@"8" and exports.shared_posix) m.addCMacro("PCRE2POSIX_SHARED", "1");
        m.addCSourceFile(.{ .file = chartables, .flags = &core_c_flags });
        m.addCSourceFiles(.{ .files = files.items, .flags = &core_c_flags });
        objects.append(b.allocator, b.addObject(.{
            .name = b.fmt("pcre2-{t}-core", .{width}),
            .root_module = m,
        })) catch @panic("OOM");
        return objects.items;
    }

    for (files.items) |file| {
        const m = b.createModule(.{
            .target = options.target,
            .optimize = options.optimize,
            .sanitize_c = options.sanitize_c,
            .link_libc = true,
            .pic = pic,
        });
        exports.addCoreLine(m, width);
        m.addConfigHeader(generated.config_header);
        m.addIncludePath(generated.header_dir);
        m.addIncludePath(b.path("src"));
        if (width == .@"8" and std.mem.eql(u8, file, "src/pcre2posix.c")) {
            if (exports.shared_posix) m.addCMacro("PCRE2POSIX_SHARED", "1");
            // Shared COFF builds override `dllimport` on this wrapper object because its core calls stay in the same DLL.
            if (exports.shared_posix) m.addCMacro("PCRE2_EXP_DECL", "extern");
        }
        m.addCSourceFile(.{ .file = b.path(file), .flags = &core_c_flags });
        objects.append(b.allocator, b.addObject(.{
            .name = b.fmt("pcre2-{t}-core-{s}", .{ width, std.fs.path.stem(file) }),
            .root_module = m,
        })) catch @panic("OOM");
    }
    const tables = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .sanitize_c = options.sanitize_c,
        .link_libc = true,
        .pic = pic,
    });
    exports.addCoreLine(tables, width);
    tables.addConfigHeader(generated.config_header);
    tables.addIncludePath(generated.header_dir);
    tables.addIncludePath(b.path("src"));
    tables.addCSourceFile(.{ .file = chartables, .flags = &core_c_flags });
    objects.append(b.allocator, b.addObject(.{
        .name = b.fmt("pcre2-{t}-core-chartables", .{width}),
        .root_module = tables,
    })) catch @panic("OOM");
    return objects.items;
}

/// ELF and Mach-O use sonames; COFF, XCOFF, and wasm do not.
fn hasSoname(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.ofmt) {
        .elf, .macho => true,
        // COFF has no soname; wasm has no dynamic loader.
        else => false,
    };
}

/// ELF and Mach-O shared objects need PIC; COFF and wasm do not.
fn needsPic(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.ofmt) {
        .elf, .macho => true,
        else => false,
    };
}

/// Windows uses the PE loader; other shared targets need a dynamic linker.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Default to dynamic on GNU libc and static elsewhere, using the target being built.
fn defaultLinkage(target: std.Build.ResolvedTarget) std.builtin.LinkMode {
    return if (target.result.isGnuLibC()) .dynamic else .static;
}

/// True only when target architecture, OS, and ABI match the host.
fn isThisMachine(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const machine = &b.graph.host.result;
    return target.result.cpu.arch == machine.cpu.arch and
        target.result.os.tag == machine.os.tag and
        target.result.abi == machine.abi;
}

/// Dynamic linkage is supported only on targets with a loader.
fn linkageSupported(linkage: std.builtin.LinkMode, target: std.Build.ResolvedTarget) bool {
    return linkage != .dynamic or targetHasDynamicLinker(target);
}

/// Allocated from `b`; `addFail` copies the message and `@panic` consumes it.
fn unsupportedSharedMessage(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    request: []const u8,
) []const u8 {
    return b.fmt(
        "{s}: {s} has no dynamic linker and so cannot load a shared object at " ++
            "all. Build the static library for that target, or choose a target " ++
            "that has one; this graph will not quietly substitute one linkage for " ++
            "the other.",
        .{ request, target.query.zigTriple(b.allocator) catch @panic("out of memory") },
    );
}

/// Selects how the bundled header is preprocessed before translation.
const AggregateRoute = enum {
    /// Aro preprocesses and parses the aggregate.
    aro,
    /// The target C preprocessor runs before Aro.
    preprocessed,
};

/// Use Aro directly for GNU libc; preprocess with the target compiler elsewhere because Aro cannot parse some target libc headers.
/// Do not fake target macros: they change the meaning of foreign libc declarations.
fn aggregateRoute(options: Pcre2Options) AggregateRoute {
    return if (options.target.result.isGnuLibC()) .aro else .preprocessed;
}

/// Include the installed header so system-mode translation matches the linked library; POSIX declarations are unavailable.
fn systemAggregate(b: *std.Build) std.Build.LazyPath {
    return b.addWriteFiles().add("pcre2_system.h",
        \\#ifndef FOUNDATION_PCRE2_SYSTEM_AGGREGATE_H
        \\#define FOUNDATION_PCRE2_SYSTEM_AGGREGATE_H
        \\#include <pcre2.h>
        \\#endif
        \\
    );
}

/// Preprocess bundled headers with the target compiler before Aro where Aro cannot parse target libc headers.
/// `-dD` preserves facade macros; `-fno-blocks` keeps Darwin headers in Aro's supported dialect.
/// Use the same target, include paths, width, and export macros as the compiled core.
fn preprocessedAggregate(
    b: *std.Build,
    options: Pcre2Options,
    header_dir: std.Build.LazyPath,
) std.Build.LazyPath {
    // `-fno-blocks` keeps Clang preprocessing and Aro translation in a compatible dialect.
    const run = b.addSystemCommand(&[_][]const u8{ b.graph.zig_exe, "cc", "-E", "-dD", "-fno-blocks", "-x", "c" });
    run.setName("preprocess pcre2.h");
    if (!options.target.query.isNative()) {
        const triple = options.target.query.zigTriple(b.allocator) catch @panic("out of memory");
        run.addArg("-target");
        run.addArg(triple);
    }
    // Use the generated core header, then upstream's `src/` directory for `pcre2posix.h`.
    run.addDirectoryArg2(header_dir, .{ .prefix = "-I" });
    run.addDirectoryArg2(b.path("src"), .{ .prefix = "-I" });
    run.addArg(b.fmt("-DPCRE2_CODE_UNIT_WIDTH={s}", .{@tagName(options.width)}));
    // `-dD` preserves the same width and linkage macros for the translator.
    const exports = Export.from(options.linkage);
    if (exports.static_core) run.addArg("-DPCRE2_STATIC=1");
    if (exports.shared_posix) run.addArg("-DPCRE2POSIX_SHARED=1");
    run.addArg("-o");
    const preprocessed = run.addOutputFileArg2("pcre2_preprocessed.h", .{});
    run.addFileArg2(b.path("translate.h"), .{});
    return preprocessed;
}

/// Generate `config.h` from upstream's template using target-derived values.
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

            // `HAVE_BUILTIN_ASSUME` stays unset; Zig's bundled C compiler lacks the required spelling.
            .HAVE_BUILTIN_ASSUME = null,
            .HAVE_BUILTIN_MUL_OVERFLOW = true,
            .HAVE_BUILTIN_UNREACHABLE = true,
            .HAVE_ATTRIBUTE_UNINITIALIZED = true,

            // Enable all widths because the primary artifact exports all three.
            .SUPPORT_PCRE2_8 = true,
            .SUPPORT_PCRE2_16 = true,
            .SUPPORT_PCRE2_32 = true,
            // Enable Unicode property support.
            .SUPPORT_UNICODE = true,
            // JIT is disabled because this package cannot fetch its SLJIT submodule.
            // Keep JIT-only grep options disabled with `SUPPORT_JIT`.
            .SUPPORT_JIT = false,
            .SLJIT_PROT_EXECUTABLE_ALLOCATOR = false,
            .SUPPORT_PCRE2GREP_JIT = false,

            // Hide internals in static and shared builds; `PCRE2_EXPORT` marks public symbols visible.
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

/// Apply the same generated headers and `config.h` as the core.
fn addSharedIncludes(m: *std.Build.Module, options: SharedOptions) void {
    m.addConfigHeader(options.generated.config_header);
    m.addIncludePath(options.generated.header_dir);
    m.addIncludePath(m.owner.path("src"));
}

/// Build-cache users need a cache rpath; installed programs need a relocatable path.
const Loader = enum {
    /// Relocatable search path for installed programs.
    install_tree,
    /// Build-cache rpath for the facade, tests, and build-only programs.
    build_cache,
};

/// Link a library and add only the search path required by the selected loader route.
fn linkForLoader(
    m: *std.Build.Module,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    loader: Loader,
) void {
    // Windows uses an import library and has no rpath.
    if (library.linkage != .dynamic or target.result.os.tag == .windows) {
        m.linkLibrary(library);
        return;
    }
    switch (loader) {
        .build_cache => m.linkLibrary(library),
        .install_tree => {
            m.addObjectFile(library.getEmittedBin());
            if (installedProgramRPath(target)) |p| m.addRPathSpecial(p);
        },
    }
}

/// Build a second program only when the loader routes differ.
fn needsBothLoaders(
    linked: ?*std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) bool {
    const library = linked orelse return false;
    return library.linkage == .dynamic and target.result.os.tag != .windows;
}

/// Use a relocatable path to reach libraries beside installed programs.
fn installedProgramRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.ofmt) {
        .elf => "$ORIGIN/../lib",
        .macho => "@loader_path/../lib",
        // COFF finds sibling DLLs automatically; wasm has no dynamic loader.
        else => null,
    };
}

/// Rpath for a wrapper that depends on its sibling core library.
fn installedLibraryRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.ofmt) {
        .elf => "$ORIGIN",
        .macho => "@loader_path",
        else => null,
    };
}

/// Link an installed program to a sibling library with only its required rpath.
fn linkInstalledSibling(
    m: *std.Build.Module,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) void {
    // Windows resolves DLLs through its import library and needs no rpath.
    if (library.linkage != .dynamic or target.result.os.tag == .windows) {
        m.linkLibrary(library);
        return;
    }
    m.addObjectFile(library.getEmittedBin());
    if (installedLibraryRPath(target)) |p| m.addRPathSpecial(p);
}

/// Build the upstream POSIX wrapper as a separate 8-bit artifact.
/// On COFF it imports the core DLL; the same source in the core uses local declarations.
fn addPosixLibrary(b: *std.Build, options: SharedOptions) *std.Build.Step.Compile {
    const posix_mod = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .sanitize_c = options.sanitize_c,
        .link_libc = true,
    });
    Export.from(options.linkage).addPosixLine(posix_mod);
    addSharedIncludes(posix_mod, options);
    posix_mod.addCSourceFiles(.{ .files = &.{"src/pcre2posix.c"}, .flags = &core_c_flags });

    const posix = b.addLibrary(.{
        .name = "pcre2-posix",
        .root_module = posix_mod,
        .linkage = options.linkage,
        .version = if (options.linkage == .dynamic and hasSoname(options.target))
            libtool.posix
        else
            null,
    });
    if (options.linkage == .dynamic and options.target.result.ofmt == .elf) {
        // Use upstream's four-symbol POSIX export list.
        posix.setVersionScript(b.addWriteFiles().add(
            "libpcre2-posix.sym",
            expandVersionScript(b, @embedFile("src/libpcre2-posix.sym.in")),
        ));
    }
    // Both shared libraries install in `lib/`, so the wrapper uses its own directory.
    linkInstalledSibling(posix_mod, options.core, options.target);
    return posix;
}

/// Names the wrapper's four unsuffixed POSIX exports.
const posix_export_names =
    "\n    pcre2_regcomp;\n    pcre2_regerror;\n    pcre2_regexec;\n    pcre2_regfree;";

/// Union upstream's versioned export lists for all widths and add the POSIX symbols.
/// Read the templates verbatim and modify only the generated script.
fn primaryVersionScript(b: *std.Build) std.Build.LazyPath {
    // Extract each upstream version script's global list between these markers.
    const node_head = "PCRE2_10.47 {\n  global:\n";
    const node_tail = "\n  local: *;";

    var head: []const u8 = "";
    var names: []const u8 = "";
    var tail: []const u8 = "";

    for (all_widths, 0..) |width, index| {
        // Coerce differently sized embedded templates to one slice type.
        const template: []const u8 = switch (width) {
            .@"8" => @embedFile("src/libpcre2-8.sym.in"),
            .@"16" => @embedFile("src/libpcre2-16.sym.in"),
            .@"32" => @embedFile("src/libpcre2-32.sym.in"),
        };
        const expanded = expandVersionScript(b, template);
        const head_at = std.mem.indexOf(u8, expanded, node_head) orelse @panic(
            "an upstream .sym.in no longer opens its export list with the node " ++
                "and `global:` this graph parses",
        );
        const after_head = expanded[head_at + node_head.len ..];
        const tail_at = std.mem.indexOf(u8, after_head, node_tail) orelse @panic(
            "an upstream .sym.in no longer ends its `global:` list with the " ++
                "`local: *;` this graph parses",
        );
        if (index == 0) {
            head = b.allocator.dupe(u8, expanded[0 .. head_at + node_head.len]) catch @panic("OOM");
            tail = after_head[tail_at..];
        }
        // Separate adjacent version-script bodies with a newline.
        const glue: []const u8 = if (index == 0) "" else "\n";
        const body = after_head[0..tail_at];
        names = std.mem.concat(b.allocator, u8, &.{ names, glue, body }) catch @panic("OOM");
    }

    return b.addWriteFiles().add(
        "libpcre2-all-widths.sym",
        b.fmt("{s}{s}{s}{s}", .{ head, names, posix_export_names, tail }),
    );
}

/// Replace upstream's extra-symbol placeholder with its local-symbol rule.
fn expandVersionScript(b: *std.Build, template: []const u8) []const u8 {
    return substitute(b, &[_][2][]const u8{
        .{ "@PCRE2_EXTRA_LOCAL_SYMS@", "  local: *;" },
    }, template);
}

const ProgramSpec = struct {
    name: []const u8,
    source: []const u8,
    decl: enum { core, posix },
    posix: bool = false,
};

/// Build upstream's multi-width `pcre2test` plus width-8 programs.
/// The demo, JIT test, fuzz support and table generator are not build products here.
fn addPrograms(b: *std.Build, options: SharedOptions, posix: ?*std.Build.Step.Compile) Programs {
    const exports = Export.from(options.linkage);
    return .{
        // pcre2test includes internal tables from `src/` and chooses its own width macros.
        .pcre2test = addProgram(b, options, posix, exports, .{
            .name = "pcre2test",
            .source = "src/pcre2test.c",
            .decl = .core,
            .posix = true,
        }, .install_tree),
        .pcre2grep = if (options.width == .@"8") addProgram(b, options, posix, exports, .{
            .name = "pcre2grep",
            .source = "src/pcre2grep.c",
            .decl = .core,
        }, .install_tree) else null,
        .posix_test = if (options.width == .@"8") addProgram(b, options, posix, exports, .{
            .name = "pcre2posix_test",
            .source = "src/pcre2posix_test.c",
            .decl = .posix,
            .posix = true,
        }, .install_tree) else null,
    };
}

/// Build a second `pcre2test` only when cache and installed loader paths differ.
fn addCachePcre2test(
    b: *std.Build,
    options: SharedOptions,
    posix: ?*std.Build.Step.Compile,
) *std.Build.Step.Compile {
    return addProgram(b, options, posix, Export.from(options.linkage), .{
        .name = "pcre2test-cache-run",
        .source = "src/pcre2test.c",
        .decl = .core,
        .posix = true,
    }, .build_cache);
}

const Programs = struct {
    pcre2test: *std.Build.Step.Compile,
    pcre2grep: ?*std.Build.Step.Compile,
    posix_test: ?*std.Build.Step.Compile,
};

fn addProgram(
    b: *std.Build,
    options: SharedOptions,
    posix: ?*std.Build.Step.Compile,
    exports: Export,
    spec: ProgramSpec,
    /// Which search path this copy of the program carries. See `Loader`.
    loader: Loader,
) *std.Build.Step.Compile {
    const m = b.createModule(.{
        .target = options.target,
        .optimize = options.optimize,
        .sanitize_c = options.sanitize_c,
        .link_libc = true,
    });
    switch (spec.decl) {
        // Apply core declaration macros to programs that include `pcre2.h`.
        .core => exports.addImportLine(m),
        // Apply the wrapper export macro to POSIX-only programs.
        .posix => exports.addPosixLine(m),
    }
    addSharedIncludes(m, options);
    m.addCSourceFile(.{ .file = b.path(spec.source), .flags = &core_c_flags });
    // Installed programs use the install-tree path; build-only programs use the cache path.
    linkForLoader(m, options.core, options.target, loader);
    // The POSIX wrapper exists only in width-8 builds.
    if (spec.posix) {
        if (posix) |wrapper| linkForLoader(m, wrapper, options.target, loader);
    }
    return b.addExecutable(.{ .name = spec.name, .root_module = m });
}

/// Run upstream's `RunTest` in a generated directory so output stays in the build cache.
/// Pass the selected width and build-cache `pcre2test` path to the driver.
fn addUpstreamSuite(
    b: *std.Build,
    step: *std.Build.Step,
    width: CodeUnitWidth,
    /// Build-cache copy driven by `RunTest`.
    pcre2test: *std.Build.Step.Compile,
) void {
    const run = b.addSystemCommand(&.{ "sh", "-c", "srcdir=\"$3\" && pcre2test=\"$1\" && export srcdir pcre2test && exec \"$0\" \"$2\"" });
    run.setName("RunTest");
    run.addFileArg2(b.path("RunTest"), .{});
    run.addArtifactArg2(pcre2test, .{});
    // The binary carries its build-cache rpath; the run step cannot set it after configure.
    run.addArg(b.fmt("-{t}", .{width}));
    run.addDirectoryArg2(b.path("."), .{ .make_absolute = true });
    run.setCwd(b.addWriteFiles().getDirectory());
    step.dependOn(&run.step);
}

/// Inputs for generated pkg-config and `pcre2-config` metadata.
const MetadataOptions = struct {
    linkage: std.builtin.LinkMode,
    width: CodeUnitWidth,
};

/// Render upstream's pkg-config templates for the selected artifact and linkage.
/// Use `Export` for flags; emit only the selected width's `.pc` and the width-8 POSIX metadata.
fn installPkgConfig(b: *std.Build, options: MetadataOptions) void {
    const exports = Export.from(options.linkage);
    const width = options.width;
    const files = b.addWriteFiles();

    const substitutions = [_][2][]const u8{
        .{ "@prefix@", "${pcfiledir}/../.." },
        .{ "@exec_prefix@", "${prefix}" },
        .{ "@libdir@", "${exec_prefix}/lib" },
        .{ "@includedir@", "${prefix}/include" },
        .{ "@PACKAGE_VERSION@", package_version },
        .{ "@LIB_POSTFIX@", "" },
        .{ "@PTHREAD_CFLAGS@", "" },
        .{ "@PTHREAD_LIBS@", "" },
        .{ "@PCRE2_STATIC_CFLAG@", exports.static_cflags },
        .{ "@PCRE2POSIX_CFLAG@", exports.posix_cflags },
    };

    // Coerce the differently sized embedded templates to one slice type.
    const template: []const u8 = switch (width) {
        .@"8" => @embedFile("libpcre2-8.pc.in"),
        .@"16" => @embedFile("libpcre2-16.pc.in"),
        .@"32" => @embedFile("libpcre2-32.pc.in"),
    };
    const width_name = b.fmt("libpcre2-{t}.pc", .{width});
    const width_pc = files.add(width_name, substitute(b, &substitutions, template));
    b.getInstallStep().dependOn(&b.addInstallLibFile(
        width_pc,
        b.fmt("pkgconfig/{s}", .{width_name}),
    ).step);

    if (width == .@"8") {
        const posix_pc = files.add("libpcre2-posix.pc", substitute(b, &substitutions, @embedFile("libpcre2-posix.pc.in")));
        b.getInstallStep().dependOn(&b.addInstallLibFile(posix_pc, "pkgconfig/libpcre2-posix.pc").step);
    }
}

/// Render upstream's `pcre2-config` template with width and linkage flags.
/// The generated script must be made executable before installation.
fn installConfigScript(b: *std.Build, options: MetadataOptions) void {
    const exports = Export.from(options.linkage);
    const text = substitute(b, &[_][2][]const u8{
        .{ "@prefix@", "$(CDPATH= cd \"$(dirname \"$0\")/..\" && pwd)" },
        .{ "@exec_prefix@", "${prefix}" },
        .{ "@libdir@", "${exec_prefix}/lib" },
        .{ "@includedir@", "${prefix}/include" },
        .{ "@PACKAGE_VERSION@", package_version },
        .{ "@LIB_POSTFIX@", "" },
        .{ "@PCRE2_STATIC_CFLAG@", exports.static_cflags },
        .{ "@PCRE2POSIX_CFLAG@", exports.posix_cflags },
        .{ "@enable_pcre2_8@", if (options.width == .@"8") "yes" else "no" },
        .{ "@enable_pcre2_16@", if (options.width == .@"16") "yes" else "no" },
        .{ "@enable_pcre2_32@", if (options.width == .@"32") "yes" else "no" },
    }, @embedFile("pcre2-config.in"));

    const script = b.addWriteFiles().add("pcre2-config", text);
    const chmod = b.addSystemCommand(&.{"chmod"});
    chmod.setName("make pcre2-config executable");
    chmod.addArg("+x");
    chmod.addFileArg2(script, .{});
    b.getInstallStep().dependOn(&chmod.step);
    b.getInstallStep().dependOn(&b.addInstallBinFile(script, "pcre2-config").step);
}

/// Install upstream manuals and documentation in their declared layout.
fn installDocumentation(b: *std.Build) void {
    b.installDirectory(.{
        .source_dir = b.path("doc"),
        .install_dir = .prefix,
        .install_subdir = man1_root,
        .include_extensions = &.{".1"},
    });
    b.installDirectory(.{
        .source_dir = b.path("doc"),
        .install_dir = .prefix,
        .install_subdir = man3_root,
        .include_extensions = &.{".3"},
    });
    b.installDirectory(.{
        .source_dir = b.path("doc"),
        .install_dir = .prefix,
        .install_subdir = doc_root,
        .include_extensions = &.{".txt"},
    });
    b.installDirectory(.{
        .source_dir = b.path("doc/html"),
        .install_dir = .prefix,
        .install_subdir = doc_html_root,
        .include_extensions = &.{".html"},
    });
    for (upstream_records) |name| b.installFile(name, b.fmt("{s}/{s}", .{ doc_root, name }));
    for (fork_records) |name| b.installFile(name, b.fmt("{s}/{s}", .{ doc_root, name }));
}

/// Install the listed licence and provenance records byte-for-byte.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |name| b.installFile(name, b.fmt("{s}/{s}", .{ licence_root, name }));
}

/// Apply ordered token substitutions, one pair at a time.
fn substitute(b: *std.Build, pairs: []const [2][]const u8, template: []const u8) []const u8 {
    var text = template;
    for (pairs) |pair| {
        text = std.mem.replaceOwned(u8, b.allocator, text, pair[0], pair[1]) catch @panic("OOM");
    }
    return text;
}

fn testModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
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
    optimize: std.lang.Optimize,
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
    optimize: std.lang.Optimize,
    facade: *std.Build.Module,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(fixtures_root),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // Fixtures use facade types, so import the same module instance as the tests.
        .imports = &.{.{ .name = "pcre2", .module = facade }},
    });
}
