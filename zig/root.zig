// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//
//! Typed PCRE2 facade for one code-unit width, with raw C and POSIX routes.
//! Owners release PCRE2 blocks; captures borrow the caller's subject.

const std = @import("std");
const widthed = @import("widthed.zig");
const posix = @import("posix.zig");

/// Raw declarations for all PCRE2 widths, or their runtime dispatch.
/// JIT entry points use upstream's disabled-build behavior.
pub const c = @import("c");

/// Loader core used by the linked configuration.
const rt = @import("rt");

/// True when this build uses runtime dispatch rather than linking PCRE2.
/// Use this compile-time value to select configuration-specific code.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Typed facade for the code-unit width selected by this build.
pub const Surface = switch (widthed.compiled_width) {
    .@"8" => Width8,
    .@"16" => Width16,
    .@"32" => Width32,
};

/// Explicit provider path or system-loader name; no fallback is used.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Loads a provider exporting all declared widths; failed attempts may be retried.
/// Different requests return `ProviderMismatch`; recursion returns `ReentrantLoad`; linked builds panic.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;
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

/// Returns the retained successful request, or null before loading.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// The code-unit width selected by this build; the artifact exposes one width.
pub const compiled_width: widthed.CodeUnitWidth = widthed.compiled_width;

/// Code-unit type for patterns, subjects, captures, and offsets.
pub const compiled_unit: type = widthed.compiled_width.unit();

/// Typed surface for one code-unit type; only the compiled width is available.
pub const Width = widthed.Width;

/// Typed surface for `u8`; available only when this build compiled 8-bit PCRE2.
pub const Width8 = if (widthed.compiled_width.unit() == u8) widthed.Width(u8) else @compileError(
    "pcre2: this build did not compile the 8-bit library, so pcre2.Width8 " ++
        "has no entry points behind it. Use pcre2.compiled_width, or build " ++
        "with -Dcode-unit-width=8.",
);

/// Typed surface for `u16`; available only when this build compiled 16-bit PCRE2.
pub const Width16 = if (widthed.compiled_width.unit() == u16) widthed.Width(u16) else @compileError(
    "pcre2: this build did not compile the 16-bit library, so pcre2.Width16 " ++
        "has no entry points behind it. Use pcre2.compiled_width, or build " ++
        "with -Dcode-unit-width=16.",
);

/// Typed surface for `u32`; available only when this build compiled 32-bit PCRE2.
pub const Width32 = if (widthed.compiled_width.unit() == u32) widthed.Width(u32) else @compileError(
    "pcre2: this build did not compile the 32-bit library, so pcre2.Width32 " ++
        "has no entry points behind it. Use pcre2.compiled_width, or build " ++
        "with -Dcode-unit-width=32.",
);

/// Everything this facade can refuse to do.
pub const Error = widthed.Error;

/// `PCRE2_UNSET`: the value PCRE2 leaves in the offset vector for a group that
/// did not take part.
pub const unset: usize = widthed.unset;

/// Capacity in code units of the diagnostic text buffer.
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

/// Callback invoked at each pattern callout.
pub const Callout = Surface.Callout;
/// Required callback for pattern callout enumeration; nonzero stops the walk.
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

/// Writes the library version to caller-owned code units and returns a borrowed slice.
/// The buffer must include space for the terminating NUL.
pub const version = Surface.version;

/// POSIX wrapper, available in 8-bit linked and runtime-dispatch builds.
pub const Posix = switch (posix.availability) {
    .linked => posix,
    .unavailable => posix.Unavailable,
};

/// Alias for `runtime_loaded`.
pub const is_runtime_loaded: bool = runtime_loaded;
