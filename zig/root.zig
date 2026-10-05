// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//
//! Public Zig surface of the PCRE2 fork.
//!
//! Scope: the PCRE2 library compiled from this repository's own `src/`, with
//! Unicode support and with JIT left off, at whichever code-unit width
//! `-Dcode-unit-width` selected. Every declaration below carries a pointer, a
//! count or a status code across the C boundary; no PCRE2 algorithm is
//! reimplemented here, and no constant is taken from prose. Each one names the
//! line of `src/pcre2.h.generic`, `src/pcre2_match.c` or `src/pcre2_context.c`
//! that it was read out of, so a reader can check the binding against the source
//! instead of against this file.
//!
//! **Routes in.** A dependent adds this package to `build.zig.zon` and takes
//! `dep.module("pcre2")`, which arrives with the compiled archive and the
//! include path for the generated `pcre2.h` on it, so the module alone is
//! enough and nothing else has to be linked. In a shared build it also arrives
//! carrying the **build cache's** loader entry -- the directory the shared
//! object was emitted into, which `Module.linkLibrary` records and every
//! compilation importing the module then gets an `-rpath` for -- because a
//! dependent's own executable is built out of a build cache, and that is where
//! this build's `libpcre2-8.so.0` really is. Nothing installed is built from
//! this module: every program this package installs is a C translation unit
//! linked with the install tree's `$ORIGIN/../lib` instead. See `Loader` in
//! `build.zig`. `@import("pcre2")` then reaches three things and nothing else:
//!   * `pub const c`, the complete translated `pcre2.h`, including the 16-bit
//!     and 32-bit declarations, `pcre2_dfa_match`, `pcre2_substitute` and the
//!     serialization calls that this facade deliberately does not wrap. Nothing
//!     is filtered out; reach for it when you need an entry point that is not
//!     below.
//!   * the typed surface of the compiled width: an owned compiled pattern, owned
//!     match-data, compile, match, convert and general contexts, a JIT stack,
//!     and results whose captures borrow the caller's subject instead of copying
//!     it.
//!   * `pub const Posix`, upstream's `regcomp`/`regexec` emulation, which is a
//!     **second** library and is offered only where that library exists.
//!
//! ## Widths
//!
//! `pcre2.h` publishes all three widths into one header
//! (`src/pcre2.h.generic:1021-1031`) and `PCRE2_SUFFIX` (`:1064`) pastes the
//! width onto every exported name, so one translation describes all three.
//! `-Dcode-unit-width` selects which of them this build is *about*: the generic
//! aliases, the primary artifact's name, and the typed facade published under
//! `pcre2.Surface`. The artifact itself is built from all three widths'
//! unmodified upstream sources (`build.zig`), so a width that is not the
//! selected one has real entry points behind it here; what refuses is this
//! build's *typed surface* for it, because `Surface` is a view of the width
//! this build selected and not a second library.
//!
//! Upstream still ships `libpcre2-8`, `libpcre2-16` and `libpcre2-32` as three
//! separate libraries (`doc/pcre2.txt:494-503`) and none of them exports
//! another's names. That is why a provider for the runtime route has to be one
//! file carrying all three (`runtime/library.zig`), and why `compiled_width`
//! and `Width8`, `Width16` and `Width32` exist: they are how a caller says
//! which width it means, and the two that are not the compiled one refuse at
//! compile time rather than becoming a link error later.
//!
//! **A declaration in `pub const c` is not a call this build can always make.**
//! In this build's own artifact every width's entry point is defined. Against a
//! single-width upstream library it is not: `pcre2.c.pcre2_match_16` in a
//! width-8 product linked to one of those is a link failure, not a runtime
//! answer, and this module does nothing to make it one.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which at
//! comptime.
//!
//! *Linked* is the default. The C library is linked, `c` is the translated
//! header, and every call below is a direct call with no table and no check.
//! `deps/lock` still describes `dep.module("pcre2")` the same way in both, so a
//! dependent does not have to know which one it got.
//!
//! *Runtime-loaded* is opt-in with `-Druntime=true`. The library is not linked;
//! `c` is a dispatch generated from the same translation step's output, and
//! every entry point that translation declared is resolved through the
//! platform loader when the caller calls `load`. Every call before that fill
//! stops the program with a message naming the library and the function that
//! was reached for. There is no fallback to a linked copy, no path-to-system
//! fallback, no unload, and no automatic retry.
//!
//! What a provider has to be is written out in `runtime/library.zig` and, for
//! the caller, in the `load` documentation below. In short: every entry point
//! the translated header declares, all three widths at once, because one
//! `load` names one file and a single-width upstream library has nothing
//! behind two thirds of what this module translates.
//!
//! **What this module does not do.** It does not reimplement matching, it does
//! not copy a capture out of the caller's subject, and it takes no Zig
//! allocator: every block here is allocated by PCRE2 and released by PCRE2, or
//! allocated by the caller's own allocator through `GeneralContext.create` and
//! released by their own deallocator.
//!
//! ## The shortest sequence that uses it
//!
//! ```zig
//! const std = @import("std");
//! const pcre2 = @import("pcre2");
//!
//! pub fn main() !void {
//!     const subject = "example.com:443";
//!     var regex = switch (try pcre2.Regex.compile("^(?<host>[^/:]+):", .{})) {
//!         .compiled => |compiled| compiled,
//!         .rejected => return error.BadPattern,
//!     };
//!     defer regex.deinit();
//!     var match_data = try pcre2.MatchData.create(&regex);
//!     defer match_data.deinit();
//!     switch (try regex.match(subject, 0, .{}, &match_data, null)) {
//!         .matched => {},
//!         .no_match => return error.NoMatch,
//!         else => return error.MatchRefused,
//!     }
//!     const host = (try match_data.group(1)) orelse return error.NoSuchGroup;
//!     std.debug.print("{s}\n", .{host});
//! }
//! ```
//!
//! A third owned block, `pcre2.MatchContext.init()`, is what bounds the work
//! PCRE2 does, and `match`'s last argument takes it or `null` for upstream's
//! compiled-in defaults. It is optional; nothing above depends on it.
//!
//! ## Ownership and lifetime
//!
//!   * `Regex` owns the `pcre2_code` and releases it in `deinit`. PCRE2
//!     allocates that block itself (`pcre2_compile.c`) and there is no allocator
//!     to confuse: no Zig allocator is handed to PCRE2, no general context is
//!     created, and no global allocator hook is installed. A caller who does
//!     create a `GeneralContext` gets PCRE2 to allocate from their own pair
//!     instead, and that block is still released by this `deinit`.
//!   * `MatchData`, `MatchContext`, `CompileContext`, `ConvertContext`,
//!     `JitStack`, `Serialized`, `Owned`, `SubstringList` and
//!     `ConvertContext.Converted` are owned separately and released by their own
//!     `deinit`. `Regex.match` never frees the caller's `MatchData`, so a
//!     `defer` around one cannot double free.
//!   * Each owner clears its own handle field in `deinit`, which makes a second
//!     call on the same variable a no-op. That protects one variable, not two:
//!     copying an owner before its `deinit` copies the pointer, and releasing
//!     both copies frees the same block twice. There is one owner of each block,
//!     and it is the value `deinit` was called on.
//!   * Capture ranges are code-unit offsets into the subject the caller passed.
//!     `MatchData` borrows that slice and never copies it, so a capture is
//!     valid until the next `match`, `dfa` or `substitute` on the same
//!     `MatchData`, until that `MatchData` is deinitialised, or until the
//!     subject is written to. PCRE2 fills its offset vector only when an
//!     attempt matched (`src/pcre2_match.c:1045-1053`), so a block whose last
//!     attempt did not match reports no capture at all: `groupRange` and
//!     `group` answer null rather than hand back offsets that describe an
//!     earlier subject. `substitute` is the one that must be said out loud,
//!     because upstream matches into the caller's block and then leaves the
//!     number of replacements it made in `match_data->rc`
//!     (`src/pcre2_substitute.c:984`, `:1762`, `:1768`) -- a field every
//!     native substring entry point reads as a pair count
//!     (`src/pcre2_substring.c:317`, `:390`). So after a substitution the
//!     block reports no capture at all, whatever was in it before, and the
//!     substitution count is the `Substitution`'s to report rather than the
//!     block's to keep. The exception is `SubstituteOptions.matched`, where
//!     upstream substitutes the match already in the block and leaves that
//!     block untouched (`src/pcre2_substitute.c:898-917`, `:1767`).
//!   * `version` writes into a buffer the caller owns and answers with a slice of
//!     that same buffer. Nothing it returns is a borrow of a frame that has
//!     already gone: the storage and the string in it have one lifetime, and it
//!     is the caller's.
//!   * The typed surface takes **no** Zig allocator. A block PCRE2 allocated is
//!     released by the owner's `deinit`; a block a caller's allocator produced is
//!     released by their own deallocator, which PCRE2 calls. A Zig leak checker
//!     therefore cannot see any of it, and `deinit` on each owner is the whole
//!     of the accounting.

const std = @import("std");
const widthed = @import("widthed.zig");
const posix = @import("posix.zig");

/// The complete translated `pcre2.h` for this build.
///
/// This is the raw C surface, not a filtered one: the 16-bit and 32-bit
/// declarations are present because `src/pcre2.h.generic:1021-1030` emits all
/// three widths, and `pcre2_dfa_match`, `pcre2_substitute` and the serialization
/// calls are present because this facade does not wrap every one of them by
/// hand.
///
/// **Which of these have a symbol behind them.** This is the whole header for
/// all three widths, and the artifact this build produces is built from all
/// three widths' unmodified upstream sources, so each of them is defined in
/// it. `-Dcode-unit-width` still selects the artifact's own name, the generic
/// aliases and the typed facade: `PCRE2_CODE_UNIT_WIDTH` is defined with that
/// value on the translation line and `PCRE2_SUFFIX` pastes the width into every
/// exported name (`src/pcre2.h.generic:1064`), so a width-8 product defines
/// `pcre2_match_8`, `pcre2_match_16` and `pcre2_match_32`, and the typed
/// surface it reaches through `pcre2.Surface` is the 8-bit one.
///
/// **JIT is the one case where a declaration here is a symbol and not a working
/// feature.** JIT is off in this fork, so `SUPPORT_JIT` is 0 in the generated
/// `config.h`, and `src/pcre2_jit_compile.c` is still in the
/// translation-unit list. Its `pcre2_jit_compile` is defined outside the
/// `#ifdef SUPPORT_JIT` (`:14303-14432`), and its all-in-one includes of
/// `pcre2_jit_match_inc.h` and `pcre2_jit_misc_inc.h` are at file scope
/// (`:14439-14440`, after the guard closes at `:14431`) rather than inside it.
/// Both of those files open an `#ifndef SUPPORT_JIT` arm for their exported
/// definitions, so all six entry points `src/pcre2.h.generic:846-859` declares
/// are defined in this archive and every one of them refuses:
///
/// * `pcre2_jit_compile_8`, `src/pcre2_jit_compile.c:14303-14432`:
///   `PCRE2_ERROR_JIT_BADOPTION`, -45, for an ordinary request
///   (`:14391-14392`) and for an option outside `PUBLIC_JIT_COMPILE_OPTIONS`
///   (`:14342-14343`); `PCRE2_ERROR_JIT_UNSUPPORTED`, -68, for
///   `PCRE2_JIT_TEST_ALLOC` (`:14329-14335`).
/// * `pcre2_jit_match_8`, `src/pcre2_jit_match_inc.h:90-96`:
///   `PCRE2_ERROR_JIT_BADOPTION` (`:103`).
/// * `pcre2_jit_free_unused_memory_8`, `src/pcre2_jit_misc_inc.h:106-117`:
///   it does no work (`:109-110`).
/// * `pcre2_jit_stack_create_8`, `src/pcre2_jit_misc_inc.h:125-134`: `NULL`
///   (`:134`).
/// * `pcre2_jit_stack_assign_8`, `src/pcre2_jit_misc_inc.h:165`: it does no work
///   (`:169-172`).
/// * `pcre2_jit_stack_free_8`, `src/pcre2_jit_misc_inc.h:187`: it does no work
///   (`:190-192`).
///
/// Disabled JIT functionality does not mean these fallback symbols are absent.
///
/// The declarations are read from this repository's own 10.49 header as the
/// compiler for this target expands it. On a GNU-libc target Aro reads
/// `translate.h` for itself, because Aro reads that C library's headers and the
/// target's own preprocessor's expansion of them is not a file Aro can parse;
/// on every other target build.zig expands it first with `zig cc -E -dD
/// -fno-blocks` for the target and hands over the result, because Aro's own
/// preprocessor cannot read that C library. Either route adds nothing to PCRE2's
/// surface and takes nothing from it: every declaration the header publishes is
/// present, for all three widths, and the C library declarations
/// `src/pcre2.h.generic:87-89` includes are here as expanded, beside PCRE2's
/// own. Where two front ends read the same header they are held to one language
/// and to the types the target really has -- blocks off, because Aro cannot parse
/// a block pointer, and the compiler's own `__int128_t`/`__uint128_t` restated
/// in `translate.h`, because the C library headers spell those names without
/// declaring them -- so what reaches this module is what the translator could
/// have read for itself.
///
/// **In a runtime-loading build this is the generated dispatch, not the
/// translated header.** Every entry point of the compiled width is re-exported
/// from the same translation step, so a type named here and a type named in the
/// dispatch are one nominal type; what differs is that a name reaches the
/// library through a table `load` fills rather than through a link line.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations and this module is
/// never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// The typed surface of the compiled width, under short names.
///
/// Every declaration below is an alias into `WidthN` for the width this build
/// compiled, so `pcre2.Regex` is `pcre2.Width8.Regex` in an 8-bit build and
/// `pcre2.Width16.Regex` in a 16-bit one. That is why `tests.zig`, `smoke.zig`
/// and the consumer work at every width without naming one. Only the selected
/// prong is evaluated, so the two widths that were not compiled are never
/// instantiated and their `@compileError` is never reached.
pub const Surface = switch (widthed.compiled_width) {
    .@"8" => Width8,
    .@"16" => Width16,
    .@"32" => Width32,
};

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then use
/// this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use. A
/// failed attempt publishes nothing and can be retried explicitly, by calling
/// this again: there is no automatic retry, and no implicit second source.
///
/// A provider must export every entry point this module's translation declared,
/// which is all three code-unit widths, and the POSIX wrapper's four names in a
/// width-8 build. `runtime/library.zig` names why, and why an ordinary
/// single-width `libpcre2-8` from a system package is not one: it has nothing
/// behind the other two widths' declarations.
///
/// It keeps the process handle and its own copy of the request to the end of the
/// process. There is no unload and no reset, because the table is process-global
/// state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for the
/// same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports both
/// configurations can tell the two apart at comptime instead of meeting this at
/// run time.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "pcre2: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "-Druntime=true, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// The code-unit width this build is about.
///
/// Read out of the translation, which `build.zig` configured from the same
/// `-Dcode-unit-width` it put on the C compile line. It selects the generic
/// aliases, the primary artifact's name and `Surface`; it is not a property of
/// the header, which publishes all three widths, and not a limit on the
/// artifact, which carries all three.
pub const compiled_width: widthed.CodeUnitWidth = widthed.compiled_width;

/// The type of one code unit of that width: `u8`, `u16` or `u32`.
///
/// A subject, a pattern, a replacement, a diagnostic and a version buffer are
/// all slices of this, and the offsets PCRE2 reports are in it. Published
/// because a caller that stores a subject needs the type to store it in.
pub const compiled_unit: type = widthed.compiled_width.unit();

/// The typed surface of one code-unit width.
///
/// Only the selected width can be used: `Width(16)` in an 8-bit build is a
/// compile-time refusal naming the width this build selected, because this
/// facade is a view of that one width and `pub const c` is the route to
/// another.
pub const Width = widthed.Width;

/// The typed surface for `u8`, whichever width this build compiled.
pub const Width8 = if (widthed.compiled_width.unit() == u8) widthed.Width(u8) else
    @compileError(
        "pcre2: this build did not compile the 8-bit library, so pcre2.Width8 " ++
            "has no entry points behind it. Use pcre2.compiled_width, or build " ++
            "with -Dcode-unit-width=8.",
    );

/// The typed surface for `u16`, whichever width this build compiled.
pub const Width16 = if (widthed.compiled_width.unit() == u16) widthed.Width(u16) else
    @compileError(
        "pcre2: this build did not compile the 16-bit library, so pcre2.Width16 " ++
            "has no entry points behind it. Use pcre2.compiled_width, or build " ++
            "with -Dcode-unit-width=16.",
    );

/// The typed surface for `u32`, whichever width this build compiled.
pub const Width32 = if (widthed.compiled_width.unit() == u32) widthed.Width(u32) else
    @compileError(
        "pcre2: this build did not compile the 32-bit library, so pcre2.Width32 " ++
            "has no entry points behind it. Use pcre2.compiled_width, or build " ++
            "with -Dcode-unit-width=32.",
    );

/// Everything this facade can refuse to do.
pub const Error = widthed.Error;

/// `PCRE2_UNSET`: the value PCRE2 leaves in the offset vector for a group that
/// did not take part.
pub const unset: usize = widthed.unset;

/// The largest number of code units a diagnostic is kept in.
pub const diagnostic_buffer_size: usize = widthed.diagnostic_buffer_size;

/// `MAX_NAME_SIZE`: the longest group name a pattern can declare.
pub const max_name_length: usize = widthed.max_name_length;

pub const compile_option = widthed.compile_option;
pub const CompileOptions = widthed.CompileOptions;
pub const match_option = widthed.match_option;
pub const MatchOptions = widthed.MatchOptions;
pub const DfaOptions = widthed.DfaOptions;
pub const SubstituteOptions = widthed.SubstituteOptions;
pub const convert_option = widthed.convert_option;
pub const newline = widthed.newline;
pub const bsr = widthed.bsr;
pub const optimization = widthed.optimization;
pub const jit_option = widthed.jit_option;
pub const substitute_case = widthed.substitute_case;

pub const Text = Surface.Text;
pub const Group = Surface.Group;
pub const Name = Surface.Name;
pub const Rejection = Surface.Rejection;
pub const CompileOutcome = Surface.CompileOutcome;
pub const MatchOutcome = Surface.MatchOutcome;
pub const DfaOutcome = Surface.DfaOutcome;
pub const Substitution = Surface.Substitution;
pub const JitOutcome = Surface.JitOutcome;

pub const GeneralContext = Surface.GeneralContext;
pub const CompileContext = Surface.CompileContext;
pub const ConvertContext = Surface.ConvertContext;
pub const MatchContext = Surface.MatchContext;
pub const JitStack = Surface.JitStack;
pub const Regex = Surface.Regex;
pub const MatchData = Surface.MatchData;
pub const Serialized = Surface.Serialized;
pub const Owned = Surface.Owned;
pub const SubstringList = Surface.SubstringList;
pub const DfaWorkspace = Surface.DfaWorkspace;

/// A callback invoked at each callout in a pattern, as the header declares it.
pub const Callout = Surface.Callout;
/// A callback `Regex.enumerateCallouts` walks the pattern with. Not optional:
/// upstream calls it without testing it (`src/pcre2_pattern_info.c:405`, `:418`).
pub const CalloutEnumerate = Surface.CalloutEnumerate;
/// A callback invoked for each substitution.
pub const SubstituteCallout = Surface.SubstituteCallout;
/// A callback that supplies one substitution's replacement text.
pub const SubstituteCaseCallout = Surface.SubstituteCaseCallout;
/// A callback the compiler consults before recursing further.
pub const RecursionGuard = Surface.RecursionGuard;
/// A callback that supplies a JIT machine stack for one attempt.
pub const JitCallback = Surface.JitCallback;
/// An allocation function, as `pcre2_general_context_create` takes it.
pub const Allocate = Surface.Allocate;
/// A deallocation function, as `pcre2_general_context_create` takes it.
pub const Deallocate = Surface.Deallocate;

/// PCRE2's own text for one error number, in code units of the compiled width.
pub const diagnostic = Surface.diagnostic;

/// The version string the library reports, written into `buffer` and returned as
/// a window on it. The buffer is in code units.
pub const version = Surface.version;

/// Upstream's POSIX `regcomp`/`regexec` emulation.
///
/// A second library, present only where this build links it: the 8-bit width and
/// the linked configuration. `Posix.availability` says which, and
/// `Posix.compile` and `Posix.exec` are compile-time refusals in a configuration
/// where it is not, rather than a call that would not link.
pub const Posix = switch (posix.availability) {
    .linked => posix,
    .unavailable => posix.Unavailable,
};

/// Whether this build was configured to resolve the native symbols at run time.
///
/// The same answer as `runtime_loaded`, under the name the configuration's own
/// documentation uses.
pub const is_runtime_loaded: bool = runtime_loaded;
