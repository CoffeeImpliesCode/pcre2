// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.

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
//!     dependent needs only `dep.module("pcre2")`, and it carries the *build
//!     cache's* loader entry, because a dependent's own executable is built out
//!     of a build cache and `linkLibrary` recorded there where the shared object
//!     really is. Nothing this package installs is built from this module: each
//!     installed program is a C translation unit with a module of its own, linked
//!     with the install tree's `$ORIGIN/../lib` instead. See `Loader`.
//!   * `tests.zig`, `smoke.zig` and the `check` step.
//!   * `-fsys=pcre2-8`, a real `b.systemIntegrationOption` that links an
//!     installed libpcre2-8 and translates the *installed* `<pcre2.h>` rather
//!     than this tree's header: in that mode the generated aggregate includes
//!     it by angle brackets, and the include directory that resolves it is the
//!     one the installed `libpcre2-8.pc` publishes, so the declarations come
//!     from the header that was installed rather than from the 10.49 copy under
//!     `src/`. The `PCRE2_STATIC` declaration macro follows the kind of
//!     installed library the linker is asked for, which `-Dlinkage` names in
//!     that mode.
//!
//!     One limit of that mode is stated here rather than worked around, because
//!     no amount of build-graph work removes it: an installed PCRE2 is a
//!     single-width library. Upstream installs `libpcre2-8`, `libpcre2-16` and
//!     `libpcre2-32` as three separate files, and `OBSERVED` on this host is
//!     that `libpcre2-8.so.0.16.1` resolves `pcre2_compile_8` and
//!     `pcre2_regcomp` and reports `pcre2_compile_16` and `pcre2_compile_32`
//!     missing
//!     (`local://foundation-contract-pcre2-full-header-width-provider-probe-before.log:1-4`),
//!     while the `<pcre2.h>` beside it declares all three widths. A linked
//!     `-fsys=pcre2-8` build is unaffected: the facade only calls the width its
//!     translation was configured for. A `-fsys=pcre2-8 -Druntime=true` build
//!     needs one file that answers for every width `<pcre2.h>` declares, and a
//!     standard single-width external library cannot be that file. A complete
//!     external provider has to export the whole declared surface; this graph
//!     does not narrow the requirement to make a real library loadable.
//!   * `translate.h`, the fork-authored aggregate the bundled translation reads,
//!     through the front end the target's C library needs: Aro's own
//!     preprocessor where Aro can read that library, and the target's own
//!     `zig cc -E -dD` in front of it everywhere else. `aggregateRoute` says
//!     which.
//!   * The rest of upstream's own delivered closure, which an earlier version
//!     of this graph left out: the four upstream programs, `pcre2-config`, the
//!     pkg-config metadata, the manual pages and the documentation, and the
//!     libtool sonames and version scripts that make a shared build a real
//!     `libpcre2-8.so.0` rather than an unversioned one. "What is delivered"
//!     below names every installed file.
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
//!     to fail later. JIT is off, so `SUPPORT_JIT` is 0 in `config.h`. The
//!     translation unit stays in the list because it is part of upstream's
//!     source set and must compile whether or not it defines anything, and the
//!     unit is **not** empty after preprocessing: `pcre2_jit_compile` is
//!     defined outside the `#ifdef SUPPORT_JIT`
//!     (`src/pcre2_jit_compile.c:14303-14432`), and the all-in-one includes of
//!     `pcre2_jit_match_inc.h` and `pcre2_jit_misc_inc.h` are at file scope
//!     (`:14439-14440`, after the guard closes at `:14431`), so the other five
//!     public JIT entry points are defined by their `#ifndef SUPPORT_JIT`
//!     fallbacks too. All six therefore link and all six refuse. JIT being
//!     disabled and the JIT entry points existing are two different facts;
//!     only the first is a consequence of removing the option.
//!   * `src/pcre2_jit_test.c`, upstream's JIT test program. Upstream builds it
//!     only when `SUPPORT_JIT` is on (`Makefile.am`, `noinst_PROGRAMS +=
//!     pcre2_jit_test` under the JIT guard), so with SLJIT absent it is not a
//!     program this build can produce. This is the SLJIT boundary and it is
//!     stated rather than worked around.
//!
//! One artifact, three widths
//! -------------------------
//! Upstream ships the three code-unit widths as three libraries
//! (`libpcre2-8`, `libpcre2-16`, `libpcre2-32`), and the artifact this fork
//! installs has always been one of them. Its public header is a different
//! matter. `src/pcre2.h.generic:1021-1031` runs
//! `PCRE2_TYPES_STRUCTURES_AND_FUNCTIONS` three times, once per
//! `PCRE2_LOCAL_WIDTH`, so `<pcre2.h>` declares `pcre2_compile_8`,
//! `pcre2_compile_16` and `pcre2_compile_32`, their types and the rest of the
//! API for all three widths whatever `PCRE2_CODE_UNIT_WIDTH` is. Only the
//! *generic* spellings - `pcre2_compile`, `pcre2_match`, `pcre2_code` - take
//! the selected width, because `PCRE2_SUFFIX` is redefined to use
//! `PCRE2_CODE_UNIT_WIDTH` at `src/pcre2.h.generic:1056-1072` after the
//! three per-width blocks have already run.
//!
//! A header that declares all three widths and a library that carries one of
//! them do not agree, and the disagreement is not cosmetic: every declaration
//! a consumer of that header can name is an extern it expects to resolve, and
//! `OBSERVED` on this host is that the installed `libpcre2-8.so.0.16.1`
//! resolves `pcre2_compile_8` and `pcre2_regcomp` but reports
//! `pcre2_compile_16` and `pcre2_compile_32` missing
//! (`local://foundation-contract-pcre2-full-header-width-provider-probe-before.log:1-4`).
//!
//! So the primary artifact this graph builds is the union of the three genuine
//! upstream width closures: the same explicit source list, compiled three
//! times with `PCRE2_CODE_UNIT_WIDTH` set to 8, then 16, then 32, with no
//! native byte edited and no source omitted. It stays one artifact with one
//! name, one soname and one version, because one file is what a `load` names
//! and one `-l` name is what a link line can spell.
//!
//! What `-Dcode-unit-width` still chooses is unchanged and is listed under
//! "Options": the primary artifact's name and soname, the pkg-config file
//! installed for it, what `pcre2-config` answers and the generic aliases the
//! typed facade speaks. Upstream's ABI is untouched: a width-8 build still
//! installs `libpcre2-8.so.0.16.1` with `DT_SONAME libpcre2-8.so.0` and the
//! libtool numbers in `configure.ac:16-19`.
//!
//! The three closures can share one artifact because upstream already made
//! them coexist in one program. Every internal name the width libraries share
//! is width-suffixed by the `#define _pcre2_x PCRE2_SUFFIX(_pcre2_x_)` blocks
//! at `src/pcre2_internal.h:2210-2240` and `src/pcre2_compile.h:269-278`,
//! which upstream writes for exactly this reason: the data behind some of
//! those names is identical in every width, "but they must have different
//! names so that multiple libraries can be simultaneously linked to a single
//! application" (`src/pcre2_internal.h:2196-2200`). What is left unshared is
//! the public entry points, and those are the names this graph exports.
//!
//! What this does *not* do: it adds no second library. There is one primary
//! artifact and, at width 8, upstream's own separate `pcre2-posix` artifact -
//! the same set of compiled artifacts as before. `-Dlinkage=static` configures
//! no shared companion, and `-Druntime=true` still builds and installs exactly
//! the same artifact and still links nothing, so a runtime build names its
//! provider at load time and this tree's own artifact is one candidate among
//! others.
//!
//! Everything below is derived from `target.result` or from a build option.
//! Nothing is derived from the machine running the build: the cross-target
//! matrix configures six targets from one host and each one gets its own
//! `config.h`, its own header copy, its own version script, its own
//! translation and its own default linkage.
//!
//! Options, as the build runner spells them:
//!   -Dtarget=<triple>     build for one target; `check` then analyses that one
//!                         target instead of the six-target matrix
//!   -Doptimize=<mode>    Debug, ReleaseSafe, ReleaseFast or ReleaseSmall
//!   -Dcode-unit-width=8|16|32
//!                         PCRE2_CODE_UNIT_WIDTH. The default is 8. It names
//!                         the primary artifact, so the installed library, its
//!                         soname, its pkg-config file and what
//!                         `pcre2-config` answers; and it is the width whose
//!                         generic aliases - `pcre2_compile`, `pcre2_match`,
//!                         `pcre2_code` - this fork's typed facade speaks. It
//!                         does not select the artifact's contents: see
//!                         "One artifact, three widths" above.
//!   -Dlinkage=static|dynamic
//!                         which artifact to build. The default is unchanged:
//!                         dynamic on a GNU libc target, static everywhere else,
//!                         and it is decided for the target being built rather
//!                         than for the host, so each `check` cell resolves it
//!                         from its own target and `wasm32-wasi` is a static
//!                         archive. A named value applies to every cell
//!                         unchanged, and a cell whose OS has no dynamic linker
//!                         is refused by name - it is not built as static
//!                         instead, and it is not left out of the matrix.
//!                         `static` names a static library artifact, not a
//!                         promise that a program linking it is wholly static.
//!   -Dsanitize_c=<mode>   the C sanitizer, as upstream's graph already had it
//!   -fsys=pcre2-8         link an installed libpcre2-8 instead of building the
//!                         bundled core; `-fno-sys=pcre2-8` forces the bundled
//!                         one. This is `b.systemIntegrationOption`, which the
//!                         build runner feeds from `-fsys=`/`-fno-sys=`; it is
//!                         not a `-D` option.
//!
//! Steps: the default install step, `test`, `smoke`, `check`, `upstream-test`,
//! `fmt`, `fmt-check`.
//!
//! What is delivered
//! -----------------
//! For `-Dcode-unit-width=8`, `-Dlinkage=dynamic`, on a GNU libc host:
//!
//!   <prefix>/bin/pcre2test          <prefix>/bin/pcre2grep
//!   <prefix>/bin/pcre2-config       <prefix>/bin/pcre2-smoke
//!   <prefix>/bin/pcre2posix_test
//!   <prefix>/lib/libpcre2-8.so.0.16.1  (+ .so.0 and .so symlinks)
//!   <prefix>/lib/libpcre2-posix.so.3.0.9 (+ .so.3 and .so symlinks)
//!   <prefix>/include/pcre2.h        <prefix>/include/pcre2posix.h
//!   <prefix>/lib/pkgconfig/libpcre2-8.pc
//!   <prefix>/lib/pkgconfig/libpcre2-posix.pc
//!   <prefix>/share/man/man1/*.1     <prefix>/share/man/man3/*.3
//!   <prefix>/share/doc/pcre2/*.txt  <prefix>/share/doc/pcre2/html/*.html
//!   <prefix>/share/doc/pcre2/{AUTHORS.md,ChangeLog,COPYING,LICENCE.md,NEWS,
//!                             README,SECURITY.md,SUPPORT-LIFECYCLE.md}
//!   <prefix>/share/doc/pcre2/{README.md,README.zig.md,README.upstream.md,
//!                             NOTICE.md,UPSTREAM.md,FORK-LICENSE.md,
//!                             FORK-NOTES.md,CHANGELOG.md}
//!   <prefix>/share/licenses/pcre2/{COPYING,LICENCE.md,AUTHORS.md,
//!                             README.upstream.md,NOTICE.md,FORK-LICENSE.md,
//!                             UPSTREAM.md,FORK-NOTES.md,UPSTREAM.sha256}
//!
//! `pcre2test`, `pcre2grep` and `pcre2-config` are upstream's `bin_PROGRAMS`
//! and `bin_SCRIPTS`: the three it installs. `pcre2posix_test` is upstream's
//! `noinst_PROGRAMS` and is installed here on purpose, because an artifact
//! nothing depends on is an artifact this graph never compiles; `build()` and
//! `addPrograms` both say so, along with which of upstream's other programs
//! are not built here and whose decision each of those is.
//!
//! `libpcre2-16.pc` or `libpcre2-32.pc` replaces `libpcre2-8.pc` for the other
//! widths, and the POSIX wrapper, `pcre2grep`, `pcre2posix_test` and
//! `libpcre2-posix.pc` are absent there, because `Makefile.am` builds all
//! three of those only under `WITH_PCRE2_8` and `src/pcre2grep.c:110` and
//! `src/pcre2demo.c:54` hard-code `PCRE2_CODE_UNIT_WIDTH 8` besides.
//!
//! That list is exactly what it was, and staying that way is a decision rather
//! than an oversight. The all-width closure changes what is *compiled*, not
//! what is *installed*, and the reason the wrapper stays behind a width gate
//! is now its own transitive native dependency rather than its own code:
//! `libpcre2-posix.pc` names `libpcre2-8` in its `Requires.private`, and
//! `-lpcre2-8` resolves only when the primary artifact is the one named
//! `libpcre2-8`. A width-16 or width-32 build installs a primary that carries
//! the 8-bit entry points under the name `libpcre2-16`, so the wrapper's
//! metadata there would describe a link no linker could make.
//!
//! A static build replaces each `.so` with `.a`, drops the version script and
//! the soname, and puts no runpath in the programs: there is nothing shared left
//! to resolve. On COFF the shared library is a DLL beside the programs in
//! `bin/`, with no soname, because `hasSoname` says that format has none; on
//! Mach-O it is `libpcre2-8.0.16.1.dylib` with
//! `LC_ID_DYLIB @rpath/libpcre2-8.dylib`.

const std = @import("std");

const manifest = @import("build.zig.zon");

/// The build half of the runtime route, owned by the API role.
///
/// Two functions, and this graph uses no others:
///
///     pub fn createModule(
///         b: *std.Build,
///         translate: *std.Build.Step.TranslateC,
///         target: std.Build.ResolvedTarget,
///         optimize: std.builtin.OptimizeMode,
///     ) *std.Build.Module;
///     pub fn createCoreModule(
///         b: *std.Build,
///         target: std.Build.ResolvedTarget,
///         optimize: std.builtin.OptimizeMode,
///     ) *std.Build.Module;
///
/// `createModule` builds the generated dispatch that replaces
/// `translate_c.createModule()` under `-Druntime`, and it makes the one
/// loader-core module the dispatch re-exports `LoadSource`/`LoadError` from.
/// `createCoreModule` builds that same core for the *linked* branch, where there
/// is no dispatch to carry those types and the facade's `rt` import is where
/// they come from. The two branches must not both call it: a second core
/// instance is a second, nominally distinct `LoadSource`, and `load(source)`
/// would then expect a type the caller did not name.
///
/// `createModule` reads the `TranslateC` step this file has already built, so
/// the dispatch keeps this build's exact translated type and constant namespace;
/// the header is not translated twice.
const graph = @import("runtime/graph.zig");

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

/// What the pkg-config files and `pcre2-config` name as the package version.
///
/// Upstream spells it `major.minor` with no patch component: `configure.ac:10-13`
/// sets `AC_INIT([PCRE2], pcre2_major.pcre2_minor[]pcre2_prerelease, ...)` and
/// `CMakeLists.txt:1191` sets `PACKAGE_VERSION "${PCRE2_MAJOR}.${PCRE2_MINOR}"`.
const package_version = "10.49";

/// `PCRE2_CODE_UNIT_WIDTH`, spelled the way the option is spelled on the
/// command line. Upstream's build.zig already exposed this enum.
pub const CodeUnitWidth = enum {
    @"8",
    @"16",
    @"32",
};

/// The default width, and the one the facade is published against.
///
/// `pcre2.h.generic:1056-1072` makes `PCRE2_SUFFIX(a)` paste
/// `PCRE2_CODE_UNIT_WIDTH` into every generic alias, so `pcre2_compile` is a
/// different function at each width rather than a different configuration of
/// one function. `zig/root.zig` reads that width out of the translation and
/// resolves its surface from it, so `test`, `smoke` and `check` run at every
/// width; nothing in this graph refuses a width any more.
///
/// It is *not* the width the artifact contains any more - that is all three,
/// whatever this says - but it is still what these two places are about, and
/// both are about *which* library rather than about the facade:
///
///   * `-fsys=pcre2-8` binds an installed `libpcre2-8`, so it cannot be paired
///     with a different width at all.
///   * `addTargetCheck` builds the cross-check at this width whatever the
///     `-Dcode-unit-width` the main build chose, because the cross matrix is a
///     check of the published facade and this is the width it is published
///     against by default. The requested width has its own gate in the
///     `widths` CI job.
const facade_width: CodeUnitWidth = .@"8";

/// The libtool interface numbers upstream declares for its shared libraries,
/// as `current:revision:age`.
///
/// `configure.ac:16-19` gives `16:1:16` for the three width libraries and
/// `3:9:0` for the POSIX wrapper. libtool's file name is
/// `SOVERSION.AGE.REVISION` and its soname is `SOVERSION`, where `SOVERSION` is
/// `current - age`: so `libpcre2-8.so.0.16.1` with `DT_SONAME
/// libpcre2-8.so.0`, and `libpcre2-posix.so.3.0.9` with `DT_SONAME
/// libpcre2-posix.so.3`. `CMakeLists.txt` computes the same two numbers from the
/// same m4 definitions.
///
/// These are handed to `b.addLibrary` as `version`, so the numbers that decide
/// an installed file name, a soname and a dependent's `DT_NEEDED` all come from
/// this one declaration rather than from three spellings of it.
const libtool = struct {
    /// `16:1:16` -> soversion 0, file `libpcre2-<width>.so.0.16.1`.
    pub const core: std.SemanticVersion = .{ .major = 0, .minor = 16, .patch = 1 };
    /// `3:9:0` -> soversion 3, file `libpcre2-posix.so.3.0.9`.
    pub const posix: std.SemanticVersion = .{ .major = 3, .minor = 0, .patch = 9 };
};

/// The PCRE2 library sources, in the order upstream's `CMakeLists.txt` lists
/// them in its `PCRE2_SOURCES` block.
///
/// Explicit rather than globbed, so a new upstream translation unit cannot slip
/// into the archive without a decision here, and taken from upstream's own list
/// rather than from a memory of it. This is the full core, and it is one list
/// for all three widths rather than three lists: `addWidthObject` compiles
/// exactly this list once per width with `PCRE2_CODE_UNIT_WIDTH` set to that
/// width, so a source added upstream lands in every closure or in none, and a
/// second copy of the list cannot drift away from this one. For each width it
/// is the interpreter (`pcre2_match.c`), the DFA matcher
/// (`pcre2_dfa_match.c`) and the complete Unicode property machinery
/// (`pcre2_ucd.c`, `pcre2_extuni.c`, `pcre2_script_run.c`, `pcre2_xclass.c`,
/// `pcre2_valid_utf.c`, `pcre2_ord2utf.c`) that `SUPPORT_UNICODE` turns on.
/// `pcre2_tables.c` is the compiled-in UCP table. `pcre2_chartables.c` is
/// added separately because it ships as `src/pcre2_chartables.c.dist` and is
/// copied, not compiled in place; it is copied once per width too, because
/// `PCRE2_CODE_UNIT_WIDTH` renames the tables inside it and so the file a
/// width compiles is genuinely a different translation of the same bytes.
///
/// `src/pcre2_dftables.c` is deliberately *not* here: `CMakeLists.txt` builds it
/// as the generator that writes `pcre2_chartables.c` for a non-default locale
/// (`REBUILD_CHARTABLES`), and `Makefile.am` lists it under `noinst_PROGRAMS`;
/// both then use `pcre2_chartables.c.dist` when that regeneration is not asked
/// for. It is a program, built below, and not a member of the library.
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

/// The three code-unit widths, in the order upstream's `Makefile.am` names its
/// `WITH_PCRE2_8`/`WITH_PCRE2_16`/`WITH_PCRE2_32` blocks.
///
/// Every primary artifact carries all three, whatever `-Dcode-unit-width`
/// selected; see "One artifact, three widths" at the top of this file.
const all_widths = [_]CodeUnitWidth{ .@"8", .@"16", .@"32" };

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
/// the dynamic build (`configure.ac`, `m4/pcre2_visibility.m4`).
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

/// Where the manual pages and the documentation go, which is where upstream's
/// own `doc_MANS`, `dist_man_MANS` and `doc_DATA` put them and where
/// `CMakeLists.txt` installs them (`${CMAKE_INSTALL_MANDIR}/man1`,
/// `/man3`, `${CMAKE_INSTALL_DATAROOTDIR}/doc/pcre2` and `/doc/pcre2/html`).
const man1_root = "share/man/man1";
const man3_root = "share/man/man3";
const doc_root = "share/doc/pcre2";
const doc_html_root = "share/doc/pcre2/html";
const licence_root = "share/licenses/pcre2";

/// Upstream's own text records that its `make install` and its CMake install
/// both copy next to the manual pages and the HTML documentation
/// (`Makefile.am`, `doc_DATA`; `CMakeLists.txt`, the `file(GLOB txts ...)` and
/// `install(FILES ...)` block at the end of the file).
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

/// This fork's own provenance and licence records, installed beside upstream's
/// so that a downstream that receives only the install prefix can still tell
/// which files are upstream's bytes and which are not, and under what grant.
/// `NOTICE.md` is the inventory; `FORK-LICENSE.md` is the grant itself, and
/// `LICENCE.md` is upstream's own and is never re-labelled.
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

/// The licence, notice and provenance records `zig build` installs under
/// `share/licenses/pcre2/`.
///
/// `doc_root` above carries the same material as documentation, and it keeps
/// carrying it: this list is the second spelling, at the place a package's
/// terms are looked for by name, which is where every other package in this
/// workspace puts them. Neither directory was renamed into the other.
///
/// Upstream's own files are `COPYING` (the BSD licence the library itself is
/// under), `LICENCE.md` (upstream's statement of that licence, kept under
/// upstream's own name and never re-labelled), `AUTHORS.md` (upstream's
/// authorship record) and `README.upstream.md` (upstream's README byte for
/// byte, which is the attribution this fork's grant requires to travel). The
/// remaining five are this fork's own: the inventory, the owner-authorised
/// grant, the pin, the integrity digests and what this fork changed.
///
/// `cmake/COPYING-CMAKE-SCRIPTS` is deliberately absent. It is a licence text
/// in this tree, but `cmake/` is not in `build.zig.zon` `.paths`, so no fetch
/// of this package carries it and nothing this graph installs is governed by
/// it; adding it would put a file in the prefix that no recipient of the
/// package was ever sent.
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

/// Which installed library kind a set of declarations binds to, and every
/// declaration macro and `-D` value that follows from it.
///
/// The two macros are not alternatives a build may mix. Upstream reads each of
/// them under `_WIN32` and each names the *opposite* library kind:
///
///   `PCRE2_STATIC`       `src/pcre2.h.generic:56-63` selects
///                        `extern __declspec(dllimport)` for the whole API when
///                        `_WIN32` is defined and `PCRE2_STATIC` is not, and
///                        `src/pcre2_internal.h:154-168` makes the library's own
///                        definitions `dllexport` on the same condition. So the
///                        macro is what tells both sides that the entry points
///                        are in a static archive, where a plain `extern` is the
///                        correct declaration and `dllimport` is a link error.
///   `PCRE2POSIX_SHARED`  `src/pcre2posix.h:129-130` makes the POSIX wrapper's
///                        declarations `extern __declspec(dllimport)` when it is
///                        defined, and `src/pcre2posix.c:70-84` makes its
///                        definitions `dllexport` on the same condition. It says
///                        nothing about the core entry points, which are declared
///                        by `pcre2.h` and follow `PCRE2_STATIC`. The wrapper
///                        includes `pcre2.h` (`src/pcre2posix.c:112`) but not
///                        `pcre2_internal.h`, which is what normally overrides
///                        that declaration for a source inside the library
///                        (`src/pcre2_internal.h:154-160`); upstream's CMake puts
///                        no `PCRE2_STATIC` on the POSIX target either, because
///                        there `pcre2posix.c` is a *separate* DLL that genuinely
///                        imports the core one. Where this fork compiles the same
///                        file into the core artifact instead, the decoration
///                        that says so is `addWidthObjects`' to give, and it does.
///
/// The one thing no macro here decides is `PCRE2_EXP_DECL`, which is not a
/// declaration-kind macro at all: it is upstream's own override for a
/// translation unit that knows better than the header does what its calls bind
/// to, and `pcre2.h` leaves a defined one alone (`src/pcre2.h.generic:51-52`).
///
/// `configure.ac:726-753` states the same rule in prose and derives the two
/// `-D` values the pkg-config files carry from it. That is why `Export` exists:
/// one `linkage` value produces the C compile lines, the translation line, the
/// preprocessing line, the programs' import lines and the `.pc` Cflags, so no
/// two of those can end up describing different libraries.
const Export = struct {
    static_core: bool,
    shared_posix: bool,
    /// `configure.ac`'s `PCRE2_STATIC_CFLAG`.
    static_cflags: []const u8,
    /// `configure.ac`'s `PCRE2POSIX_CFLAG`.
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

    /// The macros on the core library's own compile line.
    ///
    /// `PCRE2_CODE_UNIT_WIDTH` is here rather than only on the translation
    /// line because `PCRE2_SUFFIX` pastes it into every exported name
    /// (`src/pcre2.h.generic:1064`): the value that goes with an archive is the
    /// value the archive was compiled with, not a property of the header.
    fn addCoreLine(self: Export, m: *std.Build.Module, width: CodeUnitWidth) void {
        m.addCMacro("HAVE_CONFIG_H", "");
        m.addCMacro("PCRE2_CODE_UNIT_WIDTH", @tagName(width));
        if (self.static_core) m.addCMacro("PCRE2_STATIC", "1");
    }

    /// The macros on the POSIX wrapper's own compile line.
    ///
    /// `PCRE2_CODE_UNIT_WIDTH` is 8 and is not optional. The wrapper is 8-bit
    /// by construction rather than by preference - `regexec` takes a `char *`
    /// subject and `regmatch_t::rm_so` counts bytes, so a wrapper compiled
    /// against a 16- or 32-bit core would reinterpret every subject byte as a
    /// wide code unit and produce answers that are wrong rather than absent -
    /// and `src/pcre2posix.c:112` includes `pcre2.h`, which hard-errors at
    /// `src/pcre2.h.generic:1057-1059` with `#error PCRE2_CODE_UNIT_WIDTH must
    /// be defined before including pcre2.h.` when the macro is absent. Omitting
    /// it was an observed defect, not a design: 21 compile errors from that one
    /// `#include`
    /// (`local://foundation-contract-pcre2-linked-native-final-observed-cause-correction-build.log:3-119`).
    ///
    /// No `PCRE2_STATIC`, for the reason `Export` gives: the wrapper does not
    /// read it, and its own export macro is `PCRE2POSIX_SHARED`.
    fn addPosixLine(self: Export, m: *std.Build.Module) void {
        m.addCMacro("HAVE_CONFIG_H", "");
        m.addCMacro("PCRE2_CODE_UNIT_WIDTH", "8");
        if (self.shared_posix) m.addCMacro("PCRE2POSIX_SHARED", "1");
    }

    /// The macros on the compile line of anything that *calls* these headers:
    /// `pcre2test`, `pcre2grep`, `pcre2demo`, `pcre2posix_test` and
    /// `pcre2_dftables`.
    ///
    /// Both macros are given, and each header reads only the one that describes
    /// its own library, so a program that includes both headers gets exactly the
    /// pair that matches the pair it links.
    fn addImportLine(self: Export, m: *std.Build.Module) void {
        m.addCMacro("HAVE_CONFIG_H", "");
        if (self.static_core) m.addCMacro("PCRE2_STATIC", "1");
        if (self.shared_posix) m.addCMacro("PCRE2POSIX_SHARED", "1");
    }
};

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
    /// Whether the facade reaches the native entry points through the platform
    /// loader instead of a link line.
    ///
    /// Orthogonal to `linkage`: that one says which artifact this build compiles
    /// and installs, this one says how the facade calls it. The real native
    /// artifact is still built and installed either way, so a caller may name a
    /// provider this tree did not build *and* the one it did.
    runtime_loaded: bool = false,
    /// Where a program built from this graph's facade must find the library it
    /// links. See `Loader`.
    ///
    /// `.build_cache` is the default, and every graph this file builds leaves
    /// it there: the facade is the published module, and a dependent's own
    /// executable is built out of a build cache, which is where `linkLibrary`
    /// recorded that the shared object really is.  Nothing that is *installed*
    /// is built from this facade -- each installed program is a C translation
    /// unit with a module of its own, compiled by `addProgram` or linked by
    /// `linkInstalledSibling` with `.install_tree` -- so the build cache's
    /// directory reaches no installed file.
    loader: Loader = .build_cache,
};

/// The inputs this graph generates rather than reading from the tree.
///
/// They are created per target and handed to the callers that need them, so
/// `pcre2-posix` and every program are compiled against the same `config.h`,
/// the same `pcre2.h` copy and the same export list as the core they link,
/// rather than against a second set that could differ.
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

/// What every program that links the bundled core needs.
const SharedOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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
    // The kind of installed library `-fsys=pcre2-8` binds to. Both the linker
    // search mode and the PCRE2_STATIC declaration macro are derived from this
    // one value, so the declaration decoration and the library it binds to
    // cannot end up describing two different things. It defaults to dynamic
    // rather than to `linkage`, because `linkage` is about artifacts compiled
    // out of this repository's own `src/` and system mode compiles none;
    // `Module.linkSystemLibrary` prefers dynamic when the option is not passed
    // at all, so naming the default changes what a default system build links
    // not one thing.
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

    // Whether the facade calls the native entry points through a link line or
    // through a table an explicit `load` fills. Orthogonal to `-Dlinkage`: the
    // real native artifact is compiled and installed either way.
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

    // A target whose OS has no dynamic linker cannot carry a shared object, and
    // silently delivering a static archive where `-Dlinkage=dynamic` was asked
    // for would hand back an artifact the caller did not request. So a
    // *requested* dynamic linkage on such a target is refused, and the static
    // default is preserved untouched for every target that did not ask.
    //
    // This is the build target's own refusal. `addTargetCheck` makes the same
    // one for a cross-check cell, through the same `linkageSupported` and the
    // same message, because a cell is a target too and inherits nothing from
    // the machine that configured it. `std.Target.DynamicLinker.kind` answers
    // from the OS tag alone, and WASI is `.none` - `wasm32-wasi` is one of this
    // graph's six cross-check targets, and it resolves its own default to
    // static, so a default build never asks for the artifact it cannot carry
    // and a `-Dlinkage=dynamic` build is refused by name instead of attempted.
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
    // An installed library answers only for the machine it was installed on, so
    // a target naming a foreign arch, OS or ABI is refused. `-Dtarget=x86_64-linux-gnu`
    // on that machine names none of those three and is accepted; `isThisMachine`
    // decides that. The refusal and its wording are unchanged.
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

    // The second `pcre2test`, and nothing else.
    //
    // The published `pcre2` module is the build-cache flavour, and that is the
    // entry a dependent's program needs: `linkLibrary` records the directory
    // the shared object was emitted into, and every compilation that imports
    // the module -- a dependent's executable among them, itself built out of a
    // build cache -- gets an `-rpath` for it.  Everything of this build that
    // never leaves the build cache is the same case and takes the same entry:
    // the test binary, the smoke example, and the copy of `pcre2test` that
    // upstream's `RunTest` drives.
    //
    // The installed programs -- `pcre2test`, `pcre2grep`, `pcre2posix_test`,
    // `libpcre2-posix` -- are the exception, and they want the install tree's
    // `$ORIGIN/../lib` and nothing else, because Zig's own entry names a
    // directory that is gone once the file is installed and is something Nix
    // refuses to package at all.  None of them is built from the published
    // module: each is a C translation unit with a module of its own, compiled
    // by `addProgram` or `linkInstalledSibling` with `.install_tree`, so no
    // installed artifact of this build carries the build cache's directory.
    //
    // Under `-Dlinkage=static`, under `-fsys=pcre2-8` and under
    // `-Druntime=true` the two entries are the same file, and
    // `needsBothLoaders` says so: nothing is compiled twice.
    const both_loaders = needsBothLoaders(if (runtime_loaded) null else pcre2.artifact, target);

    // ---- Installed artifacts ---------------------------------------------
    //
    // `zig build` installs the compiled C artifacts, the public headers, the
    // pkg-config metadata, `pcre2-config`, the manual pages and the
    // documentation, and compiles the smoke example. The example is not
    // installed: it is the cheapest proof that the facade and the C agree on
    // types, symbols and link-time dependencies, and a proof is not a
    // deliverable.
    //
    // "Compiles" is the whole of it, and deliberately so. The install step is
    // hung on the smoke executable's **Compile** step below, not on the Run
    // step the named `smoke` step gets, so the default build executes nothing
    // for any target and `install -Dtarget=<foreign>` is a cross-compile rather
    // than an execution attempt. `zig build smoke` is what runs it.

    var pcre2test: ?*std.Build.Step.Compile = null;
    // The POSIX wrapper, kept beside `pcre2test` so that a step which runs one
    // of them can name the shared objects both of them load.
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
        // Installing a header also puts it on the include path of every
        // compilation that links this artifact, so a dependent that wants the C
        // API does not have to reach into this repository's tree.
        artifact.installHeader(shared.generated.header, "pcre2.h");

        // The POSIX wrapper is 8-bit by construction and not by preference:
        // `Export.addPosixLine` and `addPrograms` give the full reason. The
        // gate is on the installed *name*, not on the code - the primary now
        // carries the 8-bit closure either way.
        var posix: ?*std.Build.Step.Compile = null;
        if (width == .@"8") {
            posix = addPosixLibrary(b, shared);
            b.installArtifact(posix.?);
            posix.?.installHeader(b.path("src/pcre2posix.h"), "pcre2posix.h");
            // Upstream's named lazy paths, kept so a consumer written against
            // upstream's build.zig still resolves them.
            b.addNamedLazyPath("pcre2posix.h", b.path("src/pcre2posix.h"));
        }
        pcre2posix = posix;

        const programs = addPrograms(b, shared, posix);
        // Upstream's `bin_PROGRAMS`, the two programs upstream installs.
        b.installArtifact(programs.pcre2test);
        if (programs.pcre2grep) |grep| b.installArtifact(grep);
        // `pcre2posix_test` is upstream's `noinst_PROGRAMS`, and upstream
        // installs none of those. It is installed here anyway, and that is a
        // stated divergence rather than an accident: a `Step.Compile` with no
        // dependent is never built, so a program nothing installs is a program
        // this graph would not compile in its own default gate - which is
        // exactly the kind of omission that reads as "compiles" while nothing
        // has been compiled. Its placement in `bin/` is the only part of this
        // decision that is not upstream's, and it is a placement question
        // rather than a metadata or ABI one. `addPrograms` says which of
        // upstream's other programs are not built, and whose decision each of
        // those is.
        if (programs.posix_test) |pt| b.installArtifact(pt);

        installPkgConfig(b, .{ .linkage = linkage, .width = width });
        installConfigScript(b, .{ .linkage = linkage, .width = width });
        installDocumentation(b);

        // The terms again, at the location a package's terms are looked for
        // rather than at the one they are documented beside. Both paths are
        // real and both are kept.
        installLicenceRecords(b);

        // `RunTest` drives the copy built for the build cache, for the reason
        // `addCachePcre2test` gives; where the two flavours are one file it
        // drives the installed copy.
        pcre2test = if (both_loaders) addCachePcre2test(b, shared, posix) else programs.pcre2test;
    }

    // ---- Tests, smoke, cross-target check --------------------------------

    const test_step = b.step("test", "Run the behavioural tests");
    const smoke_step = b.step("smoke", "Run the deterministic example");
    const check_step = b.step(
        "check",
        "Compile the C core, the facade, the tests and the smoke without running them",
    );

    // The facade resolves to the width this build compiled, so `test`, `smoke`
    // and `check` are wired for every width rather than only for the default.
    // That is a change from an earlier version of this graph, which refused all
    // three outside width 8 because `pcre2.Regex` was then a spelling of the
    // 8-bit API and a 16-bit build would have compiled a facade whose names did
    // not exist. `zig/root.zig` now resolves its surface from the width in the
    // translation, and the parts of `tests.zig` that are genuinely 8-bit - the
    // byte-offset fixtures and the char-table questions - are gated there on
    // `compiled_width`. Nothing here is width-specific, so nothing here refuses.
    {
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
        //
        // What the cells are handed is the *option*, not the value `build`
        // resolved from it: each cell decides its own default from its own
        // target, so a GNU-libc host does not hand a `.dynamic` answer to a
        // WASI cell that cannot carry one, and a command-line value still
        // reaches every cell unchanged.
        if (!target.query.isNative()) {
            addTargetCheck(b, check_step, target.query, optimize, sanitize_c, linkage_option, runtime_loaded);
        } else {
            for (check_targets) |query| {
                addTargetCheck(b, check_step, query, optimize, sanitize_c, linkage_option, runtime_loaded);
            }
        }
    }

    // ---- Upstream's own test suite ---------------------------------------
    //
    // Upstream's `RunTest` is the authority on whether this fork's core still
    // behaves like PCRE2: it drives `pcre2test` through upstream's own
    // `testdata/testinput*` inputs and diffs the result against
    // `testdata/testoutput*`, over every test number from 0 to 29 that the
    // selected width supports. `testdata/foundation-fixtures.zig` replays a
    // slice of the same data through the Zig facade; this runs the rest through
    // upstream's own driver.
    //
    // It is a separate step rather than part of `test` because it is a foreign
    // program that needs `diff` and a writable working directory, and because
    // `tests.zig` is this fork's own gate while this one is upstream's.
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

// Where the runtime-loading seam is
// -----------------------------------
//
// `-Druntime=true` (bool, false by default) selects the *dispatch*, and it is
// orthogonal to `-Dlinkage`: the option says which artifact this build delivers
// and installs, this one says whether the facade calls it through a link line or
// through a table an explicit `load` fills. Under `-Druntime` nothing is linked
// into the module at all, so a caller may name a provider this tree did not
// build - and the artifact is still built and installed, so a caller may equally
// name the one it did.
//
// Two places carry the whole of it, and nothing else in this file knows:
//
//   * the `c` import in `addPcre2`. The runtime branch takes
//     `graph.createModule(b, translate_c, options.target, options.optimize)`,
//     which generates the dispatch from *this* `translate_c` step, so the
//     translated type and constant namespace is the one this build produced
//     rather than a second copy of it. The linked branch keeps
//     `translate_c.createModule()`.
//
//   * the link calls in the same function. Both are skipped for the runtime
//     branch - `linkLibrary(artifact)` in bundled mode and
//     `linkSystemLibrary("pcre2-8")` in `-fsys` mode - and for one reason: a
//     loaded provider must arrive through the platform loader, and a link line
//     that names the same library would let the linker resolve those symbols
//     out of it, so the runtime route would quietly be a linked one. The second
//     one mattered: naming an installed library in a runtime build put a
//     `DT_NEEDED` on every program built that way for a dependency the mode is
//     meant not to take.
//
// One core import in a linked build, and one only: `graph.createCoreModule`
// supplies the `rt` module the facade re-exports `LoadSource` and `LoadError`
// from. The runtime branch must not call it as well - `createModule` already
// makes the one core instance the dispatch re-exports those types from, and a
// second would be a second, nominally distinct `LoadSource`, so a consumer
// would be naming one type while `load` expected the other.
//
// The reusable core itself - `runtime/loader.zig`, `runtime/generate.zig`,
// `runtime/sync.c`, `runtime/sync.h` - is the driver's, and this graph neither
// copies nor edits it.

/// Compiles, but never runs, the public surface for one target.
///
/// Compiling the test binary is what makes this a check of the facade rather
/// than of an unreferenced archive: Zig analyses a function body only when
/// something calls it, `tests.zig` calls every public facade entry point, and so
/// compiling it for a target analyses all of them for that target. The full C
/// source list is compiled by the same graph, for that same target, with that
/// target's `config.h`. Nothing is run, so every result here is compile
/// evidence and not a claim that a cross-built binary executed.
///
/// ## The linkage this cell is built with
///
/// A cell is a target, and it takes its default from itself: `linkage_option`
/// is the `-Dlinkage` value if one was given and nothing else, and each cell
/// resolves its own default through `defaultLinkage` from its own
/// `target.result`. Nothing is inherited from the host build.
///
/// That is the difference between a matrix that compiles and one that fails for
/// the wrong reason. `wasm32-wasi` has no dynamic linker, and when the six
/// cells were handed the host build's `.dynamic` answer that cell tried to link
/// a shared object out of non-PIC objects and libc (`OBSERVED`: 18
/// `recompile with -fPIC` relocation errors,
/// `local://foundation-contract-pcre2-current-cross-target-check.log:19-37`).
/// `x86_64-windows-gnu` inherited it too, and a MinGW shared build is where
/// `pcre2posix.c` inside the core DLL needs the decoration `addWidthObjects`
/// gives it (same receipt, `:3-11`, seven LNK4217 lines). Both were the host's
/// linkage being applied to a target that never asked for it.
///
/// ## A cell that cannot carry what was asked for is refused, by name
///
/// When a `-Dlinkage=dynamic` build reaches a cell whose OS has no dynamic
/// linker, this does not compile a shared artifact that cannot exist, and it
/// does not quietly leave that target out of the matrix either. The cell
/// becomes a failing step of its own whose message names the target and the
/// reason, so a full aggregate dynamic check still compiles and reports the
/// five cells that can carry the artifact and attributes the sixth. The
/// message is `unsupportedSharedMessage`'s, the same one the build target's own
/// refusal in `build` uses.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
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
        // The system library path is meaningless for a foreign target, so the
        // cross matrix always builds from the in-tree sources.
        .use_system = false,
        .register_module = false,
        // The same dispatch route the main build uses, so `check` proves the
        // facade the way this configuration actually builds it. A cross check
        // runs nothing, so this is compile evidence for the runtime route and
        // not a claim that a loaded provider was resolved.
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

    // ---- Generated inputs -------------------------------------------------
    //
    // All of these are per target and are created in the build function, so
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

        // One module per width, one object each, and one library over all three.
        //
        // `core_mod` is the primary artifact's own root module and carries no
        // source of its own; what it contains is the three objects added below.
        // `Module.addObject` is how this Zig version puts a compiled object
        // into a library (`lib/std/Build/Module.zig:465-468`, reaching
        // `linkLibraryOrObject` at `:649-659`), and it is the interface this
        // graph uses rather than a second invented one. The obvious
        // alternative cannot work here: `Step.Compile` deliberately drops a
        // static library from a static library's link line
        // (`lib/std/Build/Step/Compile.zig:1176-1179`), so three intermediate
        // archives inside a `-Dlinkage=static` primary would leave that primary
        // empty.
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
            // Only for a shared build on an object format that has a soname.
            // Zig derives the soname `libpcre2-8.so.<major>` and the installed
            // name `libpcre2-8.so.<major>.<minor>.<patch>` from this and writes
            // `DT_SONAME`, so every dependent's `DT_NEEDED` is that name rather
            // than a path into a build cache. On Mach-O the same value sets
            // `libpcre2-8.0.16.1.dylib` with `LC_ID_DYLIB @rpath/libpcre2-8.dylib`.
            // On COFF and wasm there is no soname to set, and passing one there
            // would ask for a file-naming rule those formats do not have, so it
            // is passed only where it means something. See `hasSoname`.
            .version = if (options.linkage == .dynamic and hasSoname(options.target))
                libtool.core
            else
                null,
        });
        if (options.linkage == .dynamic and options.target.result.ofmt == .elf) {
            // Upstream's own export lists, unioned, for the object formats
            // whose linker takes one. `src/libpcre2-8.sym.in`,
            // `src/libpcre2-16.sym.in` and `src/libpcre2-32.sym.in` name every
            // exported symbol of the three widths, and each ends its version
            // node with `@PCRE2_EXTRA_LOCAL_SYMS@`, which upstream's CMake
            // fills with `  local: *;` when the linker's version-script syntax
            // supports the `*` wildcard (`cmake/PCRE2CheckVscript.cmake`,
            // `m4/pcre2_check_vscript.m4`). LLD takes the same text, so the
            // effect is the same: every symbol the list does not name becomes
            // local, so a static archive linked into somebody else's shared
            // library re-exports nothing.
            //
            // The width does not select one of those three files any more,
            // because the artifact holds all three widths; `primaryVersionScript`
            // reads each of them, keeps every name and keeps upstream's
            // `PCRE2_10.47`/`PCRE2_10.48`/`PCRE2_10.49` node chain verbatim, and
            // adds the four POSIX names the 8-bit closure defines.
            //
            // Mach-O has no version script and upstream does not use one there:
            // `-fvisibility=hidden` plus `PCRE2_EXPORT` is the whole export
            // story on Darwin, and it is already applied per width above. The
            // same is true of COFF, where `PCRE2_STATIC` and the `dllexport`
            // decoration are the export mechanism instead.
            artifact.?.setVersionScript(primaryVersionScript(b));
        }
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
    // All three declaration macros, on the line that reads the header. In bundled
    // mode `PCRE2_CODE_UNIT_WIDTH` and `PCRE2_STATIC` are on the preprocessing
    // line where there is one, because `-dD` keeps the `#define` lines in the
    // file the translator parses and defining them again here would define each
    // of them twice; only the Aro route has no such output, and it is the one
    // that gets them here.
    //
    // `PCRE2POSIX_SHARED` now belongs on this line too, because `translate.h`
    // names `pcre2posix.h` for the 8-bit build and that header reads the macro
    // under `_WIN32` to choose `dllimport` over a plain `extern`
    // (`src/pcre2posix.h:128-136`). It has no reader on a non-Windows target,
    // and on the preprocessing route it is defined where the other two are - so
    // it is defined in both places below, and never in both routes for one
    // target. `Export` is what decides the value in every case, so the
    // translation cannot describe a different wrapper than the one compiled.
    const exports = Export.from(if (options.use_system) options.system_linkage else options.linkage);
    translate_c.defineCMacro("PCRE2_CODE_UNIT_WIDTH", @tagName(options.width));
    if (exports.static_core) translate_c.defineCMacro("PCRE2_STATIC", "1");
    if (exports.shared_posix) translate_c.defineCMacro("PCRE2POSIX_SHARED", "1");
    if (!options.use_system and route == .aro) {
        // The include path, and only on this route. Aro preprocesses
        // `translate.h` for itself here, so this is the route that carries no
        // `-dD` output, and the macros above are the only definition of them it
        // sees. Each value still comes from `Export`, so the translation is
        // bound to the same archive the C core above was compiled into.
        //
        // Two include paths, because `translate.h` now names two headers.
        //
        // The `pcre2.h` copy. `translate.h` includes it with quotes from the
        // repository root, where there is no such file, so this is the path it
        // is found on - the same copy the C core above was compiled against,
        // which is what keeps the translation and the archive one revision.
        //
        // `src/`, for the quoted `"pcre2posix.h"` that follows it. That file is
        // upstream's own and is installed beside `pcre2.h`, so it is read from
        // the tree rather than copied, and no generated copy of it exists or
        // needs to. It is self-contained - `<stdlib.h>` is its only include, so
        // it does not need the generated `pcre2.h` beside it - which is why the
        // two headers can be included in either order without one shadowing the
        // other's guard.
        translate_c.addIncludePath(generated.?.header_dir);
        translate_c.addIncludePath(b.path("src"));
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
    // Where the runtime-loading seam is
    // -----------------------------------
    // `-Druntime=true` substitutes one call for the other. The runtime branch
    // takes the dispatch `runtime/graph.zig` generates from *this* `translate_c`
    // step, so it keeps this build's exact translated type and constant
    // namespace rather than compiling a second copy of the native extern types
    // and casting between two nominally distinct Zig modules. The linked branch
    // keeps the original translation module and the original link, and takes the
    // loader core only for the two public types the facade re-exports either
    // way.

    if (options.use_system and !options.runtime_loaded) {
        // The query goes on the translate step, and before the `c` import below:
        // `linkSystemLibrary` appends to `translate_c.system_libs`
        // (TranslateC.zig:285-299) and `setUpModule` copies that list onto the module
        // `createModule()` builds (:89-100), so a call after the import would leave
        // the `c` module's link line empty. `make` reads the list for the `-I` too.
        //
        // Skipped for the runtime branch, as the rule above states: naming an
        // installed library there put a `DT_NEEDED` on every program built that
        // way for a dependency the mode is meant not to take.
        //
        // `.force`, not `.yes`. Under `.yes` a query that fails is degraded by
        // `TranslateC.zig:250-263` to a bare `-lpcre2-8` with no cflags, and the
        // translation then reads whichever `<pcre2.h>` the compiler's default
        // search path offers - this fork's headers or none at all - against a
        // library the caller never selected. `.force` fails the build instead,
        // which is the only outcome that cannot compile one version's headers
        // against another's library.
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
        // Exactly one core import in a linked build, and it is this one:
        // `LoadSource` and `LoadError` are this SDK's public types and must be
        // the same types a caller names in either configuration. Nothing in
        // that module is instantiated until a configuration that needs the
        // loader compiles it, so a linked build that never calls `load` pays two
        // declarations and no code. This graph builds one facade, so it needs
        // one core: two would be two sets of those two types, and a caller
        // naming one while `load` expects the other would fail to compile
        // rather than fail to load.
        rt_core = graph.createCoreModule(
            b,
            options.target,
            options.optimize,
        );
        module.addImport("rt", rt_core.?);
    }

    if (!options.use_system) {
        // A dependent that compiles its own C against this module needs the
        // same header the library was compiled with, on the compile line and
        // not only on the installation line.
        module.addIncludePath(generated.?.header_dir);
        // A loaded provider must arrive through the platform loader, so the link
        // line names nothing. Linking the archive as well would let the linker
        // resolve the same symbols statically, and the runtime route would
        // quietly be a linked one. The artifact itself is still built and
        // installed above, because delivery and dispatch are separate
        // questions: the whole point of the mode is that a caller may name a
        // provider this tree did not build.
        //
        // Which entry a linked facade carries belongs to `Loader`, and the
        // published one is `.build_cache`: this module is what every program
        // built from this package imports -- the tests, the smoke example, and
        // any downstream consumer of it -- and every module in a compilation's
        // graph contributes its own rpaths, so the entry chosen here is the
        // entry those programs get. A dependent's own executable is built out of
        // a build cache, which is where `linkLibrary` recorded that the shared
        // object really is, so the build cache's directory is the one entry that
        // resolves for it. The programs this package *installs* are not built
        // from this module at all: each is a C translation unit with a module of
        // its own, compiled by `addProgram` or linked by `linkInstalledSibling`
        // with `.install_tree`, so no installed artifact of this build carries
        // the build cache's directory.
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

/// Compiles one width's genuine upstream core closure into one object.
///
/// This is the whole of the per-width half of the primary artifact. It is
/// called once for each width in `all_widths`, it is given the width, and it
/// changes nothing but the width: the same `core_sources`, the same
/// `src/pcre2_chartables.c.dist` copy, the same `core_c_flags`, and the same
/// `config.h` the other two get. There is one source list in this file, so a
/// source added upstream lands in every closure or in none.
///
/// ## Position independence
///
/// Asked for explicitly, because this is a `build-obj` and not a `build-lib`:
/// a relocatable object is not position independent unless something says so,
/// and a `-Dlinkage=dynamic` primary made of objects that were not would fail
/// to link into a shared object at all. `needsPic` decides whether to say it,
/// so the flag appears only on the formats whose shared libraries need it and
/// not on COFF, where a PE image relocates itself, or on wasm, which has no
/// shared library. A static build says nothing and keeps the driver's own
/// default, which is what it had when these sources sat directly on the
/// library.
///
/// ## The POSIX wrapper, in the 8-bit closure only
///
/// The wrapper's four entry points go into the core archive as well as into
/// upstream's separate `pcre2-posix` artifact, so that one file a `load` names
/// answers for both sets. It is 8-bit by its own source and not by this graph's
/// choice: `src/pcre2posix.c:112` includes `pcre2.h` and its functions are
/// declared in `src/pcre2posix.h:104-119`, where a subject is a `char *` and
/// `regmatch_t::rm_so` counts bytes. A 16- or 32-bit wrapper would reinterpret
/// every subject byte as a wide code unit and return answers that are wrong
/// rather than absent, so it is put where upstream puts it: the 8-bit closure.
///
/// Two things make the same four names safe in both artifacts, and both are
/// checked here rather than assumed:
///
///   * `src/pcre2posix.c:119` defines `PCRE2_PCRE2POSIX` and
///     `#define PRIV(name) name` before including `src/pcre2_tables.c` (`:121`),
///     so the wrapper's tables are `utf8_table1` and the core's are
///     `_pcre2_utf8_table1_8`. Eight table objects are defined in both copies and
///     none of the names collides. `PCRE2_PCRE2POSIX` also *removes* four tables
///     from the wrapper's copy (`src/pcre2_tables.c:78-94,145,203,231`), which is
///     why the two copies are not merely identical.
///   * a static link that names both archives takes `pcre2_regcomp` from the
///     first one that satisfies it and does not pull the second member. That is
///     ordinary archive member selection, not a duplicate definition: a linker
///     pulls a member only to resolve a still-undefined symbol. A shared link
///     resolves each library's own copy at its own address.
///
/// `PCRE2POSIX_SHARED` goes on this module for a shared build, so the four
/// names are `dllexport` on Windows and the translation and the provider agree
/// that they are not in a static archive. `src/pcre2posix.c:70-84` reads it and
/// reads it *only* under `_WIN32`, so on ELF it changes nothing and on COFF it
/// is what puts the four names in the DLL's export table. It is the same
/// `Export` value `addPosixLine` gives the separate `pcre2-posix` artifact,
/// which is what keeps the two artifacts from disagreeing about it.
///
/// ## What the wrapper's calls to the core are decorated as *here*
///
/// The two artifacts disagree about this on purpose, and the disagreement is
/// what makes both of them right. Compiled into this archive, every core entry
/// point `pcre2posix.c` calls is defined in the same image, so those calls are
/// plain `extern`; compiled into `pcre2-posix`, the same calls cross into
/// another DLL, so they are `dllimport`. One source, two compilations, two
/// different correct answers - and the one that gets the wrong answer is a
/// build failure rather than a link-time surprise, which is why `pcre2.h`'s
/// import default has to be overridden on exactly one line of exactly one
/// object.
///
/// That override is `PCRE2_EXP_DECL`, on COFF and only on COFF - `one_at_a_time`
/// is true there and there alone is one file per object, so the macro cannot
/// reach a source that *defines* what it calls - and only for a shared build,
/// because a static one already gets `extern` from `PCRE2_STATIC`. `OBSERVED`
/// that it is not a precaution: without it this object imports
/// `pcre2_compile_8`, `pcre2_match_8`, `pcre2_code_free_8` and five more from
/// the DLL that defines them, and LLD reports each one as `locally defined
/// symbol imported`
/// (`local://foundation-contract-pcre2-current-cross-target-check.log:5-11`).
/// ELF and Mach-O need nothing and get nothing, because a call to an exported
/// function of the same image is declared the same way a call to one in another
/// is, and that is what `pcre2.h` already writes there.
fn addWidthObjects(
    b: *std.Build,
    options: Pcre2Options,
    generated: Generated,
    width: CodeUnitWidth,
) []*std.Build.Step.Compile {
    // Zig's `build-obj` accepts several `-c` inputs on ELF, Mach-O and wasm and
    // refuses them on COFF (`coff does not support linking multiple objects into
    // one`), so COFF compiles each source as its own object and every other
    // format keeps the single multi-source object this graph has always used.
    // The translation units, their flags, their macros, their include paths and
    // the generated config header are the same either way.
    const one_at_a_time = switch (options.target.result.os.tag) {
        .windows, .uefi => true,
        else => false,
    };

    // The character tables ship as a `.dist` file upstream copies into place;
    // this is that copy. It is kept separate because its name in the repository
    // is not the name it is compiled under, and because a `.dist` entry in the
    // source list would be a build that breaks the moment upstream renames it.
    // It is copied once per width because `PCRE2_CODE_UNIT_WIDTH` renames the
    // table it defines, so each width genuinely compiles a different
    // translation of the same bytes.
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
            // The decoration for core entry points this object *calls*, and
            // this is the only object in the library that needs one said out
            // loud, because it is the only one that does not get it from
            // `pcre2_internal.h`.
            //
            // This object goes into the core artifact, so every core entry
            // point it calls is defined in the same DLL. `pcre2.h` reads only
            // `_WIN32` and `PCRE2_STATIC` for that decision
            // (`src/pcre2.h.generic:56-63`), a shared core defines neither, and
            // so the whole API arrived here as `extern __declspec(dllimport)`:
            // an import of a symbol this very DLL defines, which LLD reports
            // as `locally defined symbol imported` and Zig's build system turns
            // into a build failure. Seven of them, all from this one file
            // (`OBSERVED`,
            // `local://foundation-contract-pcre2-current-cross-target-check.log:3-11`).
            //
            // `PCRE2_EXP_DECL` is the override upstream provides for exactly
            // this: the header leaves an already-defined one alone
            // (`src/pcre2.h.generic:51-52`), and `src/pcre2_internal.h:154-160`
            // is the same override for the core's own sources. `extern` is the
            // true spelling for a call that never leaves the image, and it is
            // what a static build already gets from `PCRE2_STATIC` - which is
            // why only the shared case says anything here.
            //
            // It is on this object's line and never on a shared core module,
            // because the core's own definitions need this macro to mean
            // `dllexport`
            // (`src/pcre2_internal.h:154-160`) and defining it for them would
            // take the export off every entry point. `one_at_a_time` is true on
            // COFF only, where one file is one object, so this line cannot
            // reach the sources that define what they call.
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

/// Whether this target's shared-library naming has a soname at all.
///
/// ELF has `DT_SONAME` and Mach-O has `LC_ID_DYLIB`; COFF, XCOFF and wasm do
/// not. This is the one place that decides whether `libtool`'s numbers reach
/// the linker, so the installed file name, the soname and a dependent's
/// `DT_NEEDED` agree on whether there is versioning rather than disagreeing
/// pairwise.
fn hasSoname(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.ofmt) {
        .elf, .macho => true,
        // COFF (Windows and UEFI) has no soname at all, wasm has no dynamic
        // loader, and the rest of `std.Target.ObjectFormat` are not object
        // formats a C library is produced for.
        else => false,
    };
}

/// Whether this target's objects have to be compiled position independent.
///
/// ELF and Mach-O shared objects do: the loader maps them at an address the
/// program does not choose, so every absolute reference inside them has to be
/// relative. COFF does not - a PE image relocates itself, which is why a MinGW
/// build never passes `-fPIC` and why asking for it there buys nothing - and
/// wasm has no shared library to place.
///
/// The two answers are adjacent on purpose. `hasSoname` says which formats have
/// a file-naming rule for a shared library and this says which formats need
/// position independence, and both are per-format facts about the same artifact
/// rather than one of them standing in for the other.
fn needsPic(target: std.Build.ResolvedTarget) bool {
    return switch (target.result.ofmt) {
        .elf, .macho => true,
        else => false,
    };
}

/// Whether this target's OS has a dynamic linker at all, and therefore whether
/// it can carry a shared object.
///
/// Windows uses its PE/COFF loader without an interpreter path.
/// Other shared targets need a dynamic linker. WASI has neither.
/// A shared request is refused when no platform loader exists.
fn targetHasDynamicLinker(target: std.Build.ResolvedTarget) bool {
    return target.result.os.tag == .windows or std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// The linkage this graph builds for one target when `-Dlinkage` was not given.
///
/// Dynamic on a GNU libc target and static everywhere else - the rule this graph
/// has always had - and read from the `target.result` of the target *being
/// built*, so a foreign target in `zig build check` gets its own answer instead
/// of the host build's. `-fsys=pcre2-8` is not this function's business: it
/// compiles no artifact, and `system_linkage` decides which installed library it
/// binds to.
fn defaultLinkage(target: std.Build.ResolvedTarget) std.builtin.LinkMode {
    return if (target.result.isGnuLibC()) .dynamic else .static;
}

/// True when `target` names this machine: same instruction set, same operating
/// system, same ABI. An explicit `-Dtarget` naming those three qualifies; a
/// foreign ABI does not.
fn isThisMachine(b: *std.Build, target: std.Build.ResolvedTarget) bool {
    const machine = &b.graph.host.result;
    return target.result.cpu.arch == machine.cpu.arch and
        target.result.os.tag == machine.os.tag and
        target.result.abi == machine.abi;
}

/// Whether this graph can produce `linkage` for this target at all.
///
/// The one refusal there is: a shared object on an OS that has no dynamic
/// linker. It is asked of the build target in `build` and of every cross-check
/// cell in `addTargetCheck`, so no path through the graph can hand back a static
/// archive where a shared one was asked for, and no path can be handed a
/// linkage that was never asked for either.
fn linkageSupported(linkage: std.builtin.LinkMode, target: std.Build.ResolvedTarget) bool {
    return linkage != .dynamic or targetHasDynamicLinker(target);
}

/// The refusal itself, worded once for both callers.
///
/// `request` is the clause naming who asked and nothing else; every fact after
/// the colon is the same in both refusals, so they cannot drift into describing
/// different rules. The result is owned by `b`'s allocator and is deliberately
/// not freed: one caller hands it to `@panic` and the other to `b.addFail`,
/// which copies it.
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
/// It is read as it stands, with no step in front of it and with exactly one
/// include path on the translation line: the `-I` the installed
/// `libpcre2-8.pc` publishes, put there by the query `addPcre2` makes on this
/// step. `translate.h` on the GNU-libc route is read as it stands too, but for
/// the other reason
/// `aggregateRoute` gives. `-fsys=pcre2-8` refuses a foreign `-Dtarget`, so this
/// mode is always the native target's, and no failure of this aggregate has been
/// observed; narrowing its input further would be a change with no observed
///
/// It names `pcre2.h` only, and that is the whole of this mode's POSIX story:
/// `-fsys=pcre2-8` links an installed `libpcre2-8` and this graph compiles no
/// artifact at all in that mode, so there is no `libpcre2-posix` beside it and no
/// `pcre2posix.h` this build put anywhere. Naming the installed wrapper's header
/// here would bind the facade to declarations for a library the linker was never
/// asked for. `zig/posix.zig` then reports `Posix` unavailable from the missing
/// declarations, which is the truth for this mode rather than a gap in it.
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
///   * `mips64-openbsd` and `mips64el-openbsd`.
///     `generic-openbsd/mips64/endian.h:32-41` refuses to define `BYTE_ORDER`
///     unless `__MIPSEL__` or `__MIPSEB__` is defined, and Aro's MIPS predefined
///     macro table defines neither.
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
/// `PCRE2_CODE_UNIT_WIDTH` and `PCRE2_STATIC` are defined here rather than on
/// the translation line on this route, for one reason: `-dD` dumps both with
/// everything else, so defining them again there would define each of them
/// twice. Both values come from `Export`, which is the same source the C compile
/// line reads, so this line and that one cannot disagree about them.
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
/// `bsearch_b`, `heapsort_b`, `mergesort_b`, `psort_b` and `qsort_b` - each
/// of them under `#ifdef __BLOCKS__` in `any-darwin-any/_stdlib.h`, and Aro stops
/// on every one with "expected ')', found '^'": 23 errors on `aarch64-macos`
/// by itself
/// (`local://foundation-cross-test-corrected-pcre2-aarch64-macos.log:8-91`),
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
/// than the target. On every other target Clang leaves blocks off by default, so
/// there it changes nothing.
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
    // Two `-I`s, for the same two reasons as the Aro route: the generated
    // `pcre2.h` copy first, then upstream's own `src/` for the quoted
    // `"pcre2posix.h"`. Order matters only for which copy of a name is found
    // first, and no name is declared by both.
    run.addPrefixedDirectoryArg("-I", header_dir);
    run.addPrefixedDirectoryArg("-I", b.path("src"));
    run.addArg(b.fmt("-DPCRE2_CODE_UNIT_WIDTH={s}", .{@tagName(options.width)}));
    // The same two declaration macros the translation line would have carried,
    // defined here instead, for the one reason `-dD` exists: they survive into
    // the file the translator parses, so `translate.h` sees them and no second
    // definition is added downstream. `PCRE2POSIX_SHARED` is here for the same
    // reason and with the same rule as on the translation line, because
    // `translate.h` now names `pcre2posix.h` for the 8-bit build.
    const exports = Export.from(options.linkage);
    if (exports.static_core) run.addArg("-DPCRE2_STATIC=1");
    if (exports.shared_posix) run.addArg("-DPCRE2POSIX_SHARED=1");
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

            // All three, always, because the primary artifact this graph
            // builds is all three width closures and no other (see "One
            // artifact, three widths" at the top of this file). These are not
            // three copies of one value: each names a closure that exists, and
            // upstream's own rule is that a width is built when its flag is
            // defined (`Makefile.am`, the `WITH_PCRE2_8`/`_16`/`_32` blocks).
            //
            // Two programs read them and both need the truth.
            // `src/pcre2_config.c:119-128` builds the `PCRE2_CONFIG_WIDTH`
            // answer from exactly these three macros, so a narrower value here
            // would make `pcre2_config_N(PCRE2_CONFIG_WIDTH)` deny a width this
            // library really exports. `src/pcre2test.c:368-393` compiles in one
            // test mode per defined width and `:430-442` makes the first
            // defined one the default, which is why the order below is 8, 16,
            // 32 and matches upstream's `Makefile.am`.
            .SUPPORT_PCRE2_8 = true,
            .SUPPORT_PCRE2_16 = true,
            .SUPPORT_PCRE2_32 = true,
            // The full Unicode property machinery: the interpreter and the DFA
            // matcher over UCP rather than the locale tables alone.
            .SUPPORT_UNICODE = true,
            // Off unconditionally in this fork: the JIT's source is a git
            // submodule this package does not ship and must not fetch. The two
            // JIT-only pcre2grep options stay undefined for the same reason and
            // because `src/config-cmake.h.in:20-22` guards
            // `SUPPORT_PCRE2GREP_JIT` on `SUPPORT_JIT` anyway; they are named
            // here so the decision is visible rather than implied by their
            // absence.
            .SUPPORT_JIT = false,
            .SLJIT_PROT_EXECUTABLE_ALLOCATOR = false,
            .SUPPORT_PCRE2GREP_JIT = false,

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

/// Applies the same include paths, generated header and config.h the core got,
/// which is what keeps the wrapper and the library it links in one build
/// configuration.
fn addSharedIncludes(m: *std.Build.Module, options: SharedOptions) void {
    m.addConfigHeader(options.generated.config_header);
    m.addIncludePath(options.generated.header_dir);
    m.addIncludePath(m.owner.path("src"));
}

/// Where a program built against this SDK's shared libraries must find them.
///
/// The two are not two spellings of one answer, and one program cannot carry
/// both: `Module.linkLibrary` records the directory the shared object was
/// emitted into, because `Step.Compile` appends `-rpath <dir>` for every
/// shared library a compilation links
/// (`lib/std/Build/Step/Compile.zig:1290-1297`, the block reached from
/// `.other_step`).  That directory is removed with the build cache.  An
/// installed program that carried it would come out with a `DT_RUNPATH` naming
/// a path that no longer exists, and Nix refuses an installed file that names
/// its own build directory at all.  `Module.addObjectFile` puts the very same
/// file on the link line and records no search path at all, which leaves the
/// relocatable entry below as the only one an installed artifact carries.
const Loader = enum {
    /// A program `zig build install` writes into `bin/`: `pcre2test`,
    /// `pcre2grep`, `pcre2posix_test`, and the `libpcre2-posix` this prefix
    /// installs beside them.  It carries `$ORIGIN/../lib` --
    /// `@loader_path/../lib` on Mach-O -- and nothing else, so it finds the
    /// libraries this prefix installed beside it and still finds them after the
    /// tree is moved.  Each of those is compiled from a module of its own, and
    /// none of them from the published facade, which is why this is the entry
    /// an installed artifact of this build carries.
    install_tree,
    /// Everything that never leaves the build cache, **the published facade
    /// included**: a dependent's executable, the test binary, the smoke example,
    /// and the copy of `pcre2test` that upstream's own `RunTest` drives.  It
    /// keeps the ordinary `linkLibrary` call, so Zig bakes in the directory the
    /// shared objects really are in and the loader looks there -- including for
    /// a shared library's own `DT_NEEDED`, which is why `libpcre2-8.so`'s
    /// directory is wanted and not only the wrapper's.
    ///
    /// This is what the published module carries, and it is the entry that makes
    /// a dependent resolve *this* build's library: a dependent's program is
    /// built out of a build cache, where no `lib/` sits beside it, so the
    /// install tree's `$ORIGIN/../lib` would resolve nothing and the loader
    /// would fall through to whatever the machine has installed under the same
    /// soname.  The entry never reaches a store, because nothing built this way
    /// is ever installed.
    build_cache,
};

/// Put `library` on `module`'s link line, with the search path a program of
/// this `Loader` needs and nothing else.
fn linkForLoader(
    m: *std.Build.Module,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    loader: Loader,
) void {
    // Windows links through the import library and has no rpath, so the
    // ordinary call is the right one there for both loaders and is kept.
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

/// Whether a target's programs have to be compiled twice to have both loaders.
///
/// A static archive, an import-library link on COFF and a facade that links no
/// library at all all produce the same file for both `Loader` values, so a
/// second compilation would be a second copy of a binary that is already
/// right.  A shared library on a platform with a runpath is the one case where
/// they differ, and it is the only case that pays for the second build.
fn needsBothLoaders(
    linked: ?*std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) bool {
    const library = linked orelse return false;
    return library.linkage == .dynamic and target.result.os.tag != .windows;
}

/// Lets an installed program find the libraries installed beside it.
///
/// `bin/pcre2test` and `lib/libpcre2-8.so.0` are siblings under one prefix, so
/// the program needs `<prefix>/bin/$ORIGIN/../lib`, which is exactly the
/// directory `b.installArtifact` put `libpcre2-8.so.0` and
/// `libpcre2-posix.so.3` in. On Mach-O the same relationship is spelled
/// `@loader_path`. On COFF a program finds a DLL beside itself through the
/// loader's own search order, so there is nothing to add, and on wasm there is
/// no dynamic loader to name.
fn installedProgramRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.ofmt) {
        .elf => "$ORIGIN/../lib",
        .macho => "@loader_path/../lib",
        // COFF finds a DLL beside the program through the loader's own search
        // order, and wasm has no dynamic loader to name.
        else => null,
    };
}

/// The entry an installed shared library needs, which is its own directory.
///
/// `libpcre2-posix.so` records a dependency on `libpcre2-8.so`, and this
/// prefix installs both into `lib/`, so `$ORIGIN` is the whole of what it has
/// to name. A library with no non-standard dependency needs none at all, which
/// is the case for `libpcre2-8.so` itself: this graph never adds an entry to
/// the core module.
fn installedLibraryRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.ofmt) {
        .elf => "$ORIGIN",
        .macho => "@loader_path",
        else => null,
    };
}

/// Put a shared library this build produced on `m`'s link line for an artifact
/// this package installs, with the search path that artifact's installed copy
/// needs and nothing else.
///
/// The one such link is `libpcre2-posix`'s, whose dependency sits in the same
/// `lib/` it does, so the entry is its own directory.  See
/// `installedProgramRPath` for why the ordinary `Module.linkLibrary` call is
/// not made here.
fn linkInstalledSibling(
    m: *std.Build.Module,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) void {
    // Windows links through the import library and has no rpath, so the
    // ordinary call is the right one there and is kept.
    if (library.linkage != .dynamic or target.result.os.tag == .windows) {
        m.linkLibrary(library);
        return;
    }
    m.addObjectFile(library.getEmittedBin());
    if (installedLibraryRPath(target)) |p| m.addRPathSpecial(p);
}

/// `src/pcre2posix.c`: upstream's POSIX `regcomp`/`regexec` emulation, built as
/// its own artifact against the core this graph compiled. It is not part of the
/// `pcre2` facade module and is not translated; a caller that wants it takes
/// `dep.artifact("pcre2-posix")` and the installed `pcre2posix.h`.
///
/// It gets `PCRE2_CODE_UNIT_WIDTH=8` and, for a shared build,
/// `PCRE2POSIX_SHARED`. The width is required and not a preference:
/// `src/pcre2posix.c:112` includes `pcre2.h`, which hard-errors without it.
/// No `PCRE2_STATIC`, and the reason is the artifact this one is: on COFF the
/// core entry points it calls are defined in *another* DLL, so `pcre2.h`'s
/// `dllimport` is exactly right here and `PCRE2_STATIC` would be the false
/// description that breaks it. Upstream's CMake makes the same choice for the
/// same reason (`CMakeLists.txt:1011-1013` defines only `PCRE2POSIX_SHARED` on
/// the POSIX target and links it to `pcre2-8-shared`). The very same source
/// compiled *into* the core artifact is the opposite case and is given the
/// opposite decoration there; `addWidthObjects` says which is which.
///
/// Both are explained at `Export`.
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
        // `src/libpcre2-posix.sym.in` names the four entry points
        // `src/pcre2posix.c` defines (`pcre2_regerror`, `pcre2_regfree`,
        // `pcre2_regcomp`, `pcre2_regexec`), which is the whole of the wrapper's
        // exported surface: `src/pcre2posix.h:159-168` declares exactly those
        // four and defines the POSIX spellings as macros for three of them.
        posix.setVersionScript(b.addWriteFiles().add(
            "libpcre2-posix.sym",
            expandVersionScript(b, @embedFile("src/libpcre2-posix.sym.in")),
        ));
    }
    // `libpcre2-posix.so` and `libpcre2-8.so` are siblings in the `lib/` of
    // one prefix, so the wrapper's own entry is the directory it is installed
    // into. See `installedLibraryRPath`.
    linkInstalledSibling(posix_mod, options.core, options.target);
    return posix;
}

/// The four POSIX entry points, in the spelling the rest of the list uses.
///
/// These are the names `src/pcre2posix.c` defines and `src/pcre2posix.h:159-168`
/// declares. They carry no width suffix, because `PCRE2_SUFFIX` does not reach
/// them: the wrapper is 8-bit by construction, so there is one spelling of each
/// and the header that declares them is the 8-bit one.
const posix_export_names =
    "\n    pcre2_regcomp;\n    pcre2_regerror;\n    pcre2_regexec;\n    pcre2_regfree;";

/// The primary artifact's export list: upstream's three width lists, unioned,
/// with the four POSIX names added.
///
/// One artifact holds all three width closures, so it has to export all three
/// widths' entry points; a list that named one width's 79 and not the other
/// two would hide 158 of them, leaving them in the file and absent from every
/// dynamic symbol table. That is what the `  local: *;` wildcard below does to
/// anything the list does not name, and it is why the four `pcre2_reg*` names -
/// which the 8-bit closure defines and which `src/pcre2posix.c` puts in the same
/// archive - are written into the `global:` list here as well.
///
/// Upstream's three files are read, not retyped: `src/libpcre2-8.sym.in`,
/// `src/libpcre2-16.sym.in` and `src/libpcre2-32.sym.in` are the same list with
/// the suffix changed, and each is embedded whole. The version node chain is
/// taken from them verbatim - `PCRE2_10.47`, then `PCRE2_10.48 { } PCRE2_10.47`,
/// then `PCRE2_10.49 { } PCRE2_10.48` - so a consumer that checks
/// `pcre2_compile_8@@PCRE2_10.49` sees the same answer here as it would from
/// upstream's own `libpcre2-8.so`.
///
/// The four POSIX names go into the existing `PCRE2_10.47` node rather than a
/// node of their own because that is the node `src/libpcre2-posix.sym.in` puts
/// all four in. Matching it is what keeps `libpcre2-8.so` and
/// `libpcre2-posix.so` answering at the same version for the same four
/// functions.
///
/// This edits a generated file, not upstream's: each `.sym.in` is read through
/// `@embedFile` and the union happens here, so no upstream byte changes.
fn primaryVersionScript(b: *std.Build) std.Build.LazyPath {
    // Every one of the three opens its `global:` list with the first marker and
    // closes it with the second, and this graph only reads and rewrites them
    // after `expandVersionScript` has turned `@PCRE2_EXTRA_LOCAL_SYMS@` into
    // the `  local: *;` the second marker spells.
    const node_head = "PCRE2_10.47 {\n  global:\n";
    const node_tail = "\n  local: *;";

    var head: []const u8 = "";
    var names: []const u8 = "";
    var tail: []const u8 = "";

    for (all_widths, 0..) |width, index| {
        // The named result type is what lets one switch carry three
        // `@embedFile` results: each is a sentinel-terminated array of a
        // different length, and `[]const u8` coerces all three to one slice.
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
        // Each body ends on `;` and the next begins with the indent, so the
        // newline between them is this graph's to add.
        const glue: []const u8 = if (index == 0) "" else "\n";
        const body = after_head[0..tail_at];
        names = std.mem.concat(b.allocator, u8, &.{ names, glue, body }) catch @panic("OOM");
    }

    return b.addWriteFiles().add(
        "libpcre2-all-widths.sym",
        b.fmt("{s}{s}{s}{s}", .{ head, names, posix_export_names, tail }),
    );
}

/// The one substitution upstream's own build makes to its `.sym.in` files:
/// `CMakeLists.txt` and `Makefile.am` both fill the placeholder with
/// `  local: *;`, and LLD takes that text unchanged.
fn expandVersionScript(b: *std.Build, template: []const u8) []const u8 {
    return substitute(b, &[_][2][]const u8{
        .{ "@PCRE2_EXTRA_LOCAL_SYMS@", "  local: *;" },
    }, template);
}

/// One upstream program.
const ProgramSpec = struct {
    /// The name upstream installs or builds it under.
    name: []const u8,
    /// The single translation unit, which is how upstream's own build lists each
    /// of these programs.
    source: []const u8,
    /// Which of the two public headers the program reads, and therefore which
    /// declaration macro it needs.
    decl: enum { core, posix },
    /// Whether the program also links the POSIX wrapper.
    posix: bool = false,
};

/// Builds upstream's own programs against this graph's core.
///
/// Three, and each exists here for the reason upstream's `Makefile.am` gives.
///
///   `pcre2test`       `bin_PROGRAMS`, unconditional. It links the width
///                     library this build produced and, in the 8-bit build
///                     only, the POSIX wrapper - `Makefile.am` adds
///                     `libpcre2-8.la libpcre2-posix.la` under `WITH_PCRE2_8`,
///                     `libpcre2-16.la` under `WITH_PCRE2_16` and
///                     `libpcre2-32.la` under `WITH_PCRE2_32`. It compiles in
///                     one test mode per width `config.h` enables
///                     (`src/pcre2test.c:368-393`), and that is now all three,
///                     so `pcre2test -16` and `pcre2test -32` answer from this
///                     build's own library rather than being refused by a mode
///                     that was not compiled in.
///   `pcre2grep`       `bin_PROGRAMS`, inside `if WITH_PCRE2_8`
///                     (`Makefile.am:725-737`), and it needs the guard because
///                     `src/pcre2grep.c:110` hard-codes
///                     `#define PCRE2_CODE_UNIT_WIDTH 8`. So it is an 8-bit
///                     program by upstream's own arrangement, not by a
///                     preference of this graph.
///   `pcre2posix_test` `noinst_PROGRAMS`, inside `if WITH_PCRE2_8`
///                     (`Makefile.am:687-693`). It includes only
///                     `<pcre2posix.h>` (`:60`), so it exists to prove the
///                     POSIX header builds for a client that does not include
///                     `pcre2.h`, and upstream gives it `@PCRE2POSIX_CFLAG@`
///                     and no `-DPCRE2_STATIC`.
///
/// ## Why the last two are still behind the selected width
///
/// The primary artifact now carries the 8-bit closure whatever
/// `-Dcode-unit-width` said, so upstream's `WITH_PCRE2_8` condition holds
/// always and neither program is missing any code it would otherwise have.
/// What still keeps them behind the gate is the installed *name*. They belong
/// to the `libpcre2-8` deliverable, and `libpcre2-posix.pc` names
/// `libpcre2-8` in its `Requires.private`, so a build whose primary installs
/// as `libpcre2-16` or `libpcre2-32` has no `-l` name for that metadata to
/// name; installing it there would be metadata for a link no linker could
/// make. A width-8 build - this fork's default - delivers exactly the set it
/// always did.
///
/// ## What is not built, and whose decision that is
///
/// Each of these is an upstream decision with its own place in
/// `Makefile.am`, not an omission here:
///
///   `src/pcre2demo.c`        `Makefile.am:905-908`: "PCRE2 demonstration
///                            program. Not built automatically. The point is
///                            that the users should build it themselves. So just
///                            distribute the source." The file is in `.paths`,
///                            so a fetched package carries it.
///   `src/pcre2_dftables.c`   `Makefile.am:393-404`: built only under
///                            `WITH_REBUILD_CHARTABLES`. This graph compiles
///                            the distributed `pcre2_chartables.c.dist`, which
///                            is what upstream's `else` arm does and what
///                            `CMakeLists.txt` does without
///                            `REBUILD_CHARTABLES`, so the generator has
///                            nothing to generate.
///   `src/pcre2_jit_test.c`   `if WITH_JIT`. JIT is off, and SLJIT is the empty
///                            `deps/sljit` submodule.
///   `src/pcre2_fuzzsupport.c` `if WITH_FUZZ_SUPPORT` (`Makefile.am:632-670`),
///                            which needs a libFuzzer runtime this build does
///                            not have and which no installed artifact uses.
///   `maint/ucptest.c`        upstream's maintenance UCD tester, in no build
///                            rule of either upstream build system.
fn addPrograms(b: *std.Build, options: SharedOptions, posix: ?*std.Build.Step.Compile) Programs {
    const exports = Export.from(options.linkage);
    return .{
        // `src/pcre2test.c:295-325` pulls `pcre2_tables.c` and `pcre2_ucd.c`
        // into the program under `PRIV()` renaming and re-includes
        // `pcre2_intmodedep.h` and `pcre2_printint_inc.h` once per width the
        // generated `config.h` enables, so it needs `src/` on its include path
        // as well as the generated `pcre2.h`. It defines
        // `PCRE2_CODE_UNIT_WIDTH` as 0 for itself (`:313`), which is why it
        // gets no `-D` for the width from this graph.
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

/// `pcre2test` again, for the cache.
///
/// `bin/pcre2test` is installed *and* driven by upstream's own `RunTest`, and
/// one binary cannot carry both search paths, so the program is compiled twice
/// from the one `addProgram` above.  `needsBothLoaders` is what says the two
/// really differ; where they do not, this is never called and the installed
/// copy is the one `RunTest` drives.
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
        // A program that reads `pcre2.h`. It gets both macros; `pcre2.h` reads
        // `PCRE2_STATIC` and the other one has no reader in it, which is a
        // define with no effect rather than a wrong one.
        .core => exports.addImportLine(m),
        // A program that reads only `pcre2posix.h`. It gets the macro that
        // header actually reads and nothing else, which is upstream's own
        // `pcre2posix_test_CFLAGS = $(AM_CFLAGS) @PCRE2POSIX_CFLAG@`.
        .posix => exports.addPosixLine(m),
    }
    addSharedIncludes(m, options);
    m.addCSourceFile(.{ .file = b.path(spec.source), .flags = &core_c_flags });
    // A program that is installed wants the install tree's search path; a
    // program that only runs out of the build cache wants the build cache's.
    // `linkForLoader` is the whole of that difference and the only thing that
    // separates two compilations of one source file.
    linkForLoader(m, options.core, options.target, loader);
    // `posix` is null in a 16- or 32-bit build, where the wrapper does not
    // exist at all, and `pcre2test` is then the only program here that asked
    // for one - which is upstream's own arrangement for those widths.
    if (spec.posix) {
        if (posix) |wrapper| linkForLoader(m, wrapper, options.target, loader);
    }
    return b.addExecutable(.{ .name = spec.name, .root_module = m });
}

/// Runs upstream's `RunTest` against this build's `pcre2test`.
///
/// `RunTest` takes the test-data directory and the program to drive from the
/// environment (`RunTest:141-150` for `srcdir`, `RunTest:229` for
/// `pcre2test`), and it writes a `testoutput*` directory per test into its
/// current working directory. Both are handled here:
///
///   * the working directory is a generated one, so the diffs it leaves behind
///     land in the build cache and never in this repository's `testdata/`;
///   * `srcdir` is an environment value, so it has to be spelled at configure
///     time, and `pcre2test`'s path is resolved in the make step like every
///     other path. The `sh -c` wrapper is what bridges the two: `sh -c script
///     arg0 arg1 arg2` puts `arg0` in `$0`, so one line exports the program path
///     and execs `RunTest` with the width selector.
///
/// `-8`, `-16` and `-32` are `RunTest`'s own width selectors (`RunTest:9-12`),
/// and it skips the test numbers the selected width has no data for, so this
/// runs upstream's whole suite for this width and no other.
fn addUpstreamSuite(
    b: *std.Build,
    step: *std.Build.Step,
    width: CodeUnitWidth,
    /// The copy of `pcre2test` `RunTest` drives: the one built for the cache.
    pcre2test: *std.Build.Step.Compile,
) void {
    const run = b.addSystemCommand(&.{ "sh", "-c", "pcre2test=\"$1\" && export pcre2test && exec \"$0\" \"$2\"" });
    run.setName("RunTest");
    run.addFileArg(b.path("RunTest"));
    run.addArtifactArg(pcre2test);
    // No loader search path is set for it here.  The program is built with the
    // build cache's own entry baked into it, so its loader finds the shared
    // objects where they were emitted; a run step has no way to say that at
    // configure time, because the directory only exists once the cache does.
    run.addArg(b.fmt("-{t}", .{width}));
    run.setEnvironmentVariable("srcdir", b.path(".").getPath(b));
    run.setCwd(b.addWriteFiles().getDirectory());
    step.dependOn(&run.step);
}

/// The `.pc` and `pcre2-config` substitutions. One `linkage` value decides all
/// of them, through `Export`.
const MetadataOptions = struct {
    linkage: std.builtin.LinkMode,
    width: CodeUnitWidth,
};

/// Installs upstream's pkg-config files for the width this build produced.
///
/// Generated from upstream's own `libpcre2-<width>.pc.in` and
/// `libpcre2-posix.pc.in` rather than hand-written, so the field names, the
/// `-l` spellings, the `License:` line and the `Requires.private` relation are
/// upstream's and stay upstream's when upstream changes them.
///
/// Three substitutions are this graph's own decisions and each is stated:
///
///   `prefix` etc.  `${pcfiledir}/../..`, so a `.pc` locates its own prefix and
///                  the same file is correct after the prefix is moved or
///                  bind-mounted. `CMakeLists.txt` bakes `CMAKE_INSTALL_PREFIX`
///                  in instead; relocation is a property this package promises,
///                  and `${pcfiledir}` is the standard way to keep it.
///   `@PTHREAD_*@`  empty. `src/*.c` and `src/*.h` contain no `pthread` include
///                  and no thread symbol - `pcre2_maketables.c` is the only
///                  place upstream ever considered threads - so a build from
///                  this tree has nothing private to link. Upstream's own
///                  `configure` leaves these empty on a platform where
///                  `AX_PTHREAD` finds no need either. The line is left in the
///                  file exactly as the template spells it, because that is what
///                  upstream's `make install` produces there too.
///   `@PCRE2_STATIC_CFLAG@`
///                  `-DPCRE2_STATIC` for a static build and empty for a shared
///                  one, which is `configure.ac:728-739` and `CMakeLists.txt`
///                  `PCRE2_STATIC_CFLAG` restated. The same rule decides
///                  `@PCRE2POSIX_CFLAG@` in the wrapper's `.pc`
///                  (`configure.ac:741-753`), and both are applied to the C
///                  compile lines, the translation line and the preprocessing
///                  line by the same `Export` value, so a consumer's
///                  declarations and this build's definitions cannot disagree.
///
/// Only the selected width gets a `.pc`, because a `.pc` is a promise about an
/// installed *name*: `libpcre2-16.pc` says `-lpcre2-16`, and this build installs
/// one file under the name `-Dcode-unit-width` chose. The other two widths are
/// inside that file and are named by its symbols, not by a `-l` name, so a
/// `.pc` for either of them would name a library no linker can find.
///
/// The wrapper's `.pc` names the width library it needs in its own
/// `Requires.private`, which `libpcre2-posix.pc.in` already spells as
/// `libpcre2-8`: the wrapper is 8-bit by construction, so that is the
/// width-specific name, and it is emitted only in the build where that name is
/// the installed one.
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

    // `@embedFile` gives each of these a different sentinel-terminated array
    // type, so the switch's result type is named: every arm is then coerced to
    // one slice instead of the switch having to reconcile three of them.
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

/// Installs `pcre2-config`, upstream's own query script.
///
/// Generated from upstream's `pcre2-config.in`, so the option set, the usage
/// text and the per-width `--libs8`/`--libs16`/`--libs32` behaviour are
/// upstream's. The substitutions are the ones the template already has names for:
///
///   `@prefix@`     the resolved `--prefix` this build installs into. A shell
///                  script cannot use `${pcfiledir}` the way a `.pc` file can -
///                  that is a pkg-config variable, not a shell one - so this is
///                  upstream's own arrangement: its `configure` bakes the
///                  configure-time prefix in too. `b.install_path` is read after
///                  the build runner has resolved `--prefix`, so it is the
///                  prefix the artifacts actually land in.
///   `@enable_pcre2_8@`
///   `@enable_pcre2_16@`
///   `@enable_pcre2_32@`
///                  `yes` for the width whose library this install prefix
///                  holds and `no` for the other two, which is how `configure`
///                  reports a build with only some widths enabled and what
///                  this prefix can actually answer. The script then omits
///                  `--libs16` from its usage and answers `--libs16` with that
///                  usage and a non-zero exit, rather than naming a library
///                  this install prefix does not hold. Answering `yes` for all
///                  three would be true of what was *compiled* and false of
///                  what `--libs32` can return.
///   `@PCRE2_STATIC_CFLAG@`,
///   `@PCRE2POSIX_CFLAG@`
///                  the same two values the `.pc` files carry, from the same
///                  `Export`.
///
/// The file arrives with mode 0644 from `addWriteFiles` and must arrive
/// executable, so a `chmod +x` step is hung in front of the install of this one
/// file; `Step.installFile` copies the source's permissions, which is why the
/// order is a graph edge rather than a note.
fn installConfigScript(b: *std.Build, options: MetadataOptions) void {
    const exports = Export.from(options.linkage);
    const text = substitute(b, &[_][2][]const u8{
        .{ "@prefix@", b.install_path },
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
    chmod.addFileArg(script);
    b.getInstallStep().dependOn(&chmod.step);
    b.getInstallStep().dependOn(&b.addInstallBinFile(script, "pcre2-config").step);
}

/// Installs the manual pages and the documentation.
///
/// The layout is upstream's: `man1` for the two page-one manuals upstream
/// installs, `man3` for the library's own pages, `share/doc/pcre2` for the
/// plain-text documentation and both upstream's and this fork's records, and
/// `share/doc/pcre2/html` for the HTML manual. `CMakeLists.txt` installs
/// `doc/*.txt`, `doc/html/*.html`, `doc/html/*.txt`, `AUTHORS.md`, `COPYING`,
/// `ChangeLog`, `LICENCE.md`, `NEWS`, `README`, `SECURITY.md` and
/// `SUPPORT-LIFECYCLE.md` to exactly those places, and `Makefile.am` does the
/// same through `doc_DATA` and `dist_man_MANS`.
///
/// The `.txt` pass walks `doc/` recursively, which puts `doc/html/*.txt` in
/// `share/doc/pcre2/html/` beside the `.html` files - upstream's own result,
/// since its `file(GLOB html ...)` takes both suffixes.
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

/// Installs the licence, notice and provenance records under
/// `share/licenses/pcre2/`.
///
/// The same files `installDocumentation` puts under `doc_root`, at the place a
/// package's terms are looked for by name rather than among the manual pages.
/// Both directories keep every path they had; this adds the second spelling.
///
/// These are copies of files already in this repository, byte for byte;
/// nothing is rewritten, merged or truncated on the way out. `b.installFile`
/// takes a repository path and attaches its own step to the install step
/// (`lib/std/Build.zig:1675-1677`), so this needs no separate `dependOn` —
/// which is why the list above, and not a directory copy, is what makes the
/// install complete: a missing entry is a build failure naming the file.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |name| b.installFile(name, b.fmt("{s}/{s}", .{ licence_root, name }));
}

/// Replaces each `@TOKEN@` in an upstream template.
///
/// One pass per pair, in the order given, so a caller controls the order in
/// case one token could ever be a substring of another; no two tokens in the
/// templates this is called with are.
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
