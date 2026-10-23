// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//! Typed PCRE2 facade for one code-unit width.
//! Owners release PCRE2 blocks; captures borrow the caller's subject.

const std = @import("std");
const c = @import("c");
const raw = @import("raw.zig");

/// The three code-unit widths PCRE2 exposes.
pub const CodeUnitWidth = enum(u8) {
    @"8",
    @"16",
    @"32",

    /// The digits `PCRE2_SUFFIX` pastes onto an exported name.
    pub inline fn bits(self: CodeUnitWidth) []const u8 {
        return switch (self) {
            .@"8" => "8",
            .@"16" => "16",
            .@"32" => "32",
        };
    }

    /// `PCRE2_UCHAR<N>`: the type of one code unit of that width.
    pub inline fn unit(self: CodeUnitWidth) type {
        return switch (self) {
            .@"8" => u8,
            .@"16" => u16,
            .@"32" => u32,
        };
    }
};

/// Width selected by the translation's `PCRE2_CODE_UNIT_WIDTH` declaration.
/// A missing width declaration fails at compile time.
pub const compiled_width: CodeUnitWidth = blk: {
    // The translation typedef carries the configured width across front ends.
    if (@hasDecl(c, "pcre2_translate_width")) {
        break :blk switch (@sizeOf(c.pcre2_translate_width)) {
            8 => .@"8",
            16 => .@"16",
            32 => .@"32",
            else => @compileError(
                "zig/widthed.zig: pcre2_translate_width is neither 8, 16 nor 32 " ++
                    "code units, so no width of this library is selected.",
            ),
        };
    }
    if (!@hasDecl(c, "PCRE2_CODE_UNIT_WIDTH")) {
        @compileError(
            "zig/widthed.zig: this build's translation declares neither " ++
                "pcre2_translate_width nor PCRE2_CODE_UNIT_WIDTH, so the width " ++
                "of the library behind this module cannot be established. " ++
                "build.zig puts -DPCRE2_CODE_UNIT_WIDTH on the translation line " ++
                "and translate.h carries the typedef; the route in use has to " ++
                "keep one of them.",
        );
    }
    const value: u32 = @intCast(c.PCRE2_CODE_UNIT_WIDTH);
    break :blk switch (value) {
        8 => .@"8",
        16 => .@"16",
        32 => .@"32",
        else => @compileError(
            "zig/widthed.zig: PCRE2_CODE_UNIT_WIDTH is neither 8, 16 nor 32, " ++
                "so no width of this library is selected.",
        ),
    };
};

pub const Error = error{
    /// PCRE2 reported an allocation failure.
    OutOfMemory,
    /// PCRE2 could not provide metadata required by compilation or callout enumeration.
    PatternInfoUnavailable,
    /// `Regex.match` start offset exceeded the subject length; checked before matching.
    StartOffsetOutOfRange,
    /// Group index is outside `MatchData.captureCount()`.
    NoSuchGroup,
    /// Match data cannot hold the pattern's captures, or a serialization pointer slice is too short.
    /// `Regex.match` clears prior captures before returning this error.
    OvectorTooSmall,
    /// Version buffer cannot hold the string and its terminating NUL.
    VersionBufferTooSmall,
    /// PCRE2 could not answer `PCRE2_CONFIG_VERSION`.
    VersionUnavailable,
    /// PCRE2 rejected a compile or match context setting.
    SettingRefused,
    /// Caller output buffer cannot hold the substitution result.
    SubstituteBufferTooSmall,
    /// DFA scratch buffer is smaller than `minimum_workspace`.
    DfaWorkspaceTooSmall,
    /// JIT stack creation was refused because this build has JIT disabled.
    JitUnsupported,
    /// Requested capture is absent, unset, or unavailable in the offset vector.
    SubstringUnavailable,
    /// Caller buffer cannot hold the copied capture and its terminating NUL.
    SubstringBufferTooSmall,
    /// PCRE2 rejected serialized data or blocks with incompatible character tables.
    SerializationRefused,
};

/// `PCRE2_UNSET`, used for a capture group that did not participate.
pub const unset: usize = ~@as(usize, 0);

/// Size of the buffer used for PCRE2 error messages.
pub const diagnostic_buffer_size = 128;

/// Maximum group-name length accepted by the generated configuration.
pub const max_name_length = 128;

/// Compile-option bits exposed by the typed facade.
pub const compile_option = struct {
    pub const allow_empty_class: u32 = 0x0000_0001; // :116 PCRE2_ALLOW_EMPTY_CLASS
    pub const alt_bsux: u32 = 0x0000_0002; // :117 PCRE2_ALT_BSUX
    pub const auto_callout: u32 = 0x0000_0004; // :118 PCRE2_AUTO_CALLOUT
    pub const caseless: u32 = 0x0000_0008; // :119 PCRE2_CASELESS
    pub const dollar_endonly: u32 = 0x0000_0010; // :120 PCRE2_DOLLAR_ENDONLY
    pub const dotall: u32 = 0x0000_0020; // :121 PCRE2_DOTALL
    pub const duplicate_names: u32 = 0x0000_0040; // :122 PCRE2_DUPNAMES
    pub const extended: u32 = 0x0000_0080; // :123 PCRE2_EXTENDED
    pub const firstline: u32 = 0x0000_0100; // :124 PCRE2_FIRSTLINE
    pub const match_unset_backref: u32 = 0x0000_0200; // :125 PCRE2_MATCH_UNSET_BACKREF
    pub const multiline: u32 = 0x0000_0400; // :126 PCRE2_MULTILINE
    pub const never_ucp: u32 = 0x0000_0800; // :127 PCRE2_NEVER_UCP
    pub const never_utf: u32 = 0x0000_1000; // :128 PCRE2_NEVER_UTF
    pub const no_auto_capture: u32 = 0x0000_2000; // :129 PCRE2_NO_AUTO_CAPTURE
    pub const no_auto_possess: u32 = 0x0000_4000; // :130 PCRE2_NO_AUTO_POSSESS
    pub const no_dotstar_anchor: u32 = 0x0000_8000; // :131 PCRE2_NO_DOTSTAR_ANCHOR
    pub const no_start_optimize: u32 = 0x0001_0000; // :132 PCRE2_NO_START_OPTIMIZE
    pub const ucp: u32 = 0x0002_0000; // :133 PCRE2_UCP
    pub const ungreedy: u32 = 0x0004_0000; // :134 PCRE2_UNGREEDY
    pub const utf: u32 = 0x0008_0000; // :135 PCRE2_UTF
    pub const never_backslash_c: u32 = 0x0010_0000; // :136 PCRE2_NEVER_BACKSLASH_C
    pub const alt_circumflex: u32 = 0x0020_0000; // :137 PCRE2_ALT_CIRCUMFLEX
    pub const alt_verbnames: u32 = 0x0040_0000; // :138 PCRE2_ALT_VERBNAMES
    pub const use_offset_limit: u32 = 0x0080_0000; // :139 PCRE2_USE_OFFSET_LIMIT
    pub const extended_more: u32 = 0x0100_0000; // :140 PCRE2_EXTENDED_MORE
    pub const literal: u32 = 0x0200_0000; // :141 PCRE2_LITERAL
    pub const match_invalid_utf: u32 = 0x0400_0000; // :142 PCRE2_MATCH_INVALID_UTF
    pub const alt_extended_class: u32 = 0x0800_0000; // :143 PCRE2_ALT_EXTENDED_CLASS
    pub const endanchored: u32 = 0x2000_0000; // :104 PCRE2_ENDANCHORED
    pub const no_utf_check: u32 = 0x4000_0000; // :103 PCRE2_NO_UTF_CHECK
    pub const anchored: u32 = 0x8000_0000; // :102 PCRE2_ANCHORED
};

/// Compile flags. All fields default to PCRE2's no-options setting.
/// Only named upstream flags are exposed.
pub const CompileOptions = packed struct {
    allow_empty_class: bool = false,
    alt_bsux: bool = false,
    auto_callout: bool = false,
    caseless: bool = false,
    dollar_endonly: bool = false,
    dotall: bool = false,
    duplicate_names: bool = false,
    extended: bool = false,
    firstline: bool = false,
    match_unset_backref: bool = false,
    multiline: bool = false,
    never_ucp: bool = false,
    never_utf: bool = false,
    no_auto_capture: bool = false,
    no_auto_possess: bool = false,
    no_dotstar_anchor: bool = false,
    no_start_optimize: bool = false,
    ucp: bool = false,
    ungreedy: bool = false,
    utf: bool = false,
    never_backslash_c: bool = false,
    alt_circumflex: bool = false,
    alt_verbnames: bool = false,
    use_offset_limit: bool = false,
    extended_more: bool = false,
    literal: bool = false,
    match_invalid_utf: bool = false,
    alt_extended_class: bool = false,
    endanchored: bool = false,
    no_utf_check: bool = false,
    anchored: bool = false,

    /// The 32-bit word `pcre2_compile_N` expects.
    pub inline fn toBits(self: CompileOptions) u32 {
        var bits: u32 = 0;
        if (self.allow_empty_class) bits |= compile_option.allow_empty_class;
        if (self.alt_bsux) bits |= compile_option.alt_bsux;
        if (self.auto_callout) bits |= compile_option.auto_callout;
        if (self.caseless) bits |= compile_option.caseless;
        if (self.dollar_endonly) bits |= compile_option.dollar_endonly;
        if (self.dotall) bits |= compile_option.dotall;
        if (self.duplicate_names) bits |= compile_option.duplicate_names;
        if (self.extended) bits |= compile_option.extended;
        if (self.firstline) bits |= compile_option.firstline;
        if (self.match_unset_backref) bits |= compile_option.match_unset_backref;
        if (self.multiline) bits |= compile_option.multiline;
        if (self.never_ucp) bits |= compile_option.never_ucp;
        if (self.never_utf) bits |= compile_option.never_utf;
        if (self.no_auto_capture) bits |= compile_option.no_auto_capture;
        if (self.no_auto_possess) bits |= compile_option.no_auto_possess;
        if (self.no_dotstar_anchor) bits |= compile_option.no_dotstar_anchor;
        if (self.no_start_optimize) bits |= compile_option.no_start_optimize;
        if (self.ucp) bits |= compile_option.ucp;
        if (self.ungreedy) bits |= compile_option.ungreedy;
        if (self.utf) bits |= compile_option.utf;
        if (self.never_backslash_c) bits |= compile_option.never_backslash_c;
        if (self.alt_circumflex) bits |= compile_option.alt_circumflex;
        if (self.alt_verbnames) bits |= compile_option.alt_verbnames;
        if (self.use_offset_limit) bits |= compile_option.use_offset_limit;
        if (self.extended_more) bits |= compile_option.extended_more;
        if (self.literal) bits |= compile_option.literal;
        if (self.match_invalid_utf) bits |= compile_option.match_invalid_utf;
        if (self.alt_extended_class) bits |= compile_option.alt_extended_class;
        if (self.endanchored) bits |= compile_option.endanchored;
        if (self.no_utf_check) bits |= compile_option.no_utf_check;
        if (self.anchored) bits |= compile_option.anchored;
        return bits;
    }
};

/// Option bits shared by matching, DFA matching, and substitution.
pub const match_option = struct {
    pub const notbol: u32 = 0x0000_0001; // :179 PCRE2_NOTBOL
    pub const noteol: u32 = 0x0000_0002; // :180 PCRE2_NOTEOL
    pub const notempty: u32 = 0x0000_0004; // :181 PCRE2_NOTEMPTY
    pub const notempty_atstart: u32 = 0x0000_0008; // :182 PCRE2_NOTEMPTY_ATSTART
    pub const partial_soft: u32 = 0x0000_0010; // :183 PCRE2_PARTIAL_SOFT
    pub const partial_hard: u32 = 0x0000_0020; // :184 PCRE2_PARTIAL_HARD
    pub const dfa_restart: u32 = 0x0000_0040; // :185 PCRE2_DFA_RESTART
    pub const dfa_shortest: u32 = 0x0000_0080; // :186 PCRE2_DFA_SHORTEST
    pub const substitute_global: u32 = 0x0000_0100; // :187 PCRE2_SUBSTITUTE_GLOBAL
    pub const substitute_extended: u32 = 0x0000_0200; // :188 PCRE2_SUBSTITUTE_EXTENDED
    pub const substitute_unset_empty: u32 = 0x0000_0400; // :189 PCRE2_SUBSTITUTE_UNSET_EMPTY
    pub const substitute_unknown_unset: u32 = 0x0000_0800; // :190 PCRE2_SUBSTITUTE_UNKNOWN_UNSET
    pub const substitute_overflow_length: u32 = 0x0000_1000; // :191 PCRE2_SUBSTITUTE_OVERFLOW_LENGTH
    pub const no_jit: u32 = 0x0000_2000; // :192 PCRE2_NO_JIT
    pub const copy_matched_subject: u32 = 0x0000_4000; // :193 PCRE2_COPY_MATCHED_SUBJECT
    pub const substitute_literal: u32 = 0x0000_8000; // :194 PCRE2_SUBSTITUTE_LITERAL
    pub const substitute_matched: u32 = 0x0001_0000; // :195 PCRE2_SUBSTITUTE_MATCHED
    pub const substitute_replacement_only: u32 = 0x0002_0000; // :196 PCRE2_SUBSTITUTE_REPLACEMENT_ONLY
    pub const disable_recurseloop_check: u32 = 0x0004_0000; // :197 PCRE2_DISABLE_RECURSELOOP_CHECK
    pub const endanchored: u32 = 0x2000_0000; // :104 PCRE2_ENDANCHORED
    pub const no_utf_check: u32 = 0x4000_0000; // :103 PCRE2_NO_UTF_CHECK
    pub const anchored: u32 = 0x8000_0000; // :102 PCRE2_ANCHORED
};

/// Options for one backtracking match; defaults match from offset zero.
pub const MatchOptions = packed struct {
    notbol: bool = false,
    noteol: bool = false,
    notempty: bool = false,
    notempty_atstart: bool = false,
    /// Soft mode prefers a complete match; hard mode returns a partial match immediately.
    /// Partial matches return `PCRE2_ERROR_PARTIAL`; inspect `ovector` for their range.
    partial_soft: bool = false,
    partial_hard: bool = false,
    /// Disables JIT for this call; it has no effect in this JIT-disabled build.
    no_jit: bool = false,
    /// Makes PCRE2 copy the subject into match data until the next match or deinit.
    /// The returned `MatchData.subject` still borrows the caller's slice.
    copy_matched_subject: bool = false,
    disable_recurseloop_check: bool = false,
    endanchored: bool = false,
    no_utf_check: bool = false,
    anchored: bool = false,

    /// The 32-bit word `pcre2_match_N` expects.
    pub inline fn toBits(self: MatchOptions) u32 {
        var bits: u32 = 0;
        if (self.notbol) bits |= match_option.notbol;
        if (self.noteol) bits |= match_option.noteol;
        if (self.notempty) bits |= match_option.notempty;
        if (self.notempty_atstart) bits |= match_option.notempty_atstart;
        if (self.partial_soft) bits |= match_option.partial_soft;
        if (self.partial_hard) bits |= match_option.partial_hard;
        if (self.no_jit) bits |= match_option.no_jit;
        if (self.copy_matched_subject) bits |= match_option.copy_matched_subject;
        if (self.disable_recurseloop_check) bits |= match_option.disable_recurseloop_check;
        if (self.endanchored) bits |= match_option.endanchored;
        if (self.no_utf_check) bits |= match_option.no_utf_check;
        if (self.anchored) bits |= match_option.anchored;
        return bits;
    }
};

/// Options for one DFA match; only flags supported by the DFA matcher are exposed.
pub const DfaOptions = packed struct {
    notbol: bool = false,
    noteol: bool = false,
    notempty: bool = false,
    notempty_atstart: bool = false,
    partial_soft: bool = false,
    partial_hard: bool = false,
    /// Continues a partial match with the same workspace vector.
    restart: bool = false,
    /// Returns the shortest match rather than the longest.
    shortest: bool = false,
    endanchored: bool = false,
    no_utf_check: bool = false,

    pub inline fn toBits(self: DfaOptions) u32 {
        var bits: u32 = 0;
        if (self.notbol) bits |= match_option.notbol;
        if (self.noteol) bits |= match_option.noteol;
        if (self.notempty) bits |= match_option.notempty;
        if (self.notempty_atstart) bits |= match_option.notempty_atstart;
        if (self.partial_soft) bits |= match_option.partial_soft;
        if (self.partial_hard) bits |= match_option.partial_hard;
        if (self.restart) bits |= match_option.dfa_restart;
        if (self.shortest) bits |= match_option.dfa_shortest;
        if (self.endanchored) bits |= match_option.endanchored;
        if (self.no_utf_check) bits |= match_option.no_utf_check;
        return bits;
    }
};

/// Flags for substitution, including options used by its matching phase.
pub const SubstituteOptions = packed struct {
    /// `PCRE2_SUBSTITUTE_GLOBAL`: replace every match rather than only the
    /// first.
    global: bool = false,
    /// `PCRE2_SUBSTITUTE_EXTENDED`: the replacement may use `$1` and `${name}`.
    extended: bool = false,
    /// `PCRE2_SUBSTITUTE_UNSET_EMPTY`: a group that did not take part becomes
    /// the empty string instead of an error.
    unset_empty: bool = false,
    /// `PCRE2_SUBSTITUTE_UNKNOWN_UNSET`: a group name that does not exist is
    /// treated as unset rather than as an error.
    unknown_unset: bool = false,
    /// `PCRE2_SUBSTITUTE_OVERFLOW_LENGTH`: answer the length the result needs
    /// instead of writing it, which is how a caller sizes a buffer.
    overflow_length: bool = false,
    /// `PCRE2_SUBSTITUTE_LITERAL`: the replacement text is literal, so a `$`
    /// is a `$`.
    literal: bool = false,
    /// `PCRE2_SUBSTITUTE_MATCHED`: the replacement is the whole match that was
    /// found rather than the text given.
    matched: bool = false,
    /// `PCRE2_SUBSTITUTE_REPLACEMENT_ONLY`: return only the replacement
    /// strings, without the unmatched text around them.
    replacement_only: bool = false,
    notbol: bool = false,
    noteol: bool = false,
    notempty: bool = false,
    notempty_atstart: bool = false,
    anchored: bool = false,
    no_utf_check: bool = false,

    pub inline fn toBits(self: SubstituteOptions) u32 {
        var bits: u32 = 0;
        if (self.global) bits |= match_option.substitute_global;
        if (self.extended) bits |= match_option.substitute_extended;
        if (self.unset_empty) bits |= match_option.substitute_unset_empty;
        if (self.unknown_unset) bits |= match_option.substitute_unknown_unset;
        if (self.overflow_length) bits |= match_option.substitute_overflow_length;
        if (self.literal) bits |= match_option.substitute_literal;
        if (self.matched) bits |= match_option.substitute_matched;
        if (self.replacement_only) bits |= match_option.substitute_replacement_only;
        if (self.notbol) bits |= match_option.notbol;
        if (self.noteol) bits |= match_option.noteol;
        if (self.notempty) bits |= match_option.notempty;
        if (self.notempty_atstart) bits |= match_option.notempty_atstart;
        if (self.anchored) bits |= match_option.anchored;
        if (self.no_utf_check) bits |= match_option.no_utf_check;
        return bits;
    }
};

/// Pattern-conversion flags; the glob variants are cumulative.
/// `glob_no_wild_separator` and `glob_no_starstar` include `glob`.
pub const convert_option = struct {
    /// `PCRE2_CONVERT_POSIX_BASIC`: a POSIX basic regular expression.
    pub const posix_basic: u32 = 0x0000_0004; // :203
    /// `PCRE2_CONVERT_POSIX_EXTENDED`: a POSIX extended regular expression.
    pub const posix_extended: u32 = 0x0000_0008; // :204
    /// `PCRE2_CONVERT_GLOB`: a shell glob in which a wildcard crosses a path
    /// separator.
    pub const glob: u32 = 0x0000_0010; // :205
    /// `PCRE2_CONVERT_GLOB_NO_WILD_SEPARATOR`: a glob in which it does not.
    pub const glob_no_wild_separator: u32 = 0x0000_0030; // :206
    /// `PCRE2_CONVERT_GLOB_NO_STARSTAR`: a glob in which `**` does not either.
    pub const glob_no_starstar: u32 = 0x0000_0050; // :207
    /// `PCRE2_CONVERT_UTF`: the pattern is UTF and is checked before it is
    /// converted.
    pub const utf: u32 = 0x0000_0001; // :201
    /// `PCRE2_CONVERT_NO_UTF_CHECK`: skip that check.
    pub const no_utf_check: u32 = 0x0000_0002; // :202
};

/// Newline conventions accepted by `CompileContext.setNewline`; other values are refused.
pub const newline = struct {
    pub const cr: u32 = 1; // :213 PCRE2_NEWLINE_CR
    pub const lf: u32 = 2; // :214 PCRE2_NEWLINE_LF
    pub const crlf: u32 = 3; // :215 PCRE2_NEWLINE_CRLF
    pub const any: u32 = 4; // :216 PCRE2_NEWLINE_ANY
    pub const anycrlf: u32 = 5; // :217 PCRE2_NEWLINE_ANYCRLF
    pub const nul: u32 = 6; // :218 PCRE2_NEWLINE_NUL
};

/// Selects what `\\R` matches.
pub const bsr = struct {
    /// `PCRE2_BSR_UNICODE`: `\R` matches any Unicode newline sequence.
    pub const unicode: u32 = 1; // :220
    /// `PCRE2_BSR_ANYCRLF`: `\R` matches any single CR, LF or CRLF.
    pub const anycrlf: u32 = 2; // :221
};

/// Optimization directives accepted by `CompileContext.setOptimize`.
pub const optimization = struct {
    pub const none: u32 = 0; // :499 PCRE2_OPTIMIZATION_NONE
    pub const full: u32 = 1; // :500 PCRE2_OPTIMIZATION_FULL
    pub const auto_possess: u32 = 64; // :502 PCRE2_AUTO_POSSESS
    pub const auto_possess_off: u32 = 65; // :503 PCRE2_AUTO_POSSESS_OFF
    pub const dotstar_anchor: u32 = 66; // :504 PCRE2_DOTSTAR_ANCHOR
    pub const dotstar_anchor_off: u32 = 67; // :505 PCRE2_DOTSTAR_ANCHOR_OFF
    pub const start_optimize: u32 = 68; // :506 PCRE2_START_OPTIMIZE
    pub const start_optimize_off: u32 = 69; // :507 PCRE2_START_OPTIMIZE_OFF
};

/// The options `Regex.jitCompile` accepts, `src/pcre2.h.generic:167-171`.
pub const jit_option = struct {
    pub const complete: u32 = 0x0000_0001; // :167 PCRE2_JIT_COMPLETE
    pub const partial_soft: u32 = 0x0000_0002; // :168 PCRE2_JIT_PARTIAL_SOFT
    pub const partial_hard: u32 = 0x0000_0004; // :169 PCRE2_JIT_PARTIAL_HARD
    pub const invalid_utf: u32 = 0x0000_0100; // :170 PCRE2_JIT_INVALID_UTF
    /// Test-only allocation flag; PCRE2 returns `PCRE2_ERROR_JIT_UNSUPPORTED`.
    pub const test_alloc: u32 = 0x0000_0200; // :171
};

/// Case-change directions passed to substitution callbacks, not option bits.
pub const substitute_case = struct {
    pub const lower: u32 = 1; // :517 PCRE2_SUBSTITUTE_CASE_LOWER
    pub const upper: u32 = 2; // :518 PCRE2_SUBSTITUTE_CASE_UPPER
    pub const title_first: u32 = 3; // :519 PCRE2_SUBSTITUTE_CASE_TITLE_FIRST
};

/// Typed surface for the selected code-unit type.
/// A different width fails at compile time.
pub fn Width(comptime code_unit: type) type {
    if (code_unit != compiled_width.unit()) {
        @compileError(
            "pcre2: this build compiled the " ++ compiled_width.bits() ++
                "-bit library (PCRE2_CODE_UNIT_WIDTH on the translation line), " ++
                "so the declarations for " ++ @typeName(code_unit) ++ " in " ++
                "pcre2.h have no entry points behind them. Upstream ships the " ++
                "three widths as three separate libraries (doc/pcre2.txt:494-503) " ++
                "and none of them exports another width's names. Build the other " ++
                "width with -Dcode-unit-width=" ++ compiled_width.bits() ++ " to use it.",
        );
    }
    return struct {
        /// The one code-unit type this surface speaks.
        pub const CodeUnit = code_unit;
        /// Raw typed bindings for this width.
        pub const Raw = raw.Raw(code_unit);
        /// Translated opaque types and callback blocks for this width.
        pub const Types = Raw.Types;
        /// `PCRE2_SPTR<N>`.
        pub const SPtr = Raw.SPtr;
        /// `PCRE2_SIZE`, the type of every PCRE2 offset.
        pub const Size = Raw.Size;

        /// Name-table offsets are measured in code units; 8-bit entries use two.
        /// The other widths use one code unit per group number.
        const group_number_units: usize = switch (code_unit) {
            u8 => 2,
            u16, u32 => 1,
            else => @compileError(
                "pcre2: a name-table entry's group number is two code units at " ++
                    "width 8 and one at width 16 or 32 (src/pcre2_intmodedep.h:" ++
                    ":212-221), and this build selected none of the three.",
            ),
        };

        /// Decodes a group number from a name-table entry.
        inline fn group_number(entry: []const code_unit) u32 {
            return if (group_number_units == 2)
                (@as(u32, entry[0]) << 8) | @as(u32, entry[1])
            else
                @as(u32, entry[0]);
        }

        /// A callout callback, as the header declares it.
        pub const Callout = Raw.Callout;
        /// A callout-enumeration callback, which upstream never tests against
        /// null and therefore is not optional here either.
        pub const CalloutEnumerate = Raw.CalloutEnumerate;
        pub const SubstituteCallout = Raw.SubstituteCallout;
        pub const SubstituteCaseCallout = Raw.SubstituteCaseCallout;
        pub const RecursionGuard = Raw.RecursionGuard;
        pub const JitCallback = Raw.JitCallback;
        pub const Allocate = Raw.Allocate;
        pub const Deallocate = Raw.Deallocate;

        /// PCRE2 error text in a fixed buffer; `len` excludes the terminating NUL.
        /// Truncation fills the buffer to its last non-NUL code unit.
        pub const Text = struct {
            bytes: [diagnostic_buffer_size]code_unit = @splat(0),
            len: usize = 0,

            /// The message, without the terminating NUL.
            pub inline fn slice(self: *const Text) []const code_unit {
                return self.bytes[0..self.len];
            }
        };

        /// PCRE2's own text for one error number.
        pub fn diagnostic(code: i32) Text {
            var text: Text = .{};
            const written = Raw.get_error_message(code, &text.bytes, text.bytes.len);
            if (written < 0) {
                // Negative return means PCRE2 filled the buffer and truncated the message.
                text.len = text.bytes.len - 1;
                return text;
            }
            text.len = @intCast(written);
            return text;
        }

        /// Writes the library version into caller-owned storage and returns a borrowed slice.
        /// Returns `VersionBufferTooSmall` if the buffer cannot include the NUL.
        pub fn version(buffer: []code_unit) Error![:0]const code_unit {
            // A null output pointer makes this a size query and leaves `buffer` untouched.
            const required = Raw.config(@intCast(c.PCRE2_CONFIG_VERSION), null);
            // A version query must return a positive byte count.
            if (required < 1) return error.VersionUnavailable;
            // The required size includes NUL; reject undersized buffers before writing.
            const required_capacity: usize = @intCast(required);
            if (buffer.len < required_capacity) return error.VersionBufferTooSmall;

            const written = Raw.config(@intCast(c.PCRE2_CONFIG_VERSION), buffer.ptr);
            if (written < 1) return error.VersionUnavailable;
            // Verify the returned length leaves an in-bounds NUL terminator.
            const length: usize = @intCast(written - 1);
            return buffer[0..length :0];
        }

        /// Capture range in code-unit offsets relative to the subject.
        /// UTF offsets count code units, not character indices.
        pub const Group = struct {
            start: usize,
            end: usize,
        };

        /// One entry of a pattern's name table.
        pub const Name = struct {
            /// The group number the name is bound to. Group numbers start at 1.
            number: u32,
            /// Pattern name borrowed in this width's code units, without a NUL terminator.
            /// Valid only while the compiled `Regex` lives.
            name: []const code_unit,
        };

        /// Compile error code, code-unit offset, and owned diagnostic text.
        /// Fields do not borrow from the compile call.
        pub const Rejection = struct {
            code: i32,
            offset: usize,
            text: Text,
        };

        /// Outcome of `Regex.compile`.
        pub const CompileOutcome = union(enum) {
            /// Owns the compiled PCRE2 block; release it with `Regex.deinit`.
            compiled: Regex,
            /// Upstream compile refusal with its error code, offset, and text.
            rejected: Rejection,
        };

        /// Match outcome distinguishes non-match, resource limits, UTF errors, and other failures.
        pub const MatchOutcome = union(enum) {
            /// One or more matches; participating captures are readable.
            /// An undersized offset vector returns `error.OvectorTooSmall`.
            matched: void,
            /// No match at or after the start offset; not an error.
            no_match: void,
            /// PCRE2 match limit was reached; the pattern may still match.
            match_limit: void,
            /// PCRE2 depth limit was reached.
            depth_limit: void,
            /// PCRE2 heap limit was reached.
            heap_limit: void,
            /// Invalid UTF input or a start offset outside a character boundary; `code` is PCRE2's value.
            /// `startOffset` identifies invalid input, but not a misaligned start offset.
            invalid_utf: struct { code: i32, text: Text },
            /// Other negative PCRE2 results, with the numeric code and diagnostic text.
            /// Partial matches return this arm; capture accessors remain unavailable.
            failed: struct { code: i32, text: Text },
        };

        /// DFA outcome; matched ranges remain in `MatchData.ovector`.
        pub const DfaOutcome = union(enum) {
            /// One or more matched substrings; `pairs` is the count.
            matched: struct { pairs: usize },
            /// No substring matched.
            no_match: void,
            /// The output vector filled before PCRE2 found all matching substrings.
            truncated: void,
            /// Other negative PCRE2 result, with its numeric code and text.
            failed: struct { code: i32, text: Text },
        };

        /// Outcome of `Regex.substitute`.
        pub const Substitution = union(enum) {
            /// Result borrows the caller's buffer; `substitutions` is the replacement count.
            written: struct { text: []const code_unit, substitutions: usize },
            /// Required output capacity including NUL; PCRE2 wrote nothing.
            overflow: usize,
            /// Negative PCRE2 result, with its numeric code and text.
            failed: struct { code: i32, text: Text },
        };

        /// Outcome of one JIT compile request.
        pub const JitOutcome = union(enum) {
            /// PCRE2 produced JIT code for this pattern.
            compiled: void,
            /// PCRE2 refusal code and text; JIT-disabled builds return `PCRE2_ERROR_JIT_BADOPTION`.
            refused: struct { code: i32, text: Text },
        };

        /// Owned allocator context used by PCRE2-allocated blocks.
        /// Release child blocks and contexts separately before this context.
        pub const GeneralContext = struct {
            /// PCRE2's own general-context block. `null` once `deinit` has run.
            raw: ?*Types.GeneralContext,

            /// Creates an upstream-default `malloc`/`free` context.
            pub fn init() Error!GeneralContext {
                const created = Raw.general_context_create(null, null, null) orelse
                    return error.OutOfMemory;
                return .{ .raw = created };
            }

            /// Creates a context using the supplied allocator pair; null uses `malloc` and `free`.
            /// `data` is passed unchanged; the deallocator must not require a size.
            pub fn create(
                allocate: Allocate,
                deallocate: Deallocate,
                data: ?*anyopaque,
            ) Error!GeneralContext {
                const created = Raw.general_context_create(allocate, deallocate, data) orelse
                    return error.OutOfMemory;
                return .{ .raw = created };
            }

            /// Copies the context and its allocator pair.
            pub fn copy(self: *const GeneralContext) Error!GeneralContext {
                const created = Raw.general_context_copy(self.raw) orelse
                    return error.OutOfMemory;
                return .{ .raw = created };
            }

            /// Frees this context, not its child blocks.
            /// Safe to call twice on the same value.
            pub fn deinit(self: *GeneralContext) void {
                Raw.general_context_free(self.raw);
                self.raw = null;
            }

            /// Builds locale tables owned by this context; release them with `freeTables`.
            /// Compiled patterns using the tables require them to stay alive.
            pub fn tables(self: *const GeneralContext) Error![*c]const u8 {
                return Raw.maketables(self.raw) orelse error.OutOfMemory;
            }

            /// Releases tables returned by `tables`.
            pub fn freeTables(self: *const GeneralContext, character_tables: [*c]const u8) void {
                Raw.maketables_free(self.raw, character_tables);
            }
        };

        /// Owned context for compile limits, newline, and extra flags.
        /// Its borrowed allocator context must outlive it; compiled patterns are independent.
        pub const CompileContext = struct {
            raw: ?*Types.CompileContext,
            /// Borrowed allocator context; this value does not release it.
            general: ?*const GeneralContext = null,

            pub fn create(general: ?*const GeneralContext) Error!CompileContext {
                const created = Raw.compile_context_create(if (general) |g| g.raw else null) orelse
                    return error.OutOfMemory;
                return .{ .raw = created, .general = general };
            }

            /// Copies the context and its settings.
            pub fn copy(self: *const CompileContext) Error!CompileContext {
                const created = Raw.compile_context_copy(self.raw) orelse
                    return error.OutOfMemory;
                return .{ .raw = created, .general = self.general };
            }

            /// Frees the context block and clears `raw`.
            pub fn deinit(self: *CompileContext) void {
                Raw.compile_context_free(self.raw);
                self.raw = null;
            }

            /// Sets the newline convention; unsupported values return `error.SettingRefused`.
            pub fn setNewline(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_newline(self.raw, value));
            }

            /// Sets which sequences `\R` matches.
            /// Unsupported values return `error.SettingRefused`.
            pub fn setBsr(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_bsr(self.raw, value));
            }

            /// Sets the compiler's pattern-nesting limit.
            /// Upstream accepts every value.
            pub fn setParensNestLimit(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_parens_nest_limit(self.raw, value));
            }

            /// An optimization directive, one of the `optimization` values.
            pub fn setOptimize(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_optimize(self.raw, value));
            }

            /// Applies `PCRE2_EXTRA_*` bits to every pattern compiled here.
            pub fn setCompileExtraOptions(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_compile_extra_options(self.raw, value));
            }

            /// Sets the longest variable-length lookbehind accepted by the compiler.
            pub fn setMaxVarlookbehind(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_max_varlookbehind(self.raw, value));
            }

            /// Sets the maximum pattern length in code units.
            pub fn setMaxPatternLength(self: *CompileContext, value: usize) Error!void {
                try checked(Raw.set_max_pattern_length(self.raw, value));
            }

            /// Sets maximum compiled length in code units; values below 1024 are refused.
            pub fn setMaxPatternCompiledLength(self: *CompileContext, value: usize) Error!void {
                try checked(Raw.set_max_pattern_compiled_length(self.raw, value));
            }

            /// Uses caller-owned character tables; keep them alive for compiled patterns.
            /// Different table pointers make patterns incompatible for serialization.
            pub fn setCharacterTables(self: *CompileContext, tables: [*c]const u8) Error!void {
                try checked(Raw.set_character_tables(self.raw, tables));
            }

            /// Installs a recursion guard; non-zero aborts with `PCRE2_ERROR_RECURSELOOP`.
            /// `data` is passed unchanged.
            pub fn setCompileRecursionGuard(
                self: *CompileContext,
                callback: RecursionGuard,
                data: ?*anyopaque,
            ) Error!void {
                try checked(Raw.set_compile_recursion_guard(self.raw, callback, data));
            }
        };

        /// Owned glob/POSIX conversion context; its borrowed allocator must outlive it.
        /// Controls the glob escape character and path separator.
        pub const ConvertContext = struct {
            raw: ?*Types.ConvertContext,
            general: ?*const GeneralContext = null,

            pub fn create(general: ?*const GeneralContext) Error!ConvertContext {
                const created = Raw.convert_context_create(if (general) |g| g.raw else null) orelse
                    return error.OutOfMemory;
                return .{ .raw = created, .general = general };
            }

            pub fn copy(self: *const ConvertContext) Error!ConvertContext {
                const created = Raw.convert_context_copy(self.raw) orelse
                    return error.OutOfMemory;
                return .{ .raw = created, .general = self.general };
            }

            pub fn deinit(self: *ConvertContext) void {
                Raw.convert_context_free(self.raw);
                self.raw = null;
            }

            /// Sets the code unit that escapes the next glob character.
            /// Unsupported values return `error.SettingRefused`.
            pub fn setGlobEscape(self: *ConvertContext, value: code_unit) Error!void {
                try checked(Raw.set_glob_escape(self.raw, @intCast(value)));
            }

            /// Sets the path separator for glob conversion.
            /// Only `/`, `\\`, and `.` are accepted.
            pub fn setGlobSeparator(self: *ConvertContext, value: code_unit) Error!void {
                try checked(Raw.set_glob_separator(self.raw, @intCast(value)));
            }

            /// Owns the NUL-terminated converted pattern; release it with `deinit`.
            /// This is pattern text, not a compiled PCRE2 block.
            pub const Converted = struct {
                bytes: ?[*c]code_unit = null,
                len: usize = 0,

                /// Returns the converted pattern without its NUL terminator.
                /// Pass the slice and explicit length to `Regex.compile`.
                pub inline fn slice(self: *const Converted) []const code_unit {
                    return self.bytes.?[0..self.len];
                }

                /// Releases the block and clears its handle.
                pub fn deinit(self: *Converted) void {
                    if (self.bytes) |b| Raw.converted_pattern_free(b);
                    self.bytes = null;
                    self.len = 0;
                }
            };

            /// Converts a pattern into owned text or a rejection with code and offset.
            /// `len` excludes NUL; `OutOfMemory` reports allocation failure.
            pub fn convert(
                self: *const ConvertContext,
                pattern: []const code_unit,
                kind: u32,
                utf: bool,
            ) Error!union(enum) {
                converted: Converted,
                rejected: Rejection,
            } {
                var bits: u32 = kind;
                if (utf) bits |= convert_option.utf;

                var out: [*c]code_unit = null;
                var length: usize = 0;
                const rc = Raw.pattern_convert(
                    pattern.ptr,
                    pattern.len,
                    bits,
                    &out,
                    &length,
                    self.raw,
                );
                if (rc < 0) {
                    // `pcre2_convert.c` writes the error offset into the
                    // out-parameter on every failure path, so `length` is the
                    // offset and not a length here.
                    return .{ .rejected = .{
                        .code = rc,
                        .offset = length,
                        .text = diagnostic(rc),
                    } };
                }
                if (out == null) return error.OutOfMemory;
                return .{ .converted = .{ .bytes = out, .len = length } };
            }
        };

        /// Owned resource limits and callbacks for matching.
        /// Keep callback data and allocator contexts alive through this context.
        pub const MatchContext = struct {
            raw: ?*Types.MatchContext,
            general: ?*const GeneralContext = null,

            /// Creates a match context with PCRE2 defaults.
            /// Returns `OutOfMemory` if allocation fails.
            pub fn init() Error!MatchContext {
                const created = Raw.match_context_create(null) orelse
                    return error.OutOfMemory;
                return .{ .raw = created };
            }

            /// Creates a match context using `general` for its allocations.
            pub fn create(general: ?*const GeneralContext) Error!MatchContext {
                const created = Raw.match_context_create(
                    if (general) |g| g.raw else null,
                ) orelse return error.OutOfMemory;
                return .{ .raw = created, .general = general };
            }

            /// Copies the context and its settings.
            pub fn copy(self: *const MatchContext) Error!MatchContext {
                const created = Raw.match_context_copy(self.raw) orelse
                    return error.OutOfMemory;
                return .{ .raw = created, .general = self.general };
            }

            /// Frees the context block and clears `raw`.
            pub fn deinit(self: *MatchContext) void {
                Raw.match_context_free(self.raw);
                self.raw = null;
            }

            /// Sets the matcher work limit; reaching it yields `MatchOutcome.match_limit`.
            /// Unanchored patterns restart the limit at each start position.
            pub inline fn setMatchLimit(self: *MatchContext, limit: u32) void {
                _ = Raw.set_match_limit(self.raw.?, limit);
            }

            /// Sets the recursion-depth limit.
            pub inline fn setDepthLimit(self: *MatchContext, limit: u32) void {
                _ = Raw.set_depth_limit(self.raw.?, limit);
            }

            /// Sets the heap-frame limit; reaching it yields `MatchOutcome.heap_limit`.
            pub inline fn setHeapLimit(self: *MatchContext, limit: u32) void {
                _ = Raw.set_heap_limit(self.raw.?, limit);
            }

            /// Sets where `PCRE2_USE_OFFSET_LIMIT` begins applying; any value is accepted.
            pub inline fn setOffsetLimit(self: *MatchContext, limit: usize) void {
                _ = Raw.set_offset_limit(self.raw.?, limit);
            }

            /// Sets the deprecated alias for the depth limit.
            pub inline fn setRecursionLimit(self: *MatchContext, limit: u32) void {
                _ = Raw.set_recursion_limit(self.raw.?, limit);
            }

            /// Sets the deprecated recursion allocator; upstream ignores the callbacks.
            pub fn setRecursionMemoryManagement(
                self: *MatchContext,
                allocate: Allocate,
                deallocate: Deallocate,
                data: ?*anyopaque,
            ) Error!void {
                try checked(Raw.set_recursion_memory_management(
                    self.raw,
                    allocate,
                    deallocate,
                    data,
                ));
            }

            /// Installs a callback and `data`, which PCRE2 borrows until context release.
            /// Return zero to continue, positive to reject this start, or negative to abort.
            pub fn setCallout(
                self: *MatchContext,
                callback: Callout,
                data: ?*anyopaque,
            ) Error!void {
                try checked(Raw.set_callout(self.raw, callback, data));
            }

            /// Installs a substitution callback; callback and data remain borrowed.
            pub fn setSubstituteCallout(
                self: *MatchContext,
                callback: SubstituteCallout,
                data: ?*anyopaque,
            ) Error!void {
                try checked(Raw.set_substitute_callout(self.raw, callback, data));
            }

            /// Installs a replacement-text callback; callback and data remain borrowed.
            pub fn setSubstituteCaseCallout(
                self: *MatchContext,
                callback: SubstituteCaseCallout,
                data: ?*anyopaque,
            ) Error!void {
                try checked(Raw.set_substitute_case_callout(self.raw, callback, data));
            }

            /// Selects a JIT stack per attempt; null uses PCRE2's internal stack.
            /// Returned stacks remain caller-owned.
            pub fn setJitStack(
                self: *MatchContext,
                callback: JitCallback,
                data: ?*anyopaque,
            ) void {
                Raw.jit_stack_assign(self.raw, callback, data);
            }
        };

        // PCRE2 setters return zero on success and BADDATA on refusal.
        fn checked(rc: c_int) Error!void {
            if (rc != 0) return error.SettingRefused;
        }

        /// Owned JIT stack; this build has no SLJIT support.
        /// `create` reports `JitUnsupported` when the library refuses the stack.
        pub const JitStack = struct {
            raw: ?*Types.JitStack,

            /// Creates a stack of at least `start` bytes, up to `maximum`.
            /// Returns `JitUnsupported` when JIT is unavailable.
            pub fn create(start: usize, maximum: usize) Error!JitStack {
                const created = Raw.jit_stack_create(start, maximum, null) orelse
                    return error.JitUnsupported;
                return .{ .raw = created };
            }

            /// Releases the stack and clears `raw`.
            pub fn deinit(self: *JitStack) void {
                Raw.jit_stack_free(self.raw);
                self.raw = null;
            }
        };

        /// Owned compiled pattern; source text is not retained.
        /// Release with `deinit`; do not copy the handle or edit cached metadata.
        pub const Regex = struct {
            /// Borrowed access to the compiled block owned and freed by this `Regex`.
            code: ?*Types.Code,
            /// Highest capture group number, excluding group 0.
            capture_count: u32,
            /// Number of named groups, not a group number.
            name_count: u32,
            /// Name-table entry size in code units; use `nameAt` to decode entries.
            name_entry_size: u32,
            /// Borrowed name-table pointer; use `nameAt` and `nameCount`.
            name_table: [*c]const code_unit,

            /// Compiles a pattern; malformed patterns are returned as `rejected`.
            /// Allocation failure returns `OutOfMemory`; the result is owned by `Regex`.
            pub fn compile(pattern: []const code_unit, options: CompileOptions) Error!CompileOutcome {
                return compileWith(pattern, options, null);
            }

            /// Compiles with borrowed context settings; the context is not retained.
            /// Pattern text is not retained; release the returned block with `deinit`.
            pub fn compileWith(
                pattern: []const code_unit,
                options: CompileOptions,
                context: ?*const CompileContext,
            ) Error!CompileOutcome {
                var code: i32 = 0;
                var offset: usize = 0;
                const compiled = Raw.compile(
                    pattern.ptr,
                    pattern.len,
                    options.toBits(),
                    &code,
                    &offset,
                    if (context) |ctx| ctx.raw else null,
                ) orelse {
                    // PCRE2 reports compile-time allocation failure as code 121.
                    if (code == 121) return error.OutOfMemory;
                    return .{ .rejected = .{
                        .code = code,
                        .offset = offset,
                        .text = diagnostic(code),
                    } };
                };
                return .{ .compiled = try fromRaw(compiled) };
            }

            /// Releases the compiled block and clears its handle.
            pub fn deinit(self: *Regex) void {
                Raw.code_free(self.code);
                self.code = null;
            }

            /// Highest capture group number; the full group count includes group 0.
            pub inline fn captureCount(self: *const Regex) u32 {
                return self.capture_count;
            }

            /// Number of names in the table; indices use name-table order.
            pub inline fn nameCount(self: *const Regex) u32 {
                return self.name_count;
            }

            /// Returns an entry by name-order index, or null when out of range.
            /// The name and group number borrow the compiled pattern.
            pub fn nameAt(self: *const Regex, index: u32) ?Name {
                if (index >= self.name_count) return null;
                const table = self.name_table;
                const size = self.name_entry_size;
                // Reject malformed entry sizes before multiplying or slicing.
                if (size < group_number_units + 1) return null;
                const base = @as(usize, index) * size;
                const entry = table[base..][0..size];
                const rest = entry[group_number_units..];
                const end = std.mem.indexOfScalar(code_unit, rest, 0) orelse rest.len;
                return .{ .number = group_number(entry), .name = rest[0..end] };
            }

            /// Returns a name bound to `number`, or null if the group is unnamed.
            /// The code-unit slice borrows the compiled pattern.
            pub fn nameForNumber(self: *const Regex, number: u32) ?[]const code_unit {
                var i: u32 = 0;
                while (i < self.name_count) : (i += 1) {
                    const entry = self.nameAt(i) orelse return null;
                    if (entry.number == number) return entry.name;
                }
                return null;
            }

            /// Returns the group number for `name`, or null if unknown or too long.
            pub fn numberForName(self: *const Regex, name: []const code_unit) ?u32 {
                if (name.len > max_name_length) return null;
                var buffer: [max_name_length + 1]code_unit = undefined;
                @memcpy(buffer[0..name.len], name);
                buffer[name.len] = 0;
                const number = Raw.substring_number_from_name(self.code.?, &buffer);
                if (number < 0) return null;
                return @intCast(number);
            }

            /// Returns the owned compiled block for raw PCRE2 calls; do not free it.
            pub inline fn raw(self: *const Regex) *const Types.Code {
                return self.code.?;
            }

            /// Copies the compiled block; the caller owns the copy.
            /// Character tables remain shared; use `copyWithTables` to copy them.
            pub fn copy(self: *const Regex) Error!Regex {
                const copied = Raw.code_copy(self.code) orelse return error.OutOfMemory;
                return fromRaw(copied);
            }

            /// Copies the compiled block and its character tables.
            pub fn copyWithTables(self: *const Regex) Error!Regex {
                const copied = Raw.code_copy_with_tables(self.code) orelse
                    return error.OutOfMemory;
                return fromRaw(copied);
            }

            /// Reads a `PCRE2_INFO_*` value as `u32`; use `nameTable` for pointers.
            pub fn infoU32(self: *const Regex, what: u32) Error!u32 {
                var value: u32 = 0;
                if (Raw.pattern_info(self.code, what, &value) != 0)
                    return error.PatternInfoUnavailable;
                return value;
            }

            /// Reads a `PCRE2_SIZE_*` value as `usize`.
            pub fn infoSize(self: *const Regex, what: u32) Error!usize {
                var value: usize = 0;
                if (Raw.pattern_info(self.code, what, &value) != 0)
                    return error.PatternInfoUnavailable;
                return value;
            }

            /// Returns PCRE2's name-table pointer, even when the pattern has no names.
            /// Use `nameCount` to test whether the table contains entries.
            pub fn nameTable(self: *const Regex) [*c]const code_unit {
                return self.name_table;
            }

            /// Matches `subject` from a code-unit offset; borrows subject and `MatchData`.
            /// `MatchData` must fit `captureCount()+1`; invalid sizes or offsets fail before matching.
            pub fn match(
                self: *const Regex,
                subject: []const code_unit,
                start_offset: usize,
                options: MatchOptions,
                match_data: *MatchData,
                mcontext: ?*MatchContext,
            ) Error!MatchOutcome {
                return self.attempt(
                    subject,
                    start_offset,
                    options,
                    match_data,
                    mcontext,
                    Raw.match,
                );
            }

            /// Runs the JIT match entry point; it does not fall back to interpreter matching.
            /// Without SLJIT, PCRE2 returns `PCRE2_ERROR_JIT_BADOPTION`.
            pub fn jitMatch(
                self: *const Regex,
                subject: []const code_unit,
                start_offset: usize,
                options: MatchOptions,
                match_data: *MatchData,
                mcontext: ?*MatchContext,
            ) Error!MatchOutcome {
                return self.attempt(
                    subject,
                    start_offset,
                    options,
                    match_data,
                    mcontext,
                    Raw.jit_match,
                );
            }

            /// Shares validation and execution between interpreter and JIT matching.
            fn attempt(
                self: *const Regex,
                subject: []const code_unit,
                start_offset: usize,
                options: MatchOptions,
                match_data: *MatchData,
                mcontext: ?*MatchContext,
                comptime matcher: anytype,
            ) Error!MatchOutcome {
                // Clear stale captures; PCRE2 leaves old offsets on failed attempts.
                match_data.matched = false;
                match_data.pairs = 0;
                match_data.subject = subject;

                // Check capacity before matching; pass a released block through to PCRE2.
                if (match_data.raw) |block| {
                    if (Raw.get_ovector_count(block) < self.capture_count + 1) {
                        return error.OvectorTooSmall;
                    }
                }

                // Reject an out-of-range start offset before PCRE2 reports BADOFFSET.
                if (start_offset > subject.len) return error.StartOffsetOutOfRange;

                const rc = matcher(
                    self.code,
                    subject.ptr,
                    subject.len,
                    start_offset,
                    options.toBits(),
                    match_data.raw,
                    if (mcontext) |m| m.raw else null,
                );
                if (rc >= 0) {
                    // Zero means the vector was too small; never expose partial offsets as a match.
                    if (rc == 0) return error.OvectorTooSmall;
                    match_data.matched = true;
                    match_data.pairs = @intCast(rc);
                    return .matched;
                }
                return switch (rc) {
                    -1 => .no_match, // PCRE2_ERROR_NOMATCH
                    -47 => .match_limit, // PCRE2_ERROR_MATCHLIMIT
                    -53 => .depth_limit, // PCRE2_ERROR_DEPTHLIMIT
                    -63 => .heap_limit, // PCRE2_ERROR_HEAPLIMIT
                    -28...-3, -36 => .{ .invalid_utf = .{ .code = rc, .text = diagnostic(rc) } },
                    else => .{ .failed = .{ .code = rc, .text = diagnostic(rc) } },
                };
            }

            /// Compiles JIT code; disabled builds return `PCRE2_ERROR_JIT_BADOPTION`.
            pub fn jitCompile(self: *const Regex, options: u32) Error!JitOutcome {
                const rc = Raw.jit_compile(self.code, options);
                if (rc == 0) return .compiled;
                return .{ .refused = .{ .code = rc, .text = diagnostic(rc) } };
            }

            /// Runs non-backtracking DFA matching; ranges land in `MatchData.ovector`, longest first.
            /// Caller owns `workspace`; too few entries return `DfaWorkspaceTooSmall`.
            pub fn dfa(
                self: *const Regex,
                subject: []const code_unit,
                start_offset: usize,
                options: DfaOptions,
                match_data: *MatchData,
                mcontext: ?*MatchContext,
                workspace: *DfaWorkspace,
            ) Error!DfaOutcome {
                // PCRE2 requires at least 20 caller-owned workspace entries.
                if (workspace.offsets.len < minimum_workspace)
                    return error.DfaWorkspaceTooSmall;
                const wscount = workspace.wscount(subject.len);
                if (start_offset > subject.len) return error.StartOffsetOutOfRange;
                match_data.matched = false;
                match_data.pairs = 0;
                match_data.subject = subject;

                const rc = Raw.dfa_match(
                    self.code,
                    subject.ptr,
                    subject.len,
                    start_offset,
                    options.toBits(),
                    match_data.raw,
                    if (mcontext) |m| m.raw else null,
                    workspace.offsets.ptr,
                    wscount,
                );
                // Zero means more matches existed; expose the filled longest ranges as truncated.
                if (rc == 0) {
                    match_data.matched = true;
                    match_data.pairs = match_data.captureCount();
                    return .truncated;
                }
                if (rc < 0) {
                    // NOMATCH is ordinary; preserve other negative PCRE2 codes in `failed`.
                    if (rc == -1) return .no_match;
                    return .{ .failed = .{ .code = rc, .text = diagnostic(rc) } };
                }
                match_data.matched = true;
                match_data.pairs = @intCast(rc);
                return .{ .matched = .{ .pairs = match_data.pairs } };
            }

            /// Writes replacements into caller's buffer; `written.text` borrows it.
            /// Overflow reports capacity including NUL; `matched` preserves prior captures, other modes do not.
            pub fn substitute(
                self: *const Regex,
                subject: []const code_unit,
                start_offset: usize,
                options: SubstituteOptions,
                replacement: []const code_unit,
                match_data: *MatchData,
                mcontext: ?*MatchContext,
                buffer: []code_unit,
            ) Error!Substitution {
                // Clear stale match state because PCRE2 stores the substitution count in this block.
                if (!options.matched) {
                    match_data.matched = false;
                    match_data.pairs = 0;
                    match_data.subject = subject;
                }
                if (start_offset > subject.len) return error.StartOffsetOutOfRange;
                var length: usize = buffer.len;
                const rc = Raw.substitute(
                    self.code,
                    subject.ptr,
                    subject.len,
                    start_offset,
                    options.toBits(),
                    match_data.raw,
                    if (mcontext) |m| m.raw else null,
                    replacement.ptr,
                    replacement.len,
                    buffer.ptr,
                    &length,
                );
                if (rc == 0 and length > buffer.len)
                    return error.SubstituteBufferTooSmall;
                if (rc >= 0) {
                    return .{ .written = .{
                        .text = buffer[0..length],
                        .substitutions = @intCast(rc),
                    } };
                }
                return switch (rc) {
                    // -48 reports required length with overflow mode, otherwise a buffer refusal.
                    -48 => if (options.overflow_length)
                        .{ .overflow = length }
                    else
                        return error.SubstituteBufferTooSmall,
                    else => .{ .failed = .{ .code = rc, .text = diagnostic(rc) } },
                };
            }

            /// Calls back for each pattern callout; nonzero callback results stop the walk.
            /// Callback and `data` are borrowed for the call; negative results return `PatternInfoUnavailable`.
            pub fn enumerateCallouts(
                self: *const Regex,
                callback: Raw.CalloutEnumerate,
                data: ?*anyopaque,
            ) Error!u32 {
                const rc = Raw.callout_enumerate(self.code, callback, data);
                if (rc < 0) return error.PatternInfoUnavailable;
                return @intCast(rc);
            }

            /// Serializes this pattern with optional additional blocks.
            /// PCRE2 owns the result; it survives this `Regex`, and mixed tables are refused.
            pub fn serialize(
                self: *const Regex,
                extra: []const ?*const Types.Code,
                scratch: []?*const Types.Code,
            ) Error!Serialized {
                // Check caller scratch for every pointer before serialization.
                const count = 1 + extra.len;
                if (scratch.len < count) return error.OvectorTooSmall;
                scratch[0] = self.code.?;
                for (extra, 0..) |code, i| scratch[i + 1] = code;

                var bytes: [*c]u8 = null;
                var size: usize = 0;
                const rc = Raw.serialize_encode(scratch.ptr, @intCast(count), &bytes, &size, null);
                if (rc == -48) return error.OutOfMemory; // PCRE2_ERROR_NOMEMORY
                if (rc < 0) return error.SerializationRefused;
                return .{ .bytes = bytes, .len = size };
            }

            /// Decodes serialized bytes into owned blocks; the caller releases each block.
            /// `all` must hold `count` pointers; short arrays and malformed streams return distinct errors.
            pub fn decode(
                bytes: []const u8,
                count: u32,
                all: []?*Types.Code,
                general: ?*const GeneralContext,
            ) Error!Regex {
                // Check output capacity before PCRE2 writes decoded pointers.
                if (all.len == 0 or @as(usize, count) > all.len) return error.OvectorTooSmall;
                @memset(all, null);
                const rc = Raw.serialize_decode(
                    all.ptr,
                    @intCast(count),
                    bytes.ptr,
                    if (general) |g| g.raw else null,
                );
                if (rc == -48) return error.OutOfMemory; // PCRE2_ERROR_NOMEMORY
                if (rc < 0) return error.SerializationRefused;
                const first = all[0] orelse return error.OutOfMemory;
                return fromRaw(first);
            }

            /// Returns the number of blocks in a valid stream.
            /// Malformed data returns `SerializationRefused`.
            pub fn serializedCodeCount(bytes: []const u8) Error!u32 {
                const count = Raw.serialize_get_number_of_codes(bytes.ptr);
                if (count < 0) return error.SerializationRefused;
                return @intCast(count);
            }
        };

        /// Owns PCRE2-allocated serialized bytes, independent of the source `Regex`.
        pub const Serialized = struct {
            bytes: ?[*c]u8 = null,
            len: usize = 0,

            /// Returns the serialized bytes.
            pub inline fn slice(self: *const Serialized) []const u8 {
                return self.bytes.?[0..self.len];
            }

            /// Releases the block and clears its handle.
            pub fn deinit(self: *Serialized) void {
                if (self.bytes) |b| Raw.serialize_free(b);
                self.bytes = null;
                self.len = 0;
            }
        };

        // Caches metadata required by the facade.
        fn fromRaw(code: *Types.Code) Error!Regex {
            var capture_count: u32 = 0;
            var name_count: u32 = 0;
            var name_entry_size: u32 = 0;
            // PCRE2 always returns a name-table pointer, even when the table is empty.
            var name_table: [*c]const code_unit = undefined;

            if (Raw.pattern_info(code, @intCast(c.PCRE2_INFO_CAPTURECOUNT), &capture_count) != 0)
                return failRaw(code, error.PatternInfoUnavailable);
            if (Raw.pattern_info(code, @intCast(c.PCRE2_INFO_NAMECOUNT), &name_count) != 0)
                return failRaw(code, error.PatternInfoUnavailable);
            if (Raw.pattern_info(code, @intCast(c.PCRE2_INFO_NAMEENTRYSIZE), &name_entry_size) != 0)
                return failRaw(code, error.PatternInfoUnavailable);
            if (Raw.pattern_info(code, @intCast(c.PCRE2_INFO_NAMETABLE), @ptrCast(&name_table)) != 0)
                return failRaw(code, error.PatternInfoUnavailable);
            return .{
                .code = code,
                .capture_count = capture_count,
                .name_count = name_count,
                .name_entry_size = name_entry_size,
                .name_table = name_table,
            };
        }

        // Frees a PCRE2 block when facade construction fails.
        fn failRaw(code: *Types.Code, err: Error) Error {
            Raw.code_free(code);
            return err;
        }

        /// Owned result block with PCRE2's offsets; subject and captures are borrowed.
        /// Release with `deinit`; do not copy the handle or match patterns that exceed its capacity.
        pub const MatchData = struct {
            /// Owned PCRE2 block; use facade methods unless calling raw APIs.
            /// Do not replace it while `matched` and `subject` describe its contents.
            raw: ?*Types.MatchData,
            /// Borrowed subject from the last match, DFA, or substitution; valid until the next call.
            /// Do not overwrite it; group access resolves offsets against this slice.
            subject: []const code_unit = &.{},
            /// True only when the last match wrote readable offsets; other attempts clear it.
            /// Substitution clears it except `matched` mode, which leaves the block unchanged.
            matched: bool = false,

            /// Number of offset pairs written by the last match, including group 0.
            /// Zero when `matched` is false; the count may be below capacity.
            pairs: u32 = 0,

            /// Creates a block sized for `regex`; errors are `OutOfMemory` or `OvectorTooSmall`.
            /// It can serve any pattern that fits; `Regex.match` checks capacity before matching.
            pub fn create(regex: *const Regex) Error!MatchData {
                const created = Raw.match_data_create_from_pattern(regex.code.?, null) orelse
                    return error.OutOfMemory;
                if (Raw.get_ovector_count(created) < regex.capture_count + 1) {
                    Raw.match_data_free(created);
                    return error.OvectorTooSmall;
                }
                return .{ .raw = created };
            }

            /// Creates a block with `ovecsize` offset pairs, optionally allocated by `general`.
            /// PCRE2 may clamp capacity; requests it cannot satisfy return `OvectorTooSmall`.
            pub fn createWithOvector(
                ovecsize: u32,
                general: ?*const GeneralContext,
            ) Error!MatchData {
                const created = Raw.match_data_create(
                    ovecsize,
                    if (general) |g| g.raw else null,
                ) orelse return error.OutOfMemory;
                if (Raw.get_ovector_count(created) < ovecsize) {
                    Raw.match_data_free(created);
                    return error.OvectorTooSmall;
                }
                return .{ .raw = created };
            }

            /// Releases the block and clears the handle.
            /// Do not copy the handle; copies share one allocation.
            pub fn deinit(self: *MatchData) void {
                Raw.match_data_free(self.raw);
                self.raw = null;
            }

            /// Number of offset pairs this block can hold, including group 0.
            pub inline fn captureCount(self: *const MatchData) u32 {
                return Raw.get_ovector_count(self.raw.?);
            }

            /// Returns a group's code-unit range, or null if it did not participate or the last attempt failed.
            /// An invalid group number returns `NoSuchGroup`.
            pub fn groupRange(self: *const MatchData, number: u32) Error!?Group {
                // Check the index first so invalid groups always return `NoSuchGroup`.
                if (number >= self.captureCount()) return error.NoSuchGroup;
                if (!self.matched) return null;
                const offsets = Raw.get_ovector_pointer(self.raw.?);
                const index = @as(usize, number) * 2;
                const start = offsets[index];
                const end = offsets[index + 1];
                if (start == unset or end == unset) return null;
                return .{ .start = start, .end = end };
            }

            /// Returns a capture slice borrowed from `subject`, or null when unavailable.
            /// Keep the subject alive and unchanged while using the slice.
            pub fn group(self: *const MatchData, number: u32) Error!?[]const code_unit {
                const range = (try self.groupRange(number)) orelse return null;
                return self.subject[range.start..range.end];
            }

            /// Returns PCRE2's start offset for matches, invalid UTF input, and partial matches.
            /// Other outcomes may leave zero or a prior value; do not infer `matched`.
            pub inline fn startOffset(self: *const MatchData) usize {
                return Raw.get_startchar(self.raw.?);
            }

            /// Returns PCRE2's offset vector for the last successful match.
            /// The pointer expires on the next attempt or `deinit`; other states return `SubstringUnavailable`.
            pub inline fn ovector(self: *const MatchData) Error![*c]usize {
                if (!self.matched) return error.SubstringUnavailable;
                return Raw.get_ovector_pointer(self.raw.?);
            }

            /// Returns the last successful MARK label, borrowed from the compiled pattern, or null.
            /// `\K` does not clear this label.
            pub fn mark(self: *const MatchData) Error!?[]const code_unit {
                if (!self.matched) return null;
                const pointer = Raw.get_mark(self.raw.?);
                if (pointer == null) return null;
                return std.mem.span(pointer);
            }

            /// Returns the PCRE2 match-data block size in bytes.
            pub inline fn size(self: *const MatchData) usize {
                return Raw.get_match_data_size(self.raw.?);
            }

            /// Returns PCRE2's heap-frame size in bytes; zero if no extra frames were retained.
            pub inline fn heapFramesSize(self: *const MatchData) usize {
                return Raw.get_match_data_heapframes_size(self.raw.?);
            }

            /// Returns an owned copy of capture `number`; unavailable captures return `SubstringUnavailable`.
            /// Release with `Owned.deinit`; PCRE2 allocates the copy.
            pub fn get(self: *const MatchData, number: u32) Error!Owned {
                if (number >= self.captureCount()) return error.NoSuchGroup;
                if (!self.matched) return error.SubstringUnavailable;
                var out: [*c]code_unit = null;
                var got: usize = 0;
                const rc = Raw.substring_get_bynumber(self.raw, number, &out, &got);
                if (rc < 0) return error.SubstringUnavailable;
                return .{ .bytes = out, .len = got };
            }

            /// Copies a capture into caller storage and returns its code-unit length.
            /// Buffer must hold the text and NUL or returns `SubstringBufferTooSmall` without writing.
            pub fn copy(self: *const MatchData, number: u32, buffer: []code_unit) Error!usize {
                if (number >= self.captureCount()) return error.NoSuchGroup;
                if (!self.matched) return error.SubstringUnavailable;
                var capacity: usize = buffer.len;
                const rc = Raw.substring_copy_bynumber(self.raw, number, buffer.ptr, &capacity);
                if (rc == -48) return error.SubstringBufferTooSmall; // PCRE2_ERROR_NOMEMORY
                if (rc < 0) return error.SubstringUnavailable;
                return capacity;
            }

            /// Returns all captures in group order as a PCRE2-owned NUL-separated list.
            /// Unset groups are empty strings; release with `SubstringList.deinit`.
            pub fn list(self: *const MatchData) Error!SubstringList {
                if (!self.matched) return error.SubstringUnavailable;
                var listp: [*c][*c]code_unit = undefined;
                var lensp: [*c]usize = undefined;
                const rc = Raw.substring_list_get(
                    self.raw,
                    &listp,
                    &lensp,
                );
                if (rc < 0) return error.SubstringUnavailable;
                return .{ .bytes = listp, .count = self.pairs, .lengths = lensp };
            }

            /// Advances match iteration; true updates `start_offset` and `options`, false leaves them unchanged.
            /// The start offset advances on every true result.
            pub fn next(self: *const MatchData, start_offset: *usize, options: *u32) bool {
                return Raw.next_match(self.raw, start_offset, options) != 0;
            }
        };

        /// Owns a capture allocated by PCRE2; release with `deinit`.
        /// Do not copy the handle.
        pub const Owned = struct {
            bytes: ?[*c]code_unit = null,
            len: usize = 0,

            pub inline fn slice(self: *const Owned) []const code_unit {
                return self.bytes.?[0..self.len];
            }

            pub fn deinit(self: *Owned) void {
                if (self.bytes) |b| Raw.substring_free(b);
                self.bytes = null;
                self.len = 0;
            }
        };

        /// Owns PCRE2's NUL-separated capture list; release with `deinit`.
        /// `bytes` is the allocation base; `lengths` has `count` entries.
        pub const SubstringList = struct {
            /// NUL-terminated capture-pointer array; cleared by `deinit`.
            bytes: ?[*c][*c]code_unit = null,
            /// Number of captures in the last match, equal to `MatchData.pairs`.
            count: u32 = 0,
            /// Capture lengths; read only indices below `count`.
            lengths: [*c]usize = null,

            /// Returns capture `index`, or null when `index >= count`; valid until `deinit`.
            pub fn get(self: *const SubstringList, index: u32) ?[]const code_unit {
                if (index >= self.count) return null;
                return self.bytes.?[index][0..self.lengths[index]];
            }

            pub fn deinit(self: *SubstringList) void {
                if (self.bytes) |b| Raw.substring_list_free(b);
                self.bytes = null;
                self.count = 0;
            }
        };

        /// Minimum accepted DFA workspace size; smaller buffers return `DfaWorkspaceTooSmall`.
        pub const minimum_workspace: usize = 20;

        /// Caller-owned DFA scratch; matched ranges are in `MatchData`, not this buffer.
        /// Reuse the buffer with `DfaOptions.restart`; PCRE2 owns no storage here.
        pub const DfaWorkspace = struct {
            /// Caller-owned scratch; restart state is stored here.
            offsets: []c_int,
            /// Returns `max(subject_len, minimum_workspace)` workspace entries.
            pub inline fn wscount(self: *const DfaWorkspace, subject_len: usize) usize {
                _ = self;
                return @max(subject_len, minimum_workspace);
            }
        };
    };
}
