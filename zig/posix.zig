// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//! Typed bindings for upstream's POSIX wrapper over PCRE2.
//! Requires the 8-bit build; linked and runtime-dispatch routes are supported.
//! `Compiled` owns wrapper state; release it with `deinit`.

const c = @import("c");
const widthed = @import("widthed.zig");

/// POSIX and PCRE2 flags; `startend` and `pend` are unsupported by these slice helpers.
pub const option = struct {
    pub const icase: u32 = 0x0001; // :58 REG_ICASE, maps to PCRE2_CASELESS
    pub const newline: u32 = 0x0002; // :59 REG_NEWLINE, maps to PCRE2_MULTILINE
    pub const notbol: u32 = 0x0004; // :60 REG_NOTBOL
    pub const noteol: u32 = 0x0008; // :61 REG_NOTEOL
    /// Not POSIX. Maps to `PCRE2_DOTALL`.
    pub const dotall: u32 = 0x0010; // :62 REG_DOTALL
    /// Compile-time flag; suppresses capture reporting in later executions.
    /// Reported as `matched_without_reporting`.
    pub const nosub: u32 = 0x0020; // :63 REG_NOSUB
    /// Not POSIX. Maps to `PCRE2_UTF`.
    pub const utf: u32 = 0x0040; // :64 REG_UTF
    /// BSD flag; its pointer-encoded bounds are unsupported by `exec`.
    pub const startend: u32 = 0x0080; // :65 REG_STARTEND
    /// Not POSIX. Maps to `PCRE2_NOTEMPTY`.
    pub const notempty: u32 = 0x0100; // :66 REG_NOTEMPTY
    /// Not POSIX. Maps to `PCRE2_UNGREEDY`.
    pub const ungreedy: u32 = 0x0200; // :67 REG_UNGREEDY
    /// Not POSIX. Maps to `PCRE2_UCP`.
    pub const ucp: u32 = 0x0400; // :68 REG_UCP
    /// GNU flag; its pointer-encoded pattern end is unsupported by `compile`.
    pub const pend: u32 = 0x0800; // :69 REG_PEND
    /// Maps to `PCRE2_LITERAL`, so every character in the pattern is literal.
    pub const nospec: u32 = 0x1000; // :70 REG_NOSPEC
};

/// POSIX error codes returned by the upstream wrapper.
pub const code = struct {
    pub const assert: c_int = 1; // :80
    pub const badbr: c_int = 2; // :81
    pub const badpat: c_int = 3; // :82
    pub const badrpt: c_int = 4; // :83
    pub const ebrace: c_int = 5; // :84
    pub const ebrack: c_int = 6; // :85
    pub const ecollate: c_int = 7; // :86
    pub const ectype: c_int = 8; // :87
    pub const eescape: c_int = 9; // :88
    pub const empty: c_int = 10; // :89
    pub const eparen: c_int = 11; // :90
    pub const erange: c_int = 12; // :91
    pub const esize: c_int = 13; // :92
    pub const espace: c_int = 14; // :93
    pub const esubreg: c_int = 15; // :94
    pub const invarg: c_int = 16; // :95
    pub const nomatch: c_int = 17; // :96, REG_NOMATCH
};

/// Exact upstream `regex_t` type used by this wrapper.
/// It is distinct from the system `regex_t`.
pub const Regex = c.regex_t;

/// `regoff_t`, the byte-offset type in `regmatch_t`.
pub const Offset = c.regoff_t;

/// `regmatch_t` capture offsets.
pub const Match = c.regmatch_t;

/// POSIX marker (`-1`) for unmatched groups and unused output slots.
/// It differs from `PCRE2_UNSET`; use it for POSIX results.
pub const unset: c_int = -1;

/// Result of `pcre2_regcomp`.
pub const CompileOutcome = union(enum) {
    /// Owns the compiled wrapper block; release it with `Compiled.deinit`.
    compiled: Compiled,
    /// Upstream refused the pattern and returned this POSIX code.
    rejected: struct { code: c_int },
};

/// Wrapper-specific failures; POSIX codes are reported in outcomes instead.
pub const Error = error{
    /// `REG_STARTEND` and `REG_PEND` require pointer bounds this slice API cannot represent.
    /// Use upstream C entry points directly if these flags are needed.
    UnsupportedOption,
    /// The `Compiled` handle is uninitialized or was released.
    RegexNotCompiled,
};

/// Result of one `pcre2_regexec` call.
pub const MatchOutcome = union(enum) {
    /// Matched; `pmatch` holds byte offsets, with `unset` for absent and unused slots.
    matched: void,
    /// `REG_NOMATCH`; an ordinary non-match, not an error.
    no_match: void,
    /// The pattern used `REG_NOSUB`; execution matched but reported no captures.
    matched_without_reporting: void,
    /// Another non-zero POSIX error code.
    failed: struct { code: c_int },
};

/// Owns upstream's `regex_t`; compile returns it and `deinit` releases its contents.
/// Do not copy the handle.
pub const Compiled = struct {
    /// Wrapper's `regex_t`; null after `deinit`.
    raw: ?Regex,

    /// Releases the wrapper block and clears this handle.
    /// Safe to call twice on the same value; do not copy the handle.
    pub fn deinit(self: *Compiled) void {
        if (self.raw) |*raw| c.pcre2_regfree(raw);
        self.raw = null;
    }
};

/// Compiles a NUL-terminated POSIX pattern; rejection returns its POSIX code.
/// `REG_PEND` is unsupported; `REG_NOSUB` is retained for later execution.
pub fn compile(pattern: [:0]const u8, flags: u32) Error!CompileOutcome {
    if ((flags & option.pend) != 0) return error.UnsupportedOption;
    var compiled: Regex = undefined;
    const rc = c.pcre2_regcomp(&compiled, pattern.ptr, @bitCast(flags));
    if (rc != 0) return .{ .rejected = .{ .code = rc } };
    return .{ .compiled = .{ .raw = compiled } };
}

/// Matches a NUL-terminated byte string; `pmatch.len` is the number of output slots.
/// Only `REG_NOTBOL`, `REG_NOTEOL`, and `REG_NOTEMPTY` are honored; `REG_STARTEND` is unsupported.
pub fn exec(
    compiled: *const Compiled,
    subject: [:0]const u8,
    pmatch: []Match,
    flags: u32,
) Error!MatchOutcome {
    if ((flags & (option.startend | option.pend)) != 0) return error.UnsupportedOption;
    const regex: *const Regex = if (compiled.raw) |*r| r else return error.RegexNotCompiled;
    const rc = c.pcre2_regexec(regex, subject.ptr, pmatch.len, pmatch.ptr, @bitCast(flags));
    if (rc == 0) {
        if ((@as(u32, @bitCast(regex.re_cflags)) & option.nosub) != 0)
            return .matched_without_reporting;
        return .matched;
    }
    if (rc == code.nomatch) return .no_match;
    return .{ .failed = .{ .code = rc } };
}

/// Returns a captured byte slice from the supplied subject, or null when unset.
/// Pass the same subject used by `exec`.
pub fn capture(subject: []const u8, match: Match) ?[]const u8 {
    if (match.rm_so == unset or match.rm_eo == unset) return null;
    const start: usize = @intCast(match.rm_so);
    const end: usize = @intCast(match.rm_eo);
    if (start > end or end > subject.len) return null;
    return subject[start..end];
}

/// Writes and returns the upstream error message; a zero-length buffer queries required size.
/// Pass the compiled block only when available; a rejected pattern has none.
pub fn message(buffer: []u8, err: c_int, compiled: ?*const Regex) [:0]const u8 {
    const needed = c.pcre2_regerror(
        err,
        if (compiled) |r| r else null,
        buffer.ptr,
        buffer.len,
    );
    // Required length includes NUL, even when the buffer is too small.
    const length = @min(needed, buffer.len);
    if (length == 0) return buffer[0..0 :0];
    return buffer[0 .. length - 1 :0];
}

/// Whether this build exposes the wrapper's translated declarations.
/// `.linked` includes both directly linked and runtime-dispatch builds.
pub const Availability = enum {
    /// 8-bit wrapper declarations are available in linked and runtime builds.
    linked,
    /// The build did not translate the 8-bit wrapper declarations.
    unavailable,
};

/// True when all four POSIX functions and their types were translated.
/// This reports declarations, not whether their symbols are linked.
pub const translated: bool = @hasDecl(c, "pcre2_regcomp") and
    @hasDecl(c, "pcre2_regexec") and
    @hasDecl(c, "pcre2_regerror") and
    @hasDecl(c, "pcre2_regfree") and
    @hasDecl(c, "regex_t") and
    @hasDecl(c, "regmatch_t") and
    @hasDecl(c, "regoff_t");

/// `.linked` when wrapper declarations exist in an 8-bit build; otherwise `.unavailable`.
/// Runtime loading also supports 8-bit builds; `routed` identifies that path.
pub const availability: Availability = if (translated and
    widthed.compiled_width == .@"8") .linked else .unavailable;

/// True when calls use runtime dispatch; false in directly linked builds.
/// Both routes expose the same wrapper functions.
pub const routed: bool = runtime_loaded;

/// Runtime-dispatch flag, read without importing the root module.
const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// POSIX option bits re-exported for both configurations.
pub const posix_option = option;

/// POSIX error codes available in either configuration.
pub const posix_code = code;

/// Availability enum shared by both configurations.
pub const posix_availability = Availability;

/// POSIX unmatched-group marker available in both configurations.
pub const posix_unset = unset;

/// Message used by an unavailable entry point.
fn unavailable_message(comptime what: []const u8) []const u8 {
    return "pcre2: the POSIX wrapper is not reachable in this build, so " ++
        what ++ " has no library behind it. It is 8-bit by construction " ++
        "(src/pcre2posix.h:104-119), build.zig builds it only for width 8, and " ++
        "translate.h includes pcre2posix.h only under " ++
        "#if PCRE2_CODE_UNIT_WIDTH == 8. A runtime-loading build is not the " ++
        "reason: build.zig compiles the wrapper into the core for width 8 and " ++
        "exports the four from it, so one provider carries them. Build with " ++
        "-Dcode-unit-width=8, and read pcre2.Posix.availability to see which of " ++
        "the two facts is the one missing.";
}

/// Compile-time API for builds without the 8-bit POSIX wrapper.
/// Calling an operation raises a compile error naming that entry point.
pub const Unavailable = struct {
    /// Always `.unavailable`.
    pub const availability: posix_availability = .unavailable;

    /// Shared availability enum.
    pub const Availability = posix_availability;

    /// POSIX marker for unmatched groups.
    pub const unset = posix_unset;

    /// POSIX option bits and error codes; these constants need no linked symbols.
    pub const option = posix_option;
    pub const code = posix_code;

    pub fn compile(pattern: [:0]const u8, flags: u32) Error!CompileOutcome {
        _ = pattern;
        _ = flags;
        @compileError(unavailable_message("pcre2.Posix.compile"));
    }

    pub fn exec(
        compiled: *const Compiled,
        subject: [:0]const u8,
        pmatch: []Match,
        flags: u32,
    ) Error!MatchOutcome {
        _ = compiled;
        _ = subject;
        _ = pmatch;
        _ = flags;
        @compileError(unavailable_message("pcre2.Posix.exec"));
    }

    pub fn capture(subject: []const u8, match: Match) ?[]const u8 {
        _ = subject;
        _ = match;
        @compileError(unavailable_message("pcre2.Posix.capture"));
    }

    pub fn message(buffer: []u8, err: c_int, compiled: ?*const Regex) [:0]const u8 {
        _ = buffer;
        _ = err;
        _ = compiled;
        @compileError(unavailable_message("pcre2.Posix.message"));
    }
};
