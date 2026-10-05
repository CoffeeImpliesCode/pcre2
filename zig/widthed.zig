// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//
//! The typed surface of one PCRE2 code-unit width, and everything on it that
//! does not depend on which width it is.
//!
//! `pcre2.h` publishes three libraries through one header
//! (`src/pcre2.h.generic:1021-1031`), and `PCRE2_SUFFIX` (`:1064`) pastes the
//! width onto every exported name. So the difference between the three APIs is
//! only the code-unit type in a slice and the digits in a name, and this file
//! writes the surface once, generic over that type. `zig/raw.zig` is the layer
//! that turns a width into names; this file is everything above it.
//!
//! Nothing here reimplements matching. Every value a caller sees is either a
//! copy of something PCRE2 wrote into a buffer that belongs to the caller, or a
//! window on the caller's own subject through the offset vector PCRE2 filled.
//!
//! ## Widths and what a build has
//!
//! `compiled_width` is the width `build.zig` selected with `-Dcode-unit-width`,
//! read out of the translation rather than restated here. It says which width
//! the generic aliases, the primary artifact's name and the typed surface below
//! are about; the artifact itself is built from all three widths' unmodified
//! upstream sources, so it carries every width's entry points.
//!
//! `Width(u8)`, `Width(u16)` and `Width(u32)` all exist, because the header
//! declares all three. Only the selected one can be used: this file is a view
//! of the width the build was configured with, so asking for another is a
//! compile-time refusal naming the width that was compiled, at the point of
//! the mistake, rather than a link error or an uninitialised call much later.
//! The raw route through `pub const c` is where a caller that wants another
//! width's declarations goes; upstream itself ships `libpcre2-8`,
//! `libpcre2-16` and `libpcre2-32` as three separate libraries
//! (`doc/pcre2.txt:494-503`).

const std = @import("std");
const c = @import("c");
const raw = @import("raw.zig");

/// The three code-unit widths PCRE2 publishes, named as the digits
/// `PCRE2_SUFFIX` pastes onto every exported name.
///
/// `Width` below is a different thing and keeps that name: it is the typed
/// surface of one of these three, selected by its code-unit type. A width and
/// the surface a caller gets for it are separate answers and are named
/// separately.
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

/// The width this build compiled, read out of the translation.
///
/// `build.zig` puts `-DPCRE2_CODE_UNIT_WIDTH` on the translation line from the
/// same `-Dcode-unit-width` it puts on the C compile line (`addPcre2`,
/// `translate_c.defineCMacro`), and the translation step emits that macro as an
/// ordinary declaration: `pub const PCRE2_CODE_UNIT_WIDTH = @as(c_int, 8);`, at
/// `local://foundation-cross-test-pcre2-x86-windows-translate-preprocessed.log:1579`.
/// So this is the width of the library behind this module and not a property of
/// the header, which declares all three.
///
/// A route that does not carry the macro through to a declaration stops here
/// with a message naming it. That is deliberate: guessing the default width
/// would be right by accident and wrong by silence, and in a runtime-loading
/// build it would make `load` require the wrong provider's symbols.
pub const compiled_width: CodeUnitWidth = blk: {
    // Route-independent first: `translate.h` carries
    // `typedef char pcre2_translate_width[PCRE2_CODE_UNIT_WIDTH];` immediately
    // after the include, so the width is the length of that array whichever
    // front end read the header. The element is `char`, so this reads the
    // number of code units and not the size of one.
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
    /// A PCRE2 entry point ran out of memory. It arrives in two shapes and both
    /// mean the same thing.
    ///
    /// A NULL from an entry point that can only fail that way: the three such
    /// sites reached from here are `pcre2_compile.c` (which also reports this
    /// as compile error 121, "failed to allocate heap memory"),
    /// `pcre2_match_data.c:62` and `pcre2_context.c:188`.
    ///
    /// Or `PCRE2_ERROR_NOMEMORY`, -48, from the two serialization calls that
    /// answer it rather than returning NULL
    /// (`src/pcre2_serialize.c:108`, `:192`, `:221`). Every other refusal those
    /// two can give is `error.SerializationRefused`, so this name is not the
    /// way a mixed table set or a bad header arrives.
    OutOfMemory,
    /// PCRE2 refused a question about a compiled block that this facade
    /// believes it asked correctly.
    ///
    /// `pcre2_pattern_info_N` is the one reached at compile time, where a
    /// refusal means the metadata this facade reads once could not be read and
    /// the block is released rather than leaked; the named result is what is
    /// missing. Named for the missing result; it claims no cause, because this
    /// file did not establish one.
    ///
    /// `Regex.enumerateCallouts` reaches it too, for the negative answers
    /// `pcre2_callout_enumerate_N` can give: `PCRE2_ERROR_NULL` for a block that
    /// is not there, `PCRE2_ERROR_BADMAGIC` and `PCRE2_ERROR_BADMODE` for one
    /// that is not a compiled block of this width's mode
    /// (`src/pcre2_pattern_info.c:266-282`, and upstream's own assertions at
    /// `src/pcre2test_inc.h:6172-6181`), and whatever negative value the
    /// caller's callback chose to stop the walk with.
    PatternInfoUnavailable,
    /// The caller's start offset is past the end of the subject. Checked here
    /// before matching, because PCRE2 answers the same condition with
    /// `PCRE2_ERROR_BADOFFSET` (-33) from inside the matcher and the facade
    /// owns this bound as an ordinary comparison rather than an assertion.
    /// `Regex.match` makes it the second of its two pre-checks, after the one
    /// below, so a call that gets both wrong is told about the block first.
    StartOffsetOutOfRange,
    /// The requested group number is not below `MatchData.captureCount()`.
    /// PCRE2's own substring helpers would index its offset vector past the
    /// end, so the facade checks first and names the condition.
    NoSuchGroup,
    /// The caller's `MatchData` cannot hold this pattern's capture groups plus
    /// group 0. This block and pattern do not fit together. Upstream's answer
    /// to that is a return of zero: it fills as much of the vector as fitted
    /// and says only that something did not fit
    /// (`doc/html/pcre2api.html:3308-3312`, and the arithmetic behind it at
    /// `src/pcre2_match.c:8157-8158`), which is a match the caller cannot
    /// read. The facade refuses instead, before matching.
    ///
    /// The same name covers the other site, which is a different fact about
    /// the same bound: `pcre2_match_data_create_N` clamps the pair count to
    /// `UINT16_MAX` and imposes a floor of one
    /// (`src/pcre2_match_data.c:57-58`) and says nothing, so `MatchData.create`
    /// compares what it got against what that one pattern needs.
    ///
    /// And the two serialization entries, which are one bound rather than the
    /// same one. `pcre2_serialize_encode_N` and `pcre2_serialize_decode_N`
    /// each take a caller-owned array of block pointers and neither can see
    /// its length (`src/pcre2_serialize.c:94-96`, `:204`, `:243`), so
    /// `Regex.serialize` compares its `scratch` against the blocks it is about
    /// to hand upstream and `Regex.decode` compares its `all` against the
    /// `count` it was asked for.
    ///
    /// Either way the block is left holding no readable capture: `Regex.match`
    /// clears `MatchData.matched` before it checks, so a refusal is not a
    /// pause over the captures of an earlier attempt.
    OvectorTooSmall,
    /// `version`'s buffer is shorter than the size the library reports it
    /// needs. `pcre2_config_N` takes a `void *` and writes `1 + strlen(v)`
    /// code units into whatever that pointer is (`pcre2_config.c:241-242`), so
    /// it cannot know the capacity: the bound belongs to the caller, and this
    /// file compares against the required size before anything is written
    /// rather than finding out afterwards.
    VersionBufferTooSmall,
    /// The library declined the `PCRE2_CONFIG_VERSION` query instead of
    /// answering it. `pcre2_config_N` answers a request it does not recognise
    /// with `PCRE2_ERROR_BADOPTION`, -34 (`src/pcre2.h.generic:398`), which is
    /// the default of the switch it dispatches on (`pcre2_config.c:105-108`)
    /// and of the length query in front of it (`:73-78`). Substituting a
    /// placeholder string would report a release the archive was never built
    /// with, so the refusal is what this is.
    VersionUnavailable,
    /// One of the `pcre2_set_*` setters was given a value it does not accept.
    /// The setters that switch on their argument answer `PCRE2_ERROR_BADDATA`,
    /// -29, for anything outside it (`src/pcre2_context.c:362-376` for the
    /// newline convention, and the same shape for the bsr convention), and
    /// answer zero otherwise. The name is for the refusal, not for the value:
    /// this file did not classify the values, so it does not report one.
    SettingRefused,
    /// The buffer `Regex.substitute` was handed was too small for the result.
    /// `pcre2_substitute_N` copies through a macro that checks the room before
    /// every fragment and gives up with `PCRE2_ERROR_NOMEMORY`, -48, when
    /// there is not enough (`src/pcre2_substitute.c:638-656`, `:1771-1773`),
    /// leaving `*blength` at the `PCRE2_UNSET` it was reset to. Setting
    /// `SubstituteOptions.overflow_length` turns that same answer into the
    /// length the result needs, which is how `Substitution.overflow` is
    /// reported rather than this error.
    SubstituteBufferTooSmall,
    /// The buffer `Regex.dfa` was handed is below the workspace floor.
    /// `pcre2_dfa_match_N` uses the whole of it as scratch state for its own
    /// active and new blocks (`src/pcre2_dfa_match.c:605-606`) and refuses
    /// anything below `minimum_workspace` with `PCRE2_ERROR_DFA_WSSIZE`, -43
    /// (`src/pcre2_dfa_match.c:3437`), so the bound is checked here against the
    /// caller's own storage rather than left to arrive as a failure.
    /// `DfaWorkspace.wscount` already floors the count it passes; it cannot
    /// floor the buffer.
    DfaWorkspaceTooSmall,
    /// This build has no SLJIT, so a request for a JIT machine stack was
    /// refused. `deps/sljit` is an empty submodule, `SUPPORT_JIT` is 0 in the
    /// generated `config.h`, and `pcre2_jit_stack_create_N` answers NULL
    /// (`src/pcre2_jit_misc_inc.h:125-134`). That NULL is a refusal rather than
    /// a failed allocation, and the two arrive the same way, which is why both
    /// this name and `OutOfMemory` exist: only the caller's knowledge of the
    /// configuration tells them apart, and this module says which one it saw.
    JitUnsupported,
    /// PCRE2 refused to produce this substring.
    ///
    /// One of three things, all of them `pcre2_substring_length_bynumber_N`'s
    /// own answers (`src/pcre2_substring.c:312-333`): `PCRE2_ERROR_NOSUBSTRING`,
    /// -49, for a group the pattern does not declare, `PCRE2_ERROR_UNAVAILABLE`,
    /// -54, for one the block's offset vector is too small to index, and
    /// `PCRE2_ERROR_UNSET`, -55, for one that did not take part in the match
    /// (`src/pcre2.h.generic:413`, `:419-420`). A block whose last attempt did
    /// not match has no readable capture at all and is refused here before any
    /// of those is asked about. This name is for the condition, and the code is
    /// not reported rather than guessed.
    SubstringUnavailable,
    /// The caller's `buffer` was too small for the capture
    /// `MatchData.copy` was asked to put in it.
    ///
    /// `pcre2_substring_copy_bynumber_N` copies into the caller's own buffer,
    /// takes the room it has through `*sizeptr`, and answers
    /// `PCRE2_ERROR_NOMEMORY`, -48, when `size + 1` does not fit
    /// (`src/pcre2_substring.c:117-130`), without writing anything. The `+ 1`
    /// is the terminating null PCRE2 writes after the last code unit
    /// (`:127`), so a buffer that is exactly the capture's length is one short.
    SubstringBufferTooSmall,
    /// PCRE2 refused to build a stream from these blocks, or to read one from
    /// these bytes, and it did not do so by failing to allocate.
    ///
    /// One name for the refusals `pcre2_serialize_encode_N`,
    /// `pcre2_serialize_decode_N` and
    /// `pcre2_serialize_get_number_of_codes_N` can give, each of which is
    /// upstream's own negative return:
    ///
    ///   * `PCRE2_ERROR_MIXEDTABLES`, -30 -- two blocks whose character
    ///     tables are at different addresses, which upstream compares by
    ///     pointer (`src/pcre2_serialize.c:99-102`);
    ///   * `PCRE2_ERROR_BADMAGIC`, -31, and `PCRE2_ERROR_BADMODE`, -32 --
    ///     bytes that are not a stream of this version and width
    ///     (`:179-181`, `:273-275`);
    ///   * `PCRE2_ERROR_BADSERIALIZEDDATA`, -62 -- a stream whose header or
    ///     blocks do not describe what they must (`:178`, `:209-213`,
    ///     `:229-235`);
    ///   * `PCRE2_ERROR_BADDATA`, -29, for a count of zero or less (`:88`,
    ///     `:177`), and `PCRE2_ERROR_NULL`, -51, for a null argument
    ///     (`:85-86`, `:96`, `:176`).
    ///
    /// `error.OutOfMemory` is kept for `PCRE2_ERROR_NOMEMORY`, -48, which is
    /// the only allocation failure among them (`:108`, `:192`, `:221`), so the
    /// two are told apart by the caller. The name is for the refusal and not
    /// for which of those it was: this file did not classify them, and the
    /// numbers are upstream's own where they are needed.
    SerializationRefused,
};

/// `PCRE2_UNSET`, `src/pcre2.h.generic:539`: the value PCRE2 leaves in the
/// offset vector for a capturing group that did not take part in the match
/// (`pcre2_match.c:1036-1037`, `:1053`).
pub const unset: usize = ~@as(usize, 0);

/// The largest number of code units a diagnostic is kept in. Upstream's message
/// table (`src/pcre2_error.c`) is a packed list of short sentences; the longest
/// compile-time text is well under this. A message that would not fit is
/// truncated and the truncation is visible through `Text.len`.
pub const diagnostic_buffer_size = 128;

/// `MAX_NAME_SIZE` from the generated `config.h`, `src/config-cmake.h.in:53`.
/// `pcre2_compile.c:2671` rejects a longer group name at compile time, so a
/// name this long cannot belong to any pattern PCRE2 accepted.
pub const max_name_length = 128;

// ---------------------------------------------------------------------------
// Option bits
// ---------------------------------------------------------------------------

/// The compile-time option word, copied from `src/pcre2.h.generic:102-143`.
///
/// The names are the facade's; the values are upstream's, one line each. The
/// facade composes the 32-bit word from these and passes nothing else, so a
/// bit PCRE2 defines and this file does not name simply cannot be set through
/// the typed surface.
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

/// Options for `pcre2_compile_N`.
///
/// Every field defaults to false, so `.{ .{} }` is the upstream default
/// (no options at all) and a partial literal is valid. There is no `fromBits`:
/// the only direction this facade converts is from a caller's intent to
/// upstream's word, so a caller cannot smuggle in a bit this file does not
/// name.
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

/// The option bits of `pcre2_match_N`, `pcre2_dfa_match_N` and
/// `pcre2_substitute_N`, copied from `src/pcre2.h.generic:102-104` and
/// `:179-197`.
///
/// The three functions share one word and therefore one list, so the bits below
/// are named once and each of the three option structs picks the ones its own
/// function reads.
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

/// Options for one `Regex.match` call.
///
/// The defaults are the defaults, so `.{ .{} }` is an ordinary unanchored
/// match from offset zero over the whole subject.
pub const MatchOptions = packed struct {
    notbol: bool = false,
    noteol: bool = false,
    notempty: bool = false,
    notempty_atstart: bool = false,
    /// Ask for the best partial match rather than a refusal to report one.
    /// `partial_soft` keeps searching for a complete match and reports the
    /// partial one only if none is found; `partial_hard` overrides it and
    /// returns the partial one at once, preferring it to any alternative
    /// complete match (`doc/html/pcre2api.html:3179-3190`). Either one makes a
    /// partial attempt answer `MatchOutcome.failed` with code
    /// `PCRE2_ERROR_PARTIAL`, -2, and no readable capture: upstream writes
    /// only `ovector[0]` and `ovector[1]`, the part of the subject that did
    /// match (`doc/html/pcre2api.html:3282-3284`,
    /// `src/pcre2_match.c:8204-8209`), and this facade reports the code
    /// rather than a partial result. `startOffset()` carries that start; the
    /// end is reachable only through `MatchData.ovector()`.
    partial_soft: bool = false,
    partial_hard: bool = false,
    /// No effect here: this fork builds with JIT off, so there is no compiled
    /// JIT code for the matcher to be told not to use. Upstream still accepts
    /// the bit (`src/pcre2.h.generic:192`).
    no_jit: bool = false,
    /// Have PCRE2 keep its own copy of the subject in the match block
    /// (`src/pcre2_match.c:8165-8178`). That is a **native** allocation:
    /// PCRE2 frees it at the start of the next `match` on the same block
    /// (`:7110-7115`) or when the block is freed, and no Zig allocator is
    /// involved, so a leak checker cannot see it. `MatchData.subject` still
    /// holds the borrow of the caller's slice either way; this option changes
    /// what PCRE2 keeps internally, not what this facade hands back.
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

/// Options for one `Regex.dfa` call.
///
/// The DFA matcher does not capture and does not backtrack, so it reads two
/// bits of its own (`src/pcre2.h.generic:185-186`) and the shared ones it has
/// in common with the other matchers. The backtracking-only bits are left out:
/// a bit that names an option this function does not read is not an option here.
pub const DfaOptions = packed struct {
    notbol: bool = false,
    noteol: bool = false,
    notempty: bool = false,
    notempty_atstart: bool = false,
    partial_soft: bool = false,
    partial_hard: bool = false,
    /// `PCRE2_DFA_RESTART`: answer `PCRE2_ERROR_PARTIAL` for a partial match so
    /// the caller can add subject characters and continue with the same vector
    /// (`doc/pcre2.txt:4325-4331`). The workspace must then be the same vector
    /// as the previous call, which is the same `[]c_int` a caller passes here.
    restart: bool = false,
    /// `PCRE2_DFA_SHORTEST`: stop at the shortest match rather than the
    /// longest.
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

/// Options for one `Regex.substitute` call.
///
/// The substitution bits are `src/pcre2.h.generic:187-191` and `:194-196`, plus
/// the shared matcher bits `pcre2_substitute` also reads because it matches
/// first.
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

/// What `pcre2_pattern_convert_N` is asked to convert, from
/// `src/pcre2.h.generic:201-207`.
///
/// The three glob values are cumulative rather than independent: upstream
/// spells "a glob in which a wildcard does not cross a path separator" as
/// `PCRE2_CONVERT_GLOB` plus `0x20`, and `PCRE2_CONVERT_GLOB_NO_WILD_SEPARATOR`
/// is that sum, so a caller cannot ask for that behaviour without also asking
/// for a glob. `ConvertContext.convert` therefore takes the pattern kind as one
/// of the three whole values below and does not ask the caller to reproduce the
/// addition.
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

/// The newline conventions `CompileContext.setNewline` accepts,
/// `src/pcre2.h.generic:213-218`. Anything else is refused by the library with
/// `PCRE2_ERROR_BADDATA`.
pub const newline = struct {
    pub const cr: u32 = 1; // :213 PCRE2_NEWLINE_CR
    pub const lf: u32 = 2; // :214 PCRE2_NEWLINE_LF
    pub const crlf: u32 = 3; // :215 PCRE2_NEWLINE_CRLF
    pub const any: u32 = 4; // :216 PCRE2_NEWLINE_ANY
    pub const anycrlf: u32 = 5; // :217 PCRE2_NEWLINE_ANYCRLF
    pub const nul: u32 = 6; // :218 PCRE2_NEWLINE_NUL
};

/// What `\R` means, `src/pcre2.h.generic:220-221`.
pub const bsr = struct {
    /// `PCRE2_BSR_UNICODE`: `\R` matches any Unicode newline sequence.
    pub const unicode: u32 = 1; // :220
    /// `PCRE2_BSR_ANYCRLF`: `\R` matches any single CR, LF or CRLF.
    pub const anycrlf: u32 = 2; // :221
};

/// The directives `CompileContext.setOptimize` accepts,
/// `src/pcre2.h.generic:499-507`.
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
    /// `PCRE2_JIT_TEST_ALLOC`: exercised by upstream's own JIT allocator test,
    /// and answered `PCRE2_ERROR_JIT_UNSUPPORTED` in every build
    /// (`src/pcre2_jit_compile.c:14329-14335`). Present because the header
    /// declares it, not because a caller has a use for it.
    pub const test_alloc: u32 = 0x0000_0200; // :171
};

/// The case transformations a substitute-case callout is told to apply,
/// `src/pcre2.h.generic:517-519`. They are arguments to the callback, not bits
/// in the options word.
pub const substitute_case = struct {
    pub const lower: u32 = 1; // :517 PCRE2_SUBSTITUTE_CASE_LOWER
    pub const upper: u32 = 2; // :518 PCRE2_SUBSTITUTE_CASE_UPPER
    pub const title_first: u32 = 3; // :519 PCRE2_SUBSTITUTE_CASE_TITLE_FIRST
};

/// The typed surface of one code-unit width.
///
/// `code_unit` must be the width this build compiled, and the check is a
/// compile-time refusal rather than a run-time one: a caller that reaches for
/// the 16-bit surface in an 8-bit build has asked for a library that is not
/// there, and the honest answer is that at the point of the mistake rather than
/// a link error about a name they never typed.
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
        /// The width-generic raw bindings for it, so a caller that needs an
        /// entry point this facade does not wrap has the typed one rather than
        /// the transliterated name.
        pub const Raw = raw.Raw(code_unit);
        /// The opaque blocks and callback structures of this width, taken from
        /// the translation rather than restated, so a value of one is the same
        /// nominal type the header declares.
        pub const Types = Raw.Types;
        /// `PCRE2_SPTR<N>`.
        pub const SPtr = Raw.SPtr;
        /// `PCRE2_SIZE`, the type of every PCRE2 offset.
        pub const Size = Raw.Size;

        /// `IMM2_SIZE`, `src/pcre2_intmodedep.h:212-221`: how many code units one
        /// 16-bit immediate occupies at this width. Two in the 8-bit library,
        /// where `GET2` is a big-endian pair (`:214`), and one in the 16- and
        /// 32-bit libraries, where it is a single code unit (`:219`).
        ///
        /// It is here because it is the offset of the name inside a name-table
        /// entry, not because of how anything stores a group number: upstream
        /// reaches the name by adding `IMM2_SIZE` to a code-unit pointer
        /// (`src/pcre2_compile_cgroup.c:142-144`, `:167-175`, `:253-257`;
        /// `src/pcre2_substring.c:498-518`). Reading a 16- or 32-bit table as
        /// bytes, or advancing one by bytes, lands inside a code unit and names
        /// a different group every time.
        const group_number_units: usize = switch (code_unit) {
            u8 => 2,
            u16, u32 => 1,
            else => @compileError(
                "pcre2: a name-table entry's group number is two code units at " ++
                    "width 8 and one at width 16 or 32 (src/pcre2_intmodedep.h:" ++
                    ":212-221), and this build selected none of the three.",
            ),
        };

        /// `GET2(entry, 0)`: the group number at the front of a name-table entry,
        /// decoded at this width (`src/pcre2_intmodedep.h:214` and `:219`).
        /// `entry` is the whole entry, so this is in bounds once `nameAt` has
        /// checked the entry is at least `group_number_units` long.
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

        // ---- Diagnostics --------------------------------------------------

        /// A message copied out of PCRE2's own text, plus the number of code
        /// units that are actually message.
        ///
        /// `pcre2_get_error_message_N` returns the number of code units it
        /// wrote, excluding the terminating NUL (`pcre2_error.c:382-383`), so
        /// `slice()` is `bytes[0..len]`. A message too long for the buffer comes
        /// back as `PCRE2_ERROR_NOMEMORY` with `size - 1` code units written and
        /// truncated, and `len` is `size - 1` in that case, which is how a
        /// caller can tell that it was cut rather than complete.
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
                // The buffer was filled to `size - 1` and the call reported
                // PCRE2_ERROR_NOMEMORY, which is how upstream says the message
                // did not fit (`pcre2_error.c:363-370`). The text is still
                // usable; it is just the beginning of the sentence.
                text.len = text.bytes.len - 1;
                return text;
            }
            text.len = @intCast(written);
            return text;
        }

        /// The version string the library reports, written into `buffer` and
        /// returned as a window on it.
        ///
        /// The buffer belongs to the caller and so does the answer: the string
        /// and its terminating NUL are both written by the library into that
        /// storage, and the returned slice borrows it instead of anything this
        /// function owns. Upstream's advice for this code is the same shape,
        /// query the size first and then write into a buffer the caller sized
        /// (`doc/pcre2.txt:1466-1475`).
        ///
        /// This is the library answering, not a constant compiled into this
        /// file: `pcre2_config.c:236-243` formats the version out of the
        /// `PCRE2_MAJOR`, `PCRE2_MINOR`, `PCRE2_PRERELEASE` and `PCRE2_DATE`
        /// macros the rest of the C was built with, so it moves when the pin
        /// moves and cannot drift from the library this binary reached.
        ///
        /// Every release so far has needed no more than 24 code units
        /// (`doc/pcre2.txt:1468-1469`), so a buffer that size or larger cannot
        /// be too small for a real release; a caller that has to cope with
        /// anything wider sizes the buffer from what the first call asks for,
        /// which is the count this function compares against.
        ///
        /// The buffer is in code units, so for a 16- or 32-bit library the
        /// caller sizes it in those and not in bytes.
        pub fn version(buffer: []code_unit) Error![:0]const code_unit {
            // The `where == NULL` path is the size query: it returns
            // `1 + strlen(v)` and writes nothing at all
            // (`pcre2_config.c:73-103`, `:241-242`), so the caller's code units
            // are untouched by the time this function returns, whichever way
            // it returns.
            const required = Raw.config(@intCast(c.PCRE2_CONFIG_VERSION), null);
            // A string request cannot answer zero, because the count is
            // `1 + strlen` of a compile-time literal. Zero therefore means the
            // library declined in the same way a negative return does, and
            // neither is reported here as a version.
            if (required < 1) return error.VersionUnavailable;
            // The count is the string plus its terminating zero
            // (`pcre2_config.c:242`), so it is the whole capacity: a buffer of
            // exactly that many is enough and one code unit less is not.
            // Checked here, before the call that writes, because that call has
            // no way to know how big the buffer is.
            const required_capacity: usize = @intCast(required);
            if (buffer.len < required_capacity) return error.VersionBufferTooSmall;

            const written = Raw.config(@intCast(c.PCRE2_CONFIG_VERSION), buffer.ptr);
            if (written < 1) return error.VersionUnavailable;
            // `strcpy_c<N>` copied the string, wrote the zero after it
            // (`pcre2_string_utils.c:191-196`) and returned its length, which
            // is this count less one. The sentinel below is a check that the
            // code unit at that offset really is that zero rather than an
            // assumption about it, and the slice cannot reach past `buffer.len`
            // because the buffer was sized from the count this same call
            // returned.
            const length: usize = @intCast(written - 1);
            return buffer[0..length :0];
        }

        // ---- Results -------------------------------------------------------

        /// A capturing group's code-unit range inside the subject.
        ///
        /// Both ends are code-unit offsets from the start of the subject, which
        /// is what PCRE2's offset vector holds. For a pattern compiled with
        /// `PCRE2_UTF` these are code-unit offsets and not character indices,
        /// so a three-code-unit character advances `end` by three.
        pub const Group = struct {
            start: usize,
            end: usize,
        };

        /// One entry of a pattern's name table.
        pub const Name = struct {
            /// The group number the name is bound to. Group numbers start at 1.
            number: u32,
            /// The name, borrowed from the compiled block. It is not
            /// NUL-terminated in this slice and it is valid only while the
            /// `Regex` lives.
            ///
            /// Code units, not bytes: upstream writes the name out of the
            /// pattern with `memcpy(slot + IMM2_SIZE, name, CU2BYTES(length))`
            /// (`src/pcre2_compile_cgroup.c:168`), one name character per code
            /// unit of this width, so a 16- or 32-bit name is not a sequence of
            /// bytes at all and reading it as one misaligns every code unit
            /// after the first. `numberForName`'s argument is a NUL-terminated
            /// name in the same units, because `PCRE2_SPTR` is.
            name: []const code_unit,
        };

        /// A pattern upstream refused, with everything needed to point a user at
        /// it.
        ///
        /// Every field is upstream's own and none of it borrows: `text` owns its
        /// buffer inside the value, so a `Rejection` outlives the call that
        /// produced it and needs no release.
        pub const Rejection = struct {
            code: i32,
            offset: usize,
            text: Text,
        };

        /// What `Regex.compile` did.
        pub const CompileOutcome = union(enum) {
            /// The pattern compiled. Owns PCRE2's compiled block; release it
            /// with `Regex.deinit`.
            compiled: Regex,
            /// Upstream rejected the pattern. `code` is the number from the
            /// table at `src/pcre2_error.c` (compile errors are 100 plus an
            /// index, `src/pcre2_compile.h:53`) and `offset` is the code-unit
            /// offset in the pattern that upstream reported, which is the same
            /// offset `pcre2test` prints after "at offset".
            rejected: Rejection,
        };

        /// What one `Regex.match` call returned.
        ///
        /// A negative return from `pcre2_match_N` is not one condition. It is a
        /// non-match, or one of the resource ceilings, or a UTF validity
        /// failure, or something this facade does not model, and an attacker who
        /// can choose the subject needs to be able to tell those apart without
        /// reading a message string. The split is taken from
        /// `src/pcre2_error.c`'s table and from the call sites in
        /// `src/pcre2_match.c`.
        pub const MatchOutcome = union(enum) {
            /// The matcher returned one or more, and `MatchData.matched` is
            /// true. The two are the same fact: the tag is never returned
            /// without it, so a caller that reaches this arm can read the
            /// capture accessors, subject still to a group that did not take
            /// part answering null.
            ///
            /// A return of **zero** is upstream's truncated answer — it filled
            /// the offset vector as far as it went
            /// (`doc/html/pcre2api.html:3308-3312`, and the test for it at
            /// `src/pcre2_match.c:8157-8158`) — and it is not this tag.
            /// `Regex.match` refuses a block that cannot hold this pattern's
            /// groups plus group 0 with `error.OvectorTooSmall` before matching,
            /// and reports the zero as that same error rather than as a match
            /// nothing can read.
            matched: void,
            /// `PCRE2_ERROR_NOMATCH`, -1 (`src/pcre2.h.generic:350`). The
            /// pattern did not match at or after the requested start offset.
            /// This is the ordinary negative answer, not a failure, and it is
            /// not an error.
            no_match: void,
            /// `PCRE2_ERROR_MATCHLIMIT`, -47 (`:411`): the match context's
            /// match limit was reached. The pattern may well match; the work was
            /// refused.
            match_limit: void,
            /// `PCRE2_ERROR_DEPTHLIMIT`, -53 (`:417`): the match context's
            /// depth limit was reached.
            depth_limit: void,
            /// `PCRE2_ERROR_HEAPLIMIT`, -63 (`:428`): the match context's heap
            /// limit was reached.
            heap_limit: void,
            /// The subject is not valid UTF for a UTF pattern, or the start
            /// offset is not on a character boundary. `code` is upstream's own
            /// number: -3 to -23 for UTF-8, -24 to -26 for UTF-16, -27 to
            /// -28 for UTF-32, and -36 for a bad UTF start offset
            /// (`PCRE2_ERROR_UTF8_ERR1` through `PCRE2_ERROR_UTF32_ERR2`
            /// and `PCRE2_ERROR_BADUTFOFFSET`, src/pcre2.h.generic:355-400).
            ///
            /// The code-unit offset of the offending unit is in
            /// `MatchData.startOffset`, for the validity failures only:
            /// `pcre2_match.c:7270-7279` returns before writing that field when
            /// the start offset itself is on a continuation unit.
            invalid_utf: struct { code: i32, text: Text },
            /// Any other negative return, with upstream's number and its text,
            /// so nothing is flattened into a generic failure.
            ///
            /// One negative return arrives here that has its own meaning and no
            /// tag of its own: `PCRE2_ERROR_PARTIAL`, -2
            /// (`src/pcre2.h.generic:351`), which `MatchOptions.partial_soft`
            /// and `.partial_hard` ask for. Upstream wrote the partially matched
            /// part into `ovector[0]` and `ovector[1]` and the start into
            /// `startOffset` before returning it
            /// (`src/pcre2_match.c:8204-8209`); this union reports the code and
            /// leaves `MatchData.matched` false, so no capture is readable and
            /// the end of the partial is not reachable except through
            /// `MatchData.ovector()`. Match `code` against -2 rather than
            /// guessing from the tag, and do not read it as a plain failure.
            failed: struct { code: i32, text: Text },
        };

        /// What one `Regex.dfa` call returned.
        ///
        /// The DFA matcher does not capture and does not backtrack, so what it
        /// finds is a list of substrings rather than a set of groups. It writes
        /// the offsets into the caller's vector, longest match first
        /// (`doc/pcre2.txt:4352-4360`), and this facade reports the count
        /// rather than copying them out: they are code-unit offsets into the
        /// subject the caller passed, and they are read out of the block the
        /// matcher wrote through `MatchData.ovector`, two entries per pair.
        /// `DfaWorkspace` is only the matcher's scratch and has no accessor
        /// over its contents.
        pub const DfaOutcome = union(enum) {
            /// One or more matched substrings, the count upstream returned.
            matched: struct { pairs: usize },
            /// `PCRE2_ERROR_NOMATCH`, -1: nothing matched.
            no_match: void,
            /// A return of zero. The matcher found more substrings than the
            /// vector could hold and filled it with the longest ones
            /// (`doc/pcre2.txt:4359-4360`), so the vector is readable but not
            /// complete, and this is that answer rather than a failure.
            truncated: void,
            /// Any other negative return, with upstream's number and its text.
            failed: struct { code: i32, text: Text },
        };

        /// What one `Regex.substitute` call returned.
        pub const Substitution = union(enum) {
            /// The result is in `text`, which is a window on the caller's own
            /// buffer. `substitutions` is the number of replacements made,
            /// which is what `pcre2_substitute_N` returns on success
            /// (`src/pcre2_substitute.c:1757-1764`).
            written: struct { text: []const code_unit, substitutions: usize },
            /// `SubstituteOptions.overflow_length` was set and the call
            /// answered the length the result needs, including its terminating
            /// NUL, without writing anything
            /// (`src/pcre2_substitute.c:1746-1755`). `needed` is that length:
            /// size a buffer to it and call again without the overflow option.
            overflow: usize,
            /// Any negative return other than the overflow one, with upstream's
            /// number and its text.
            failed: struct { code: i32, text: Text },
        };

        /// What one `Regex.jitCompile` call returned.
        ///
        /// A separate type from `MatchOutcome` because the question is
        /// different: a JIT compile either produced machine code or refused,
        /// and a refusal is not a match that failed to match.
        pub const JitOutcome = union(enum) {
            /// The library produced JIT code for this pattern, and
            /// `Regex.jitMatch` will use it.
            compiled: void,
            /// The library refused, with upstream's number and its text. In a
            /// build without SLJIT this is always the answer, and the number is
            /// `PCRE2_ERROR_JIT_BADOPTION`, -45
            /// (`src/pcre2.h.generic:409`, `src/pcre2_jit_compile.c:14303-14432`).
            refused: struct { code: i32, text: Text },
        };

        // ---- General context: the allocator --------------------------------

        /// The allocator every other block in this library can be asked to come
        /// from, owned.
        ///
        /// **What owns what.** The general context owns itself and nothing
        /// else. A block created *through* it is allocated by `allocate` and
        /// released by `deallocate`, both of which are the caller's functions,
        /// and `deallocate` receives exactly the pointer `allocate` returned
        /// with exactly the size that call was given
        /// (`src/pcre2_context.c:120-159`). No Zig allocator is involved
        /// anywhere in this facade, and a Zig leak checker cannot see a block
        /// PCRE2 allocated: releasing it is a call the caller makes, through
        /// this module, on the block's own `deinit`.
        ///
        /// `init` is upstream's own `malloc` and `free`, which is what every
        /// other entry point here uses when it is given no context. `create` is
        /// how a caller substitutes their own pair, which is the only way to
        /// account for PCRE2's memory at all.
        ///
        /// One context is one owner and may be shared by any number of compile,
        /// match, convert and jit-stack contexts, each of which copies nothing
        /// of it: they hold the pointer, and the pointer stays valid until this
        /// context is released. `deinit` on a context that still has others
        /// pointing at it leaves those with a dangling allocator, which is the
        /// caller's ordering to get right; nothing here can detect it.
        pub const GeneralContext = struct {
            /// PCRE2's own general-context block. `null` once `deinit` has run.
            raw: ?*Types.GeneralContext,

            /// Upstream's allocator: `malloc` and `free`
            /// (`src/pcre2_context.c:120-159` for the null-function-pointer
            /// case).
            pub fn init() Error!GeneralContext {
                const created = Raw.general_context_create(null, null, null) orelse
                    return error.OutOfMemory;
                return .{ .raw = created };
            }

            /// A context that allocates through the caller's own pair.
            ///
            /// `allocate` and `deallocate` may both be null, which is upstream's
            /// `malloc` and `free`; `data` is whatever the pair needs and is
            /// handed back to each of them unchanged.
            ///
            /// A pair whose `deallocate` needs the size of the block is not a
            /// usable pair: PCRE2 gives it the size in the *allocation* call and
            /// not in the free call, so an allocator that requires the length in
            /// `free` cannot be plugged in here without a size this module has
            /// nowhere to keep.
            pub fn create(
                allocate: Allocate,
                deallocate: Deallocate,
                data: ?*anyopaque,
            ) Error!GeneralContext {
                const created = Raw.general_context_create(allocate, deallocate, data) orelse
                    return error.OutOfMemory;
                return .{ .raw = created };
            }

            /// A second, independent context over the same pair, for a caller
            /// that wants two blocks that release in either order.
            pub fn copy(self: *const GeneralContext) Error!GeneralContext {
                const created = Raw.general_context_copy(self.raw) orelse
                    return error.OutOfMemory;
                return .{ .raw = created };
            }

            /// Releases PCRE2's block and clears `raw`, so a second call on
            /// this value is the same no-op rather than a second free. Blocks
            /// allocated through this context are **not** released here: each
            /// is released by its own `deinit`.
            pub fn deinit(self: *GeneralContext) void {
                Raw.general_context_free(self.raw);
                self.raw = null;
            }

            /// 256 bytes of character tables built from the current locale,
            /// allocated by this context and released by `freeTables`.
            ///
            /// The buffer is the library's, not the caller's: `pcre2_maketables_N`
            /// allocates it through this context (`src/pcre2_maketables.c:94`)
            /// and `freeTables` hands it back, and nothing copies it. See
            /// `CompileContext.setCharacterTables`, which is the way to hand
            /// these bytes to a compile, and which keeps the pointer rather than
            /// the bytes -- so a block compiled with them needs them alive for
            /// as long as it is.
            pub fn tables(self: *const GeneralContext) Error![*c]const u8 {
                return Raw.maketables(self.raw) orelse error.OutOfMemory;
            }

            /// Releases tables `tables` returned, through the same context that
            /// produced them.
            pub fn freeTables(self: *const GeneralContext, character_tables: [*c]const u8) void {
                Raw.maketables_free(self.raw, character_tables);
            }
        };

        // ---- Compile context ----------------------------------------------

        /// How a pattern is compiled, owned.
        ///
        /// A compile context holds the limits, the newline convention and the
        /// extra option bits that apply to every pattern it compiles. It is
        /// created from a `GeneralContext` if the caller wants its memory
        /// accounted for, and from upstream's allocator if it does not; either
        /// way the block is the caller's and `deinit` releases it.
        ///
        /// One context is one owner and may be handed to any number of
        /// `Regex.compileWith` calls. `deinit` clears `raw` in the value it was
        /// called on, which makes a second call on that same value a no-op; a
        /// copy taken before it keeps the same pointer, and releasing both frees
        /// PCRE2's block twice.
        pub const CompileContext = struct {
            raw: ?*Types.CompileContext,
            /// The general context this one was created from, kept so a caller
            /// can see the ownership it just took on. Not released by `deinit`.
            general: ?*const GeneralContext = null,

            pub fn create(general: ?*const GeneralContext) Error!CompileContext {
                const created = Raw.compile_context_create(if (general) |g| g.raw else null) orelse
                    return error.OutOfMemory;
                return .{ .raw = created, .general = general };
            }

            /// A second, independent context holding the same settings.
            pub fn copy(self: *const CompileContext) Error!CompileContext {
                const created = Raw.compile_context_copy(self.raw) orelse
                    return error.OutOfMemory;
                return .{ .raw = created, .general = self.general };
            }

            /// Releases PCRE2's block and clears `raw`.
            pub fn deinit(self: *CompileContext) void {
                Raw.compile_context_free(self.raw);
                self.raw = null;
            }

            /// The newline convention, one of the `newline` values. Anything
            /// else is `error.SettingRefused`, because the library switches on
            /// the value and answers `PCRE2_ERROR_BADDATA`
            /// (`src/pcre2_context.c:362-376`).
            pub fn setNewline(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_newline(self.raw, value));
            }

            /// What `\R` means, one of the `bsr` values, with the same
            /// refusal for anything else.
            pub fn setBsr(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_bsr(self.raw, value));
            }

            /// The nesting limit the compiler enforces on the pattern itself.
            /// This one does not switch on its argument and always answers zero
            /// (`src/pcre2_context.c:355-360`), so it cannot fail; the `Error!`
            /// is there because every setter in this block has the same shape
            /// and a caller should not have to know which one checks.
            pub fn setParensNestLimit(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_parens_nest_limit(self.raw, value));
            }

            /// An optimization directive, one of the `optimization` values.
            pub fn setOptimize(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_optimize(self.raw, value));
            }

            /// Option bits applied to every pattern this context compiles,
            /// whatever `pcre2_compile` is given. These are the
            /// `PCRE2_EXTRA_*` bits (`src/pcre2.h.generic:147-163`), a second
            /// word, so they do not collide with the compile options this
            /// facade names.
            pub fn setCompileExtraOptions(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_compile_extra_options(self.raw, value));
            }

            /// The longest variable-length lookbehind the compiler accepts.
            pub fn setMaxVarlookbehind(self: *CompileContext, value: u32) Error!void {
                try checked(Raw.set_max_varlookbehind(self.raw, value));
            }

            /// The longest pattern the compiler accepts, in code units.
            pub fn setMaxPatternLength(self: *CompileContext, value: usize) Error!void {
                try checked(Raw.set_max_pattern_length(self.raw, value));
            }

            /// The largest compiled pattern the compiler will produce, in code
            /// units. Refused for a value below 1024
            /// (`src/pcre2_context.c:330-345`).
            pub fn setMaxPatternCompiledLength(self: *CompileContext, value: usize) Error!void {
                try checked(Raw.set_max_pattern_compiled_length(self.raw, value));
            }

            /// Use these 256 bytes as the character tables rather than the
            /// process locale's.
            ///
            /// **PCRE2 keeps the pointer, not a copy of the bytes.**
            /// `pcre2_set_character_tables_N` stores it as it was given
            /// (`src/pcre2_context.c:326-329`) and `pcre2_compile_N` stores that
            /// same pointer in the block it builds (`src/pcre2_compile.c:10451`,
            /// `:10960`), with no `PCRE2_DEREF_TABLES` flag, so nothing frees
            /// them at `pcre2_code_free` time either
            /// (`src/pcre2_compile.c:1146`). `tables` therefore has to stay
            /// valid for as long as every pattern compiled through this context,
            /// and is not released by anything here.
            ///
            /// Two blocks built from two different sets of tables are what
            /// upstream's `PCRE2_ERROR_MIXEDTABLES` is about, because it
            /// compares these pointers rather than their contents
            /// (`src/pcre2_serialize.c:99-102`).
            pub fn setCharacterTables(self: *CompileContext, tables: [*c]const u8) Error!void {
                try checked(Raw.set_character_tables(self.raw, tables));
            }

            /// A callback the compiler consults before it recurses further.
            /// Returning non-zero aborts the compile with
            /// `PCRE2_ERROR_RECURSELOOP`, -52 (`src/pcre2.h.generic:416`).
            /// `data` is handed back to the callback unchanged.
            pub fn setCompileRecursionGuard(
                self: *CompileContext,
                callback: RecursionGuard,
                data: ?*anyopaque,
            ) Error!void {
                try checked(Raw.set_compile_recursion_guard(self.raw, callback, data));
            }
        };

        // ---- Convert context ----------------------------------------------

        /// How a glob or a POSIX pattern is converted, owned.
        ///
        /// It exists for one setting: which character escapes the next one in a
        /// glob, and which character separates path components. `create`
        /// produces upstream's defaults, which is `\`` and `/`.
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

            /// The character that escapes the next one in a glob, as a code
            /// unit.
            ///
            /// **This can refuse.** Upstream takes anything up to 255 that is
            /// either zero or one of the glob punctuation characters its own
            /// table lists, and answers `PCRE2_ERROR_BADDATA`, -29, for
            /// anything else (`src/pcre2_context.c:537-554`), which is
            /// `error.SettingRefused`. The value is not classified here, which
            /// is what that name says.
            pub fn setGlobEscape(self: *ConvertContext, value: code_unit) Error!void {
                try checked(Raw.set_glob_escape(self.raw, @intCast(value)));
            }

            /// The character that separates path components, as a code unit.
            ///
            /// **This can refuse, too.** Upstream takes only `/`, `\` or `.`
            /// and answers `PCRE2_ERROR_BADDATA`, -29, for every other code
            /// unit (`src/pcre2_context.c:528-535`), which is
            /// `error.SettingRefused`.
            pub fn setGlobSeparator(self: *ConvertContext, value: code_unit) Error!void {
                try checked(Raw.set_glob_separator(self.raw, @intCast(value)));
            }

            /// A converted pattern, owned.
            ///
            /// This is *not* a compiled block. It is the pattern text
            /// `pcre2_pattern_convert_N` produced, which the caller then hands
            /// to `Regex.compile`. It carries a hidden header for the allocator
            /// that produced it, so it is released with
            /// `pcre2_converted_pattern_free_N` and by nothing else: not
            /// `pcre2_code_free`, and not a Zig allocator.
            pub const Converted = struct {
                bytes: ?[*c]code_unit = null,
                len: usize = 0,

                /// The converted pattern, in code units, owned by this value.
                ///
                /// The block PCRE2 allocated is NUL-terminated; this slice is the
                /// text and stops at the terminator without including it, because
                /// that is the count `pcre2_pattern_convert_N` reports: each
                /// converter writes the NUL into its output
                /// (`src/pcre2_convert.c:382`, `:1080`) and answers
                /// `convlength` and `out.output_size - 1` (`:381`, `:1092`)
                /// without it. Hand this to `Regex.compile`, which takes an
                /// explicit length; read the terminator only through a C call
                /// that wants one.
                pub inline fn slice(self: *const Converted) []const code_unit {
                    return self.bytes.?[0..self.len];
                }

                /// Releases the block and clears the handle, so a second call on
                /// this value is a no-op.
                pub fn deinit(self: *Converted) void {
                    if (self.bytes) |b| Raw.converted_pattern_free(b);
                    self.bytes = null;
                    self.len = 0;
                }
            };

            /// Convert `pattern` into PCRE2 pattern text.
            ///
            /// `kind` is one of `convert_option.glob`,
            /// `.glob_no_wild_separator`, `.glob_no_starstar`,
            /// `.posix_basic` or `.posix_extended`: exactly one of them, and the
            /// one that says what the pattern *is*. A rejection is a value, not
            /// an error, and carries upstream's number and the offset it
            /// reported; the only failure that is an error is the allocation
            /// for the result, which upstream reports as
            /// `PCRE2_ERROR_NOMEMORY`.
            ///
            /// The result is a block PCRE2 allocated and NUL-terminated, and
            /// `len` **excludes** that terminator: it is the count
            /// `pcre2_pattern_convert_N` reports, which the converters set from
            /// the text they wrote and before the NUL
            /// (`src/pcre2_convert.c:381-382` for a POSIX pattern, `:1092` for
            /// a glob). On a failure path `length` is the error offset instead,
            /// which is the only other thing the same out-parameter carries
            /// (`src/pcre2_convert.c:1164-1166`).
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

        // ---- Match context -------------------------------------------------

        /// The resource ceilings and the callout one match attempt runs under,
        /// owned.
        ///
        /// Without a context PCRE2 uses the compiled-in defaults from
        /// `src/config.h.generic:195` — `MATCH_LIMIT` of 10000000, with
        /// `MATCH_LIMIT_DEPTH` the same value (`:209`) and `HEAP_LIMIT` of
        /// 20000000 (`:169`) — which is upstream behaviour. Supplying one is how
        /// a caller bounds work on a subject an attacker chose, which is why the
        /// ceilings below are the real operations here rather than a
        /// convenience: `MatchOutcome` tells a match limit apart from no match
        /// precisely because the limit can be reached.
        ///
        /// One context is one owner and may be passed to any number of
        /// `Regex.match` calls and any number of patterns; nothing it holds
        /// refers to a particular match. A copy taken before `deinit` copies the
        /// pointer, and releasing both copies frees PCRE2's block twice, so it is
        /// not a second owner.
        ///
        /// **A callout and the ceilings are the same context.** PCRE2 holds one
        /// pointer, so installing a callout through `setCallout` and then
        /// borrowing the context into something else is the caller's ordering
        /// to get right; nothing here copies the block.
        pub const MatchContext = struct {
            raw: ?*Types.MatchContext,
            general: ?*const GeneralContext = null,

            /// Creates a context holding upstream's current defaults for every
            /// field.
            ///
            /// The only way this fails is the allocation in
            /// `pcre2_context.c:186-188`, and on that path nothing was
            /// allocated here and nothing is left to release.
            pub fn init() Error!MatchContext {
                const created = Raw.match_context_create(null) orelse
                    return error.OutOfMemory;
                return .{ .raw = created };
            }

            /// A context whose block comes from `general`, so a caller that
            /// wants PCRE2's match memory accounted for asks for it here.
            pub fn create(general: ?*const GeneralContext) Error!MatchContext {
                const created = Raw.match_context_create(
                    if (general) |g| g.raw else null,
                ) orelse return error.OutOfMemory;
                return .{ .raw = created, .general = general };
            }

            /// A second, independent context holding the same settings.
            pub fn copy(self: *const MatchContext) Error!MatchContext {
                const created = Raw.match_context_copy(self.raw) orelse
                    return error.OutOfMemory;
                return .{ .raw = created, .general = self.general };
            }

            /// Releases PCRE2's block and clears `raw`.
            pub fn deinit(self: *MatchContext) void {
                Raw.match_context_free(self.raw);
                self.raw = null;
            }

            /// Caps how many times the matcher goes round its main loop during
            /// one attempt; reaching it is `MatchOutcome.match_limit`. `limit`
            /// is that count and nothing else: for an unanchored pattern the
            /// count restarts at zero at each starting position, so it bounds
            /// total backtracking rather than the cost of one position
            /// (`doc/html/pcre2api.html:1222-1234`). Takes effect for every
            /// later attempt made with this context, not only the next one.
            pub inline fn setMatchLimit(self: *MatchContext, limit: u32) void {
                _ = Raw.set_match_limit(self.raw.?, limit);
            }

            /// Caps how deeply backtracking may nest during one attempt;
            /// reaching it is `MatchOutcome.depth_limit`.
            pub inline fn setDepthLimit(self: *MatchContext, limit: u32) void {
                _ = Raw.set_depth_limit(self.raw.?, limit);
            }

            /// Caps the heap frames one attempt may use; reaching it is
            /// `MatchOutcome.heap_limit`. Upstream's default is 20000000
            /// (`src/config.h.generic:168-169`).
            pub inline fn setHeapLimit(self: *MatchContext, limit: u32) void {
                _ = Raw.set_heap_limit(self.raw.?, limit);
            }

            /// The offset from which `PCRE2_USE_OFFSET_LIMIT` starts enforcing
            /// the match limit. `src/pcre2_context.c` accepts any value, so this
            /// one cannot fail either.
            pub inline fn setOffsetLimit(self: *MatchContext, limit: usize) void {
                _ = Raw.set_offset_limit(self.raw.?, limit);
            }

            /// The internal-recursion ceiling. Upstream keeps the name for
            /// compatibility with pre-8.0 code and maps it onto the depth limit
            /// (`src/pcre2_context.c:255-266`), so it is the same bound under
            /// the older name rather than a second one.
            pub inline fn setRecursionLimit(self: *MatchContext, limit: u32) void {
                _ = Raw.set_recursion_limit(self.raw.?, limit);
            }

            /// A per-context allocator for the matcher's internal recursion
            /// frames. Upstream keeps this for compatibility and **ignores** it
            /// (`src/pcre2_context.c:213-233` returns zero and changes
            /// nothing), so the pair this accepts is never called. It is here
            /// because the header declares it and because the answer is what a
            /// caller has to check to discover that.
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

            /// A callback invoked at each callout in a pattern.
            ///
            /// The callback receives PCRE2's own callout block, so it can see
            /// the capture vector as it stands, the subject, the position in
            /// the pattern and the callout's own flags.
            ///
            /// **Zero continues.** The matcher branches on the answer's sign
            /// (`src/pcre2_match.c:5989-5994`): zero carries on from just after
            /// the callout, a **positive** answer is `MATCH_NOMATCH` for this
            /// start position, so the matcher keeps bumping along and reports
            /// `PCRE2_ERROR_NOMATCH` unless a later position matches, and a
            /// **negative** answer abandons the attempt with that number as
            /// `pcre2_match_N`'s return. So returning non-zero is how a caller
            /// refuses a match it has decided against mid-way -- the positive
            /// form declines this position and keeps looking, the negative form
            /// stops -- and returning zero is the ordinary "go on".
            ///
            /// The callback and its `data` are the caller's and are **not**
            /// copied into the context: PCRE2 holds the two pointers and calls
            /// them for as long as the context lives. Whatever `data` points at
            /// must therefore outlive the context, and the callback must not
            /// free anything the context still holds.
            pub fn setCallout(
                self: *MatchContext,
                callback: Callout,
                data: ?*anyopaque,
            ) Error!void {
                try checked(Raw.set_callout(self.raw, callback, data));
            }

            /// A callback invoked for each substitution, with the same
            /// ownership rules as `setCallout`.
            pub fn setSubstituteCallout(
                self: *MatchContext,
                callback: SubstituteCallout,
                data: ?*anyopaque,
            ) Error!void {
                try checked(Raw.set_substitute_callout(self.raw, callback, data));
            }

            /// A callback that supplies the replacement text for one
            /// substitution, with the same ownership rules as `setCallout`.
            pub fn setSubstituteCaseCallout(
                self: *MatchContext,
                callback: SubstituteCaseCallout,
                data: ?*anyopaque,
            ) Error!void {
                try checked(Raw.set_substitute_case_callout(self.raw, callback, data));
            }

            /// A JIT machine stack, and the callback that supplies one per
            /// attempt.
            ///
            /// With no callback here, `pcre2_jit_match_N` uses the small block on
            /// its own stack. With one, the callback is asked before each
            /// attempt and may answer null to let PCRE2 use that block anyway.
            /// The stack the callback returns must be one the caller created
            /// and still owns; PCRE2 does not free it, and does not free it
            /// either when the context is released.
            pub fn setJitStack(
                self: *MatchContext,
                callback: JitCallback,
                data: ?*anyopaque,
            ) void {
                Raw.jit_stack_assign(self.raw, callback, data);
            }
        };

        /// Turn a `pcre2_set_*` answer into an error, or nothing.
        ///
        /// The setters answer zero for a value they took and
        /// `PCRE2_ERROR_BADDATA` for one they did not; nothing else is a
        /// refusal, and nothing here classifies the value that caused it.
        fn checked(rc: c_int) Error!void {
            if (rc != 0) return error.SettingRefused;
        }

        // ---- JIT stack ------------------------------------------------------

        /// A JIT machine stack, owned.
        ///
        /// **This build has no JIT.** `deps/sljit` is an empty submodule, so
        /// `SUPPORT_JIT` is 0 in the generated `config.h` and
        /// `pcre2_jit_stack_create_N` answers NULL
        /// (`src/pcre2_jit_misc_inc.h:125-134`). That NULL is a refusal rather
        /// than a failed allocation, which is what `error.JitUnsupported` says;
        /// the type exists so the callback a `MatchContext` takes has something
        /// to name, and so a caller finds out here rather than through a null
        /// pointer much later.
        pub const JitStack = struct {
            raw: ?*Types.JitStack,

            /// A stack of at least `start` bytes that can grow to `maximum`.
            ///
            /// Fails with `error.JitUnsupported` in a build without SLJIT and
            /// with `error.OutOfMemory` in one where the allocation failed; the
            /// two arrive as the same NULL upstream and are told apart by what
            /// the caller asked for, which is why both names exist.
            pub fn create(start: usize, maximum: usize) Error!JitStack {
                const created = Raw.jit_stack_create(start, maximum, null) orelse
                    return error.JitUnsupported;
                return .{ .raw = created };
            }

            /// Releases the stack and clears `raw`, so a second call on this
            /// value is a no-op.
            pub fn deinit(self: *JitStack) void {
                Raw.jit_stack_free(self.raw);
                self.raw = null;
            }
        };

        // ---- Compiled pattern ----------------------------------------------

        /// A compiled pattern, owned.
        ///
        /// Created by `compile`, `copy`, `deserialize` or `decode`, released by
        /// `deinit`, and valid in between. Nothing it exposes borrows the
        /// pattern text: the pattern is read during `compile` and not
        /// retained, so `pattern` may go out of scope immediately afterwards.
        ///
        /// Copying the struct copies the pointer. `deinit` takes a mutable
        /// pointer and clears the field it was called on, so a second call on
        /// that same value is a no-op; a copy made beforehand keeps the same
        /// pointer and is not made safe by the one being cleared, so there is
        /// one owner and it is the value `deinit` was called on.
        ///
        /// Cached `capture_count`, `name_count`, `name_entry_size` and
        /// `name_table` must remain consistent with `code`; direct writes are
        /// not supported.
        ///
        /// PCRE2 allocated the block and PCRE2 releases it: `pcre2_compile_N`
        /// uses `malloc` unless a `CompileContext` from a caller's general
        /// context is handed to `compileWith`, and in that case the block comes
        /// from that allocator instead. Either way it is this `deinit` that
        /// hands it back and no Zig allocator is involved, so a Zig leak checker
        /// cannot see it.
        pub const Regex = struct {
            /// PCRE2's own compiled block. `Regex.match` borrows it, `raw`
            /// hands it to an entry point this facade does not wrap, and
            /// `deinit` frees it. It is published for the first two of those;
            /// writing it is not a supported use. `null` once `deinit` has run,
            /// which is why the accessors below read it as non-null.
            code: ?*Types.Code,
            /// `PCRE2_INFO_CAPTURECOUNT` is `re->top_bracket`
            /// (`pcre2_pattern_info.c:136-137`): the highest group number, so a
            /// pattern with no capture groups has 0. `Regex.captureCount`
            /// excludes group 0; `MatchData.captureCount` includes it. Use the
            /// accessors.
            capture_count: u32,
            /// `PCRE2_INFO_NAMECOUNT` (`pcre2_pattern_info.c:225-227`): how many
            /// names the pattern declared, which is a table length and not a
            /// group number. Read through `nameCount`.
            name_count: u32,
            /// `PCRE2_INFO_NAMEENTRYSIZE` (`pcre2_pattern_info.c:221-223`): the
            /// size **in code units** of every entry in that table. Code units
            /// and not bytes, because the field it copies is declared "Size
            /// (code units) of table entries" (`src/pcre2_intmodedep.h:683`) and
            /// because upstream advances the table by it in code units
            /// (`src/pcre2_substring.c:492`, `:498`, `:509`, `:514`;
            /// `src/pcre2_compile_cgroup.c:160`, `:185`, `:224`;
            /// `src/pcre2_serialize.c:230`). The compiler sizes every entry from
            /// the longest name in the pattern (`src/pcre2_compile.c:5713-5716`),
            /// so the two widths' answers differ for the same pattern. Read
            /// through `nameAt`, which checks it.
            name_entry_size: u32,
            /// `PCRE2_INFO_NAMETABLE` (`pcre2_pattern_info.c:229-232`): the
            /// `PCRE2_SPTR` into the compiled block, which this value owns.
            ///
            /// Not optional because PCRE2 never answers null here: the switch
            /// has one arm for it, it is reached for every compiled block, and
            /// it returns an address computed from the block itself. A pattern
            /// with no names has an address too, and is already out of range for
            /// every `nameAt` index because `name_count` is 0.
            name_table: [*c]const code_unit,

            /// Compiles `pattern`.
            ///
            /// A rejection is a value, not an error: a malformed pattern is a
            /// fact about the pattern, and the caller usually wants the code and
            /// the offset to show the user. Only the two conditions that are not
            /// about the pattern become an error, and both are the same one.
            ///
            /// No allocator is involved on either path. The compiled block is
            /// allocated by PCRE2 with `malloc` and released by `deinit`.
            pub fn compile(pattern: []const code_unit, options: CompileOptions) Error!CompileOutcome {
                return compileWith(pattern, options, null);
            }

            /// Compiles `pattern` under `context`'s settings.
            ///
            /// The context is borrowed for the length of this call and is not
            /// retained: PCRE2 reads what it needs out of it during compilation
            /// and copies nothing of it into the block except the values it
            /// applies. A caller may therefore release the context as soon as
            /// this returns, and a pattern compiled here is independent of it.
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
                    // `pcre2_compile` returns NULL for exactly two reasons and
                    // sets *errorcode for both: a pattern diagnostic, and ERR21,
                    // which is 121, "failed to allocate heap memory"
                    // (`pcre2_compile.c:10780`, `:10811`, `:10947`; `ERRn == 100
                    // + n` by `src/pcre2_compile.h:53`).
                    if (code == 121) return error.OutOfMemory;
                    return .{ .rejected = .{
                        .code = code,
                        .offset = offset,
                        .text = diagnostic(code),
                    } };
                };
                return .{ .compiled = try fromRaw(compiled) };
            }

            /// Releases the compiled block. A second call does nothing.
            pub fn deinit(self: *Regex) void {
                Raw.code_free(self.code);
                self.code = null;
            }

            /// The highest capturing group number in the pattern, so there are
            /// `captureCount() + 1` groups counting group 0.
            pub inline fn captureCount(self: *const Regex) u32 {
                return self.capture_count;
            }

            /// How many names the pattern declared. PCRE2 keeps the table in
            /// name order, not group order and not the order the names were
            /// written in (`pcre2_compile_cgroup.c:106-108`, `:140-161`; the
            /// lookup at `pcre2_substring.c:495-523` binary-searches it), so this
            /// is the bound for `nameAt` and not a group number.
            pub inline fn nameCount(self: *const Regex) u32 {
                return self.name_count;
            }

            /// Name-table entry `index`, or null when `index` is past the table.
            ///
            /// `index` walks the table in name order, so it is not a group
            /// number and the numbers it produces need not ascend.
            ///
            /// One entry is `name_entry_size` **code units**: the group number
            /// in `group_number_units` of them, then the name in code units,
            /// then a NUL and zero padding out to the size the longest name in
            /// the pattern asked for (`src/pcre2_compile.c:5713-5716` sizes
            /// every entry that way; `src/pcre2_compile_cgroup.c:167-175`
            /// writes it, with the NUL and the padding fill at `:174-175`). The
            /// size therefore depends on the pattern and not on `index`, and the
            /// name is ended by the NUL inside the entry rather than by the end
            /// of the entry, which is what makes a name shorter than the
            /// longest one readable.
            pub fn nameAt(self: *const Regex, index: u32) ?Name {
                if (index >= self.name_count) return null;
                const table = self.name_table;
                const size = self.name_entry_size;
                // The floor for an entry this file can walk: the code units the
                // group number occupies, plus at least one code unit of name
                // after them. Upstream never produces a smaller one:
                // `src/pcre2_compile.c:5715-5716` sizes every entry to the
                // longest name in the pattern plus `IMM2_SIZE` plus one, and a
                // name is at least one character wide. But the walk below
                // multiplies by this value, so the bound is checked here rather
                // than left as a comment about what upstream does.
                if (size < group_number_units + 1) return null;
                const base = @as(usize, index) * size;
                const entry = table[base..][0..size];
                const rest = entry[group_number_units..];
                const end = std.mem.indexOfScalar(code_unit, rest, 0) orelse rest.len;
                return .{ .number = group_number(entry), .name = rest[0..end] };
            }

            /// The name bound to `number`, or null when the pattern declared no
            /// such name. This is a scan, because the table is in name order
            /// rather than in group order, so the answer is not at a position
            /// `number` can index into.
            ///
            /// The name is in code units and borrows the compiled block on the
            /// same terms as `Name.name`.
            pub fn nameForNumber(self: *const Regex, number: u32) ?[]const code_unit {
                var i: u32 = 0;
                while (i < self.name_count) : (i += 1) {
                    const entry = self.nameAt(i) orelse return null;
                    if (entry.number == number) return entry.name;
                }
                return null;
            }

            /// The group number `name` is bound to, or null when the pattern
            /// declared no such name. `pcre2_substring_number_from_name_N` takes
            /// a NUL-terminated name, so the caller's slice is copied into a
            /// stack buffer; a name longer than `max_name_length` is not a name
            /// of any pattern PCRE2 would have accepted
            /// (`pcre2_compile.c:2671`).
            pub fn numberForName(self: *const Regex, name: []const code_unit) ?u32 {
                if (name.len > max_name_length) return null;
                var buffer: [max_name_length + 1]code_unit = undefined;
                @memcpy(buffer[0..name.len], name);
                buffer[name.len] = 0;
                const number = Raw.substring_number_from_name(self.code.?, &buffer);
                if (number < 0) return null;
                return @intCast(number);
            }

            /// The compiled block, for a caller that needs an entry point this
            /// facade does not wrap: `pcre2_serialize_encode_N`, an enumeration
            /// of the raw callout block, or the raw declarations of a width this
            /// build did not compile.
            ///
            /// The pointer is const because that is how every PCRE2 entry point
            /// takes it except `pcre2_jit_compile_N`. It stays owned by this
            /// `Regex`; the caller must not free it.
            pub inline fn raw(self: *const Regex) *const Types.Code {
                return self.code.?;
            }

            /// A second compiled block from this one, sharing nothing but the
            /// character tables the process locale gave. The caller owns it and
            /// releases it with its own `deinit`.
            pub fn copy(self: *const Regex) Error!Regex {
                const copied = Raw.code_copy(self.code) orelse return error.OutOfMemory;
                return fromRaw(copied);
            }

            /// A second compiled block with the character tables copied too, so
            /// the copy does not depend on the locale that is current later.
            pub fn copyWithTables(self: *const Regex) Error!Regex {
                const copied = Raw.code_copy_with_tables(self.code) orelse
                    return error.OutOfMemory;
                return fromRaw(copied);
            }

            /// One of the `PCRE2_INFO_*` queries, as a `u32`.
            ///
            /// Every such query except `PCRE2_INFO_NAMETABLE` writes a `uint32_t`
            /// (`src/pcre2_pattern_info.c:120-232`), which is what this reads.
            /// `nameTable` is the one that does not, and it has its own accessor
            /// because reading it as a `u32` would be reading four bytes of a
            /// pointer as a number.
            pub fn infoU32(self: *const Regex, what: u32) Error!u32 {
                var value: u32 = 0;
                if (Raw.pattern_info(self.code, what, &value) != 0)
                    return error.PatternInfoUnavailable;
                return value;
            }

            /// One of the `PCRE2_SIZE_*` queries, as a `usize`.
            pub fn infoSize(self: *const Regex, what: u32) Error!usize {
                var value: usize = 0;
                if (Raw.pattern_info(self.code, what, &value) != 0)
                    return error.PatternInfoUnavailable;
                return value;
            }

            /// Where PCRE2's name table is, for a caller that wants the raw
            /// `pcre2_substring_nametable_scan_N` over it.
            ///
            /// This is `PCRE2_INFO_NAMETABLE` read as a `PCRE2_SPTR`, which is
            /// what that entry point takes as its table argument and what it
            /// walks in code units (`src/pcre2_substring.c:493`, `:498`).
            /// Not optional: upstream answers an address for every compiled
            /// block, including one whose pattern declared no names, because the
            /// table sits between the fixed part of the block and the compiled
            /// code whether or not there is anything in it
            /// (`src/pcre2_pattern_info.c:230-232`;
            /// `src/pcre2_compile.c:10985-10990`). `nameCount` is what says the
            /// table is empty.
            pub fn nameTable(self: *const Regex) [*c]const code_unit {
                return self.name_table;
            }

            /// Runs one match attempt over `subject` starting at `start_offset`
            /// and reports what it did. Whichever way the attempt ends,
            /// `match_data` is left describing **this** attempt and nothing else:
            /// `matched` is cleared and `subject` is set before anything else
            /// happens, including before either of the two refusals below.
            ///
            /// **The block must fit the pattern passed here.** A `MatchData` is
            /// sized once, by `MatchData.create`, and nothing in it records which
            /// pattern that was, so this call compares the block it was handed
            /// against `captureCount() + 1` for *this* `Regex` and refuses the
            /// pairing with `error.OvectorTooSmall` before matching. The count is
            /// read out of `raw` on every call, so a caller that installed a
            /// different block gets the bound measured against the one it
            /// installed. Upstream's own answer to the same condition is a
            /// return of zero (`doc/html/pcre2api.html:3308-3312`, decided at
            /// `src/pcre2_match.c:8157-8158`), which is a match whose tail is
            /// another attempt's offsets.
            ///
            /// `match_data` is the caller's and is never freed here; it may be
            /// reused for as many attempts as the caller likes. `mcontext` is
            /// optional; without one, PCRE2 uses the compiled-in defaults
            /// `MATCH_LIMIT` of 10000000 and `MATCH_LIMIT_DEPTH` equal to it
            /// (`src/config.h.generic:195` and `:209`), which is upstream
            /// behaviour and is what a caller who passes no context gets.
            ///
            /// The subject is borrowed, not copied, and the offsets in the
            /// outcome and in `match_data` are code-unit offsets into it.
            ///
            /// **What survives each failure.** `error.OvectorTooSmall` and
            /// `error.StartOffsetOutOfRange` both run before the matcher,
            /// capacity first. Both leave `matched` false and `subject` set, so
            /// no capture from the previous attempt remains readable. The native
            /// offset vector and `startOffset()` are not reset by these facade
            /// refusals. After a native failed attempt, PCRE2 also leaves the
            /// offset vector unchanged (`doc/html/pcre2api.html:3334`). Neither
            /// refusal changes what the caller owns. Every other negative return
            /// clears `matched` the same way, so `groupRange` and `group` answer
            /// null until an attempt matches.
            ///
            /// `MatchOutcome.matched` is never returned while `matched` is false:
            /// upstream's zero is reported as `error.OvectorTooSmall` instead, so
            /// a caller that reaches that arm can read every group the attempt
            /// used.
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

            /// The same attempt through `pcre2_jit_match_N`.
            ///
            /// **There is no fallback.** In a build without SLJIT the entry
            /// point is upstream's `#ifndef SUPPORT_JIT` body, and that body
            /// ignores every argument and answers
            /// `PCRE2_ERROR_JIT_BADOPTION`, -45
            /// (`src/pcre2_jit_match_inc.h:95-103`); it does not call
            /// `pcre2_match_N`. So in this build the answer is always
            /// `MatchOutcome.failed` with that number and no capture is
            /// readable. A build with SLJIT answers a real match, and a caller
            /// that wants the JIT path in one place does not have to branch on
            /// which configuration it is in.
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

            /// The shared body of `match` and `jitMatch`, so the two cannot
            /// differ in a precondition.
            fn attempt(
                self: *const Regex,
                subject: []const code_unit,
                start_offset: usize,
                options: MatchOptions,
                match_data: *MatchData,
                mcontext: ?*MatchContext,
                comptime matcher: anytype,
            ) Error!MatchOutcome {
                // The block now describes this attempt and nothing else,
                // including when the attempt is refused below: a block carries
                // no readable capture unless the attempt that last used it
                // matched. PCRE2 keeps the offset vector it wrote last time on
                // every path except the one that matched
                // (`src/pcre2_match.c:1045-1053`), so without this the next
                // caller could be handed offsets that belong to a subject it
                // never saw.
                match_data.matched = false;
                match_data.pairs = 0;
                match_data.subject = subject;

                // The pairing between this block and this pattern, checked
                // before the matcher runs. A `raw` of null is a released block,
                // which every accessor below already treats as out of contract;
                // it is passed through so the matcher answers it the way it
                // always has (`src/pcre2_match.c:7035`, `PCRE2_ERROR_NULL`)
                // rather than this call inventing a different failure -- or a
                // panic -- for it.
                if (match_data.raw) |block| {
                    if (Raw.get_ovector_count(block) < self.capture_count + 1) {
                        return error.OvectorTooSmall;
                    }
                }

                // Checked here rather than left to the matcher: PCRE2 would
                // answer the same condition with PCRE2_ERROR_BADOFFSET (-33),
                // and a bound the caller can trip by accident is worth naming as
                // a bound.
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
                    // A return of zero is upstream's way of saying the vector
                    // was too small: it fills as much of it as fitted and leaves
                    // the rest (`doc/html/pcre2api.html:3308-3312`, decided at
                    // `src/pcre2_match.c:8157-8158` from the highest group the
                    // attempt actually used), so the entries it did not write are
                    // still an earlier attempt's. The check above rules it out for
                    // a block that is this call's own, so this arm is the last
                    // thing standing between a truncated match and `.matched`; it
                    // answers with the same `OvectorTooSmall` rather than a tag
                    // no capture can be read from.
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

            /// Compiles JIT code for this pattern, or explains why it did not.
            ///
            /// This build has no SLJIT, so the answer is always `refused` with
            /// `PCRE2_ERROR_JIT_BADOPTION`, -45. The compiled-in JIT code is
            /// attached to the block PCRE2 owns, so there is nothing for the
            /// caller to release and `deinit` releases it with the block.
            pub fn jitCompile(self: *const Regex, options: u32) Error!JitOutcome {
                const rc = Raw.jit_compile(self.code, options);
                if (rc == 0) return .compiled;
                return .{ .refused = .{ .code = rc, .text = diagnostic(rc) } };
            }

            /// Runs one attempt with the DFA matcher, which does not capture and
            /// does not backtrack.
            ///
            /// **The matched ranges land in `match_data`, not in `workspace`.**
            /// `pcre2_dfa_match_N` hands its internal matcher the block's own
            /// offset vector as the output (`src/pcre2_dfa_match.c:4062-4063`),
            /// and upstream's own substring helpers read a DFA result out of
            /// that block (`src/pcre2_substring.c:334-341`). Read the pairs from
            /// `MatchData.ovector()`, two entries each, and read no capture-group
            /// semantics into them: this matcher has no groups
            /// (`doc/pcre2.txt:4340-4343`), so they are the matched substrings,
            /// **longest match first** (`doc/pcre2.txt:4352-4360`).
            ///
            /// `workspace` is the caller's scratch buffer and nothing else: the
            /// matcher fills it with its own active and new state blocks
            /// (`src/pcre2_dfa_match.c:605-606`) and what is left there
            /// afterwards is its business, which is why `DfaWorkspace` has no
            /// accessor over it.
            ///
            /// A buffer below `minimum_workspace` is
            /// `error.DfaWorkspaceTooSmall`, checked before the matcher runs.
            ///
            /// `match_data` is written by the matcher and holds the result. The
            /// block is still the caller's and is still never freed here.
            pub fn dfa(
                self: *const Regex,
                subject: []const code_unit,
                start_offset: usize,
                options: DfaOptions,
                match_data: *MatchData,
                mcontext: ?*MatchContext,
                workspace: *DfaWorkspace,
            ) Error!DfaOutcome {
                // The matcher writes pairs into the vector and has no way to
                // know how much room it has: upstream refuses a workspace
                // below its own floor of 20 with `PCRE2_ERROR_DFA_WSSIZE`, -43
                // (`src/pcre2_dfa_match.c:3437`). `wscount` above already floors
                // the count it passes, so this is the check on the caller's own
                // storage that `wscount` cannot make for it.
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
                // A zero return is upstream's way of saying the matcher found
                // more pairs than the block's vector could hold, so it filled the
                // vector with the longest ones and said so with a zero
                // (`src/pcre2_dfa_match.c:905-911`). That attempt did match, so
                // `MatchData.ovector()` has to be readable, and it holds as many
                // pairs as the block can take.
                if (rc == 0) {
                    match_data.matched = true;
                    match_data.pairs = match_data.captureCount();
                    return .truncated;
                }
                if (rc < 0) {
                    // `-1` is `PCRE2_ERROR_NOMATCH`, the ordinary negative
                    // answer and not a failure; anything else below zero is one
                    // of the ceilings or a condition this file does not
                    // classify, and it is reported with upstream's number.
                    if (rc == -1) return .no_match;
                    return .{ .failed = .{ .code = rc, .text = diagnostic(rc) } };
                }
                match_data.matched = true;
                match_data.pairs = @intCast(rc);
                return .{ .matched = .{ .pairs = match_data.pairs } };
            }

            /// Replaces matches in `subject` into `buffer`.
            ///
            /// `replacement` is in the simple syntax unless
            /// `SubstituteOptions.extended` is set, in which case `$1` and
            /// `${name}` name groups. Nothing is allocated: the result is written
            /// into `buffer` and `Substitution.written.text` is a window on it.
            ///
            /// With `SubstituteOptions.overflow_length` set, the call answers
            /// the length the result needs without writing anything, which is how
            /// a caller sizes `buffer` and then calls again without that option.
            /// Without it, a buffer that does not fit is
            /// `error.SubstituteBufferTooSmall` and nothing is written.
            ///
            /// **What this leaves in `match_data`.** It is the caller's block and
            /// is written, never freed, and after an ordinary substitution
            /// nothing in it describes a capture: upstream matches into that
            /// block (`src/pcre2_substitute.c:984`), so the offset vector holds
            /// the *last* internal match's pairs, and on the way out it stores
            /// the number of substitutions it made in `match_data->rc`
            /// (`:1762`, `:1768`) -- a field every native substring entry point
            /// reads as a pair count (`src/pcre2_substring.c:317`, `:390`). So
            /// this call moves the block into the "nothing readable" state
            /// before it runs, whichever way the attempt ends, and the
            /// substitution count is reported as `Substitution.written.substitutions`
            /// rather than kept in the block: a later `MatchData.group` answers
            /// null and `list`, `get`, `copy` and `ovector` refuse, instead of
            /// resolving offsets that were computed against a different subject
            /// or walking a vector with more pairs in it than were written.
            ///
            /// `SubstituteOptions.matched` is the one case where that is not
            /// true, and where the description is deliberately left alone:
            /// upstream copies the caller's block into one of its own, matches
            /// into that, and frees it (`src/pcre2_substitute.c:898-917`,
            /// `:1767`), so the captures that were in the block are still the
            /// ones in it. That option substitutes the match already in the
            /// block, so it is also the only one whose result depends on what
            /// was there before.
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
                // The block now describes this substitution and nothing else,
                // before anything can refuse or upstream can write into it. The
                // reason is in the doc comment above: upstream leaves
                // `match_data->rc` holding the substitution count, and every
                // native substring entry point reads that field as a pair count,
                // so a block left describing an earlier match would be read
                // through a pair count that has nothing to do with the vector
                // next to it.
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
                    // PCRE2_ERROR_NOMEMORY, -48. With the overflow option set it
                    // is the length the result needs; without it, the copy gave
                    // up mid-way (`src/pcre2_substitute.c:638-656`, `:1771-1773`).
                    -48 => if (options.overflow_length)
                        .{ .overflow = length }
                    else
                        return error.SubstituteBufferTooSmall,
                    else => .{ .failed = .{ .code = rc, .text = diagnostic(rc) } },
                };
            }

            /// Walks every callout in the pattern, calling `callback` for each.
            ///
            /// `pcre2_callout_enumerate_N` hands the callback the compiled
            /// pattern's own positions and callout strings, not a match: this is
            /// how a caller learns what a pattern contains before running it. A
            /// non-zero answer from the callback stops the walk, and that answer
            /// is what this call returns, so a caller that found what it wanted
            /// stops with a positive value of its own.
            ///
            /// `callback` is not optional. Upstream calls it for every
            /// `OP_CALLOUT` and `OP_CALLOUT_STR` and never tests it against
            /// null (`src/pcre2_pattern_info.c:405`, `:418`), so a pattern
            /// containing one callout would dereference a null there rather
            /// than answer anything. Upstream's own declaration is a plain
            /// function pointer (`src/pcre2_pattern_info.c:267`), so that is the
            /// shape this takes: `Raw.CalloutEnumerate`.
            ///
            /// A negative answer is `error.PatternInfoUnavailable`. It is what a
            /// block PCRE2 does not recognise as a compiled pattern of this
            /// width answers, and what a callback that stopped the walk with a
            /// negative value of its own produces. Neither fits a `u32`, so
            /// neither is passed through as one.
            ///
            /// `data` is handed back to the callback unchanged and is the
            /// caller's for the length of the call. Nothing is allocated.
            pub fn enumerateCallouts(
                self: *const Regex,
                callback: Raw.CalloutEnumerate,
                data: ?*anyopaque,
            ) Error!u32 {
                const rc = Raw.callout_enumerate(self.code, callback, data);
                if (rc < 0) return error.PatternInfoUnavailable;
                return @intCast(rc);
            }

            /// Serializes this pattern.
            ///
            /// `extra` are further compiled blocks to put in the same stream,
            /// which is how upstream shares one set of character tables across
            /// patterns that will be compiled together. Blocks whose tables are
            /// at different addresses are refused by upstream with
            /// `PCRE2_ERROR_MIXEDTABLES` (`src/pcre2_serialize.c:99-102`),
            /// which is `error.SerializationRefused` and not
            /// `error.OutOfMemory`: the only allocation failure here is
            /// `PCRE2_ERROR_NOMEMORY` (`:108`), and it keeps that name.
            ///
            /// The returned bytes were allocated by PCRE2 and are released by
            /// `Serialized.deinit` and by nothing else. Releasing this `Regex`
            /// does not release them, and they outlive it.
            pub fn serialize(
                self: *const Regex,
                extra: []const ?*const Types.Code,
                scratch: []?*const Types.Code,
            ) Error!Serialized {
                // The pointer array is the caller's, because this facade takes
                // no allocator of its own anywhere and this is the one place a
                // variable-length array would have needed one. `scratch` has to
                // hold this pattern and every entry of `extra`; the bound is
                // checked here rather than left to the caller to discover as a
                // truncated list.
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

            /// Compiles a pattern from bytes `serialize` produced.
            ///
            /// `count` is how many blocks the caller wants back; upstream caps
            /// that at the number in the stream and answers it
            /// (`src/pcre2_serialize.c:183-184`, `:248`). The first block is
            /// the pattern this returns, and the rest are the caller's to free
            /// with `pcre2_code_free_N`.
            ///
            /// `all` is a caller-owned array, and it has to hold `count` of
            /// those pointers. Upstream writes one `pcre2_code *` per block it
            /// decodes (`src/pcre2_serialize.c:204`, `:243`) and never sees the
            /// length of the array it was handed, so a destination shorter than
            /// `count` is `error.OvectorTooSmall` here rather than an overrun
            /// the caller finds out about later. An empty destination is
            /// refused by the same comparison, because the answer is the first
            /// block. `Regex.serialize` owns the mirror of this bound for its
            /// own scratch array (`:2344-2345`).
            ///
            /// Bytes upstream will not decode are `error.SerializationRefused`,
            /// which is every refusal of the stream itself -- `BADMAGIC`,
            /// `BADMODE`, `BADSERIALIZEDDATA`, `BADDATA`, `NULL`
            /// (`:176-181`, `:209-213`, `:229-235`) -- as distinct from the one
            /// allocation failure, `PCRE2_ERROR_NOMEMORY` (`:192`, `:221`),
            /// which stays `error.OutOfMemory`. Nothing is left behind by a
            /// refusal: upstream frees the tables and every block it had
            /// already decoded on the way out (`:250-259`).
            ///
            /// The blocks come from upstream's `malloc` unless `general` says
            /// otherwise, and each is released by the caller.
            pub fn decode(
                bytes: []const u8,
                count: u32,
                all: []?*Types.Code,
                general: ?*const GeneralContext,
            ) Error!Regex {
                // The count is the caller's, the array is the caller's, and the
                // two have to agree before anything runs: upstream writes one
                // pointer per block it decodes and cannot see how long the
                // destination is.
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

            /// How many blocks a serialized stream holds, which is what
            /// `decode` needs as its `count`.
            ///
            /// This allocates nothing, so it cannot run out of memory: its
            /// negatives are the refusals of the bytes, `PCRE2_ERROR_NULL`,
            /// `PCRE2_ERROR_BADMAGIC` and `PCRE2_ERROR_BADMODE`
            /// (`src/pcre2_serialize.c:272-275`), and they are
            /// `error.SerializationRefused`.
            pub fn serializedCodeCount(bytes: []const u8) Error!u32 {
                const count = Raw.serialize_get_number_of_codes(bytes.ptr);
                if (count < 0) return error.SerializationRefused;
                return @intCast(count);
            }
        };

        /// A serialized pattern, owned.
        ///
        /// The bytes are PCRE2's own allocation, made inside
        /// `pcre2_serialize_encode_N` (`src/pcre2_serialize.c:106-108`) and
        /// released by `pcre2_serialize_free_N` and by nothing else. They are
        /// independent of the `Regex` they came from: that one may be released
        /// first, and these outlive it.
        pub const Serialized = struct {
            bytes: ?[*c]u8 = null,
            len: usize = 0,

            /// The stream, which is opaque bytes and not text.
            pub inline fn slice(self: *const Serialized) []const u8 {
                return self.bytes.?[0..self.len];
            }

            /// Releases the block and clears the handle, so a second call on this
            /// value is a no-op.
            pub fn deinit(self: *Serialized) void {
                if (self.bytes) |b| Raw.serialize_free(b);
                self.bytes = null;
                self.len = 0;
            }
        };

        /// Builds a `Regex` from a compiled block and reads the pattern
        /// information this facade needs once, so `captureCount`, `nameCount`
        /// and `nameAt` cost nothing later.
        fn fromRaw(code: *Types.Code) Error!Regex {
            var capture_count: u32 = 0;
            var name_count: u32 = 0;
            var name_entry_size: u32 = 0;
            // A bare pointer, not an optional, because that is the shape of the
            // out-parameter for `PCRE2_INFO_NAMETABLE`: upstream writes exactly
            // `sizeof(PCRE2_SPTR)` bytes there and touches nothing else
            // (`src/pcre2_pattern_info.c:229-232`). A Zig optional is not
            // required to be a bare pointer -- `?[*c]` is sixteen bytes in the
            // toolchain this fork builds with, where `?*T` and `?[]T` are eight
            // -- so an optional out-parameter came back as whatever its tag
            // held and `nameAt` took `orelse return null` on every in-range
            // index for every compiled block. The optional bought nothing: the
            // answer is never null, so the struct field is bare too.
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

        /// Releases a block this file could not finish building a `Regex` from.
        ///
        /// Every path into `fromRaw` that fails leaves a compiled block PCRE2
        /// allocated and no owner, so this is what keeps that from being a leak.
        fn failRaw(code: *Types.Code, err: Error) Error {
            Raw.code_free(code);
            return err;
        }

        // ---- Match data -------------------------------------------------------

        /// The offset vector and the result of the last match on it, owned
        /// separately from the pattern.
        ///
        /// PCRE2 fills the vector in place; this facade never copies a capture
        /// out of it and never reallocates it, so a capture is a pair of offsets
        /// into the caller's own subject. The block is freed by `deinit` and by
        /// nothing else, and `Regex.match` does not take ownership of it.
        ///
        /// Valid states are exactly two: created and not yet used, where
        /// `matched` is false, `subject` is empty and no capture is readable; and
        /// describing one attempt, which `Regex.match`, `Regex.dfa` and
        /// `Regex.substitute` move it into whether that attempt matched or not.
        /// `subject` and `matched` are the whole of that description, and the
        /// capture accessors fail closed on it: `matched` false is a block with
        /// nothing readable in it, whatever the offset vector still holds.
        /// `Regex.substitute` moves it into the second state on every call
        /// except the one that starts from the match already in the block,
        /// because that is the only case where it leaves the block alone.
        ///
        /// One block is one owner. `deinit` clears `raw` in the value it was
        /// called on, which makes a second call on that same value a no-op; a
        /// copy taken before it keeps the same pointer, so releasing both frees
        /// PCRE2's block twice. Copying the struct is never how a second owner is
        /// made.
        ///
        /// The block is sized once, for the pattern `create` was given, and
        /// nothing in it records which pattern that was. `Regex.match` therefore
        /// compares this block's capacity against **the pattern passed to that
        /// call** and refuses a pair that does not fit with
        /// `error.OvectorTooSmall`, so one block can be reused across patterns
        /// only while every one of them fits.
        pub const MatchData = struct {
            /// PCRE2's own match-data block: the offset vector and the fields
            /// the C side reads. `Regex.match` writes and reads it and `deinit`
            /// frees it. It is published for a caller that needs something this
            /// facade does not wrap: the ovector pointer behind a partial match,
            /// or the subject copy PCRE2 keeps under
            /// `MatchOptions.copy_matched_subject`. `null` once `deinit` has
            /// run, which is why the accessors below read it as non-null.
            ///
            /// Writing a different block into a live `MatchData` is a caller
            /// error this type cannot detect: `matched` and `subject` describe
            /// the attempt that filled the block being replaced, so `groupRange`
            /// and `group` would read one block's offsets against the previous
            /// one's verdict.
            raw: ?*Types.MatchData,
            /// The subject handed to the most recent `Regex.match`, `Regex.dfa`
            /// or `Regex.substitute` call on this block, whichever way that
            /// attempt ended, including a refused one. It is a borrow and not a
            /// copy, so it is valid until the next call on this block and is
            /// the caller's to keep alive; read it to recover the bytes a range
            /// refers to. While `matched` is true it is the subject the
            /// readable ranges were computed from; while it is false the ranges
            /// are gone and only the subject is left.
            ///
            /// Do not write it. It is the borrow `group` resolves a range
            /// against, and a slice the caller assigns here need not be the
            /// subject of the attempt that set `matched`, which is how a range
            /// ends up indexing one string with another's offsets.
            subject: []const code_unit = &.{},
            /// Whether the offset vector in `raw` was written by the most recent
            /// `Regex.match` on this block, which is to say whether that attempt
            /// matched and every group it used fitted in the vector.
            ///
            /// `Regex.substitute` clears it too, and that is the load-bearing
            /// part: the block it writes into is left holding the number of
            /// substitutions in its `rc` (`src/pcre2_substitute.c:1762`,
            /// `:1768`), and `rc` is what every native substring entry point
            /// reads as a pair count (`src/pcre2_substring.c:317`, `:390`).
            ///
            /// `Regex.match` clears it for **every** attempt and sets it only
            /// when `pcre2_match_N` returned one or more, because upstream writes
            /// `ovector[]` only on the path that matched
            /// (`src/pcre2_match.c:1045-1053`) and every other path returns
            /// through `src/pcre2_match.c:8184-8222` with the previous vector
            /// still in place. `MatchOutcome.matched` is never returned while
            /// this is false, so a caller that reads the outcome never has to
            /// test it to know whether a capture can be read; a caller that
            /// reached the block by another route has to test it.
            ///
            /// Defaulted, so a fresh block and a partial literal are both valid.
            /// That the previous vector survives a failed attempt is upstream's
            /// own documented contract rather than an inference from control
            /// flow: `doc/html/pcre2api.html:3330-3334`.
            matched: bool = false,

            /// How many offset-vector pairs the attempt that set `matched`
            /// actually filled, which is the number `pcre2_match_N` answered
            /// with: one more than the highest group the attempt used, capped at
            /// this block's `captureCount()` (`src/pcre2_match.c:8157-8158`).
            /// Group 0 is a pair, so a match of a pattern with no capturing
            /// groups at all is 1.
            ///
            /// Zero unless `matched` is true, and the reason `MatchData.list`
            /// counts with this and not with `captureCount()`: PCRE2's own
            /// substring entry points report the pairs the attempt filled
            /// (`src/pcre2_substring.c:390-391`), so a block given more room
            /// than the pattern needed has fewer pairs written than its
            /// `captureCount()` and nothing written beyond them.
            pairs: u32 = 0,

            /// Creates a block with an offset vector that holds `regex`'s group 0
            /// and every capturing group it declares.
            ///
            /// `pcre2_match_data_create_from_pattern_N` passes `top_bracket + 1`
            /// to `pcre2_match_data_create_N`, which silently clamps the pair
            /// count to `UINT16_MAX` and imposes a floor of one
            /// (`pcre2_match_data.c:57-58`) and reports no error. The facade
            /// checks the clamp instead of letting a caller read offsets that
            /// were never written. Nothing is allocated by this file and nothing
            /// is handed to a Zig allocator: on `error.OutOfMemory` PCRE2 returned
            /// NULL, and on `error.OvectorTooSmall` this call frees the block it
            /// just made rather than leaking it, so neither error leaves anything
            /// to release.
            ///
            /// The block is valid from here until `deinit`. It is not tied to
            /// `regex`: it may be used with any other pattern that fits, and
            /// `Regex.match` is what refuses one that does not.
            pub fn create(regex: *const Regex) Error!MatchData {
                const created = Raw.match_data_create_from_pattern(regex.code.?, null) orelse
                    return error.OutOfMemory;
                if (Raw.get_ovector_count(created) < regex.capture_count + 1) {
                    Raw.match_data_free(created);
                    return error.OvectorTooSmall;
                }
                return .{ .raw = created };
            }

            /// Creates a block whose offset vector holds `ovecsize` pairs,
            /// group 0 included, and allocates it from `general` if one is given.
            ///
            /// `pcre2_match_data_create_N` clamps `ovecsize` to `UINT16_MAX` and
            /// imposes a floor of one (`pcre2_match_data.c:57-58`) and says
            /// nothing, so the value actually taken is read back and a caller
            /// that asked for more than it got is told so.
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

            /// Releases PCRE2's block and clears `raw`, so a second call on this
            /// value is the same no-op rather than a second free. The value is
            /// unusable afterwards: every accessor reads `raw` as non-null.
            /// Copying the struct before this call copies the pointer, and that
            /// copy is not made safe by the one being cleared.
            pub fn deinit(self: *MatchData) void {
                Raw.match_data_free(self.raw);
                self.raw = null;
            }

            /// How many offset-vector pairs this block can hold, which is one
            /// more than the capture count of the pattern `create` was given.
            /// Every group number this facade accepts is below this, and
            /// `Regex.match` refuses any pattern whose capture count is not.
            pub inline fn captureCount(self: *const MatchData) u32 {
                return Raw.get_ovector_count(self.raw.?);
            }

            /// The code-unit range of capturing group `number`, or null when
            /// there is no range to report.
            ///
            /// There is no range for either of two reasons: the group did not
            /// take part in the match that filled the block, or the attempt that
            /// last used the block did not match at all. The second is not a
            /// guess: PCRE2 writes `ovector[]` only on the path that matched
            /// (`src/pcre2_match.c:1045-1053`), so after `no_match`, after any
            /// other negative return, or after a refused attempt the vector still
            /// holds an earlier attempt's offsets, which describe a subject the
            /// caller may no longer even be holding.
            ///
            /// `error.NoSuchGroup` is about `number` alone and is answered before
            /// the match state is looked at: a group number the block cannot
            /// index is a mistake whatever the block last did.
            pub fn groupRange(self: *const MatchData, number: u32) Error!?Group {
                // The group number first, before the match state: it is a
                // statement about the index the caller passed, and it holds
                // whatever the block last did.
                if (number >= self.captureCount()) return error.NoSuchGroup;
                if (!self.matched) return null;
                const offsets = Raw.get_ovector_pointer(self.raw.?);
                const index = @as(usize, number) * 2;
                const start = offsets[index];
                const end = offsets[index + 1];
                if (start == unset or end == unset) return null;
                return .{ .start = start, .end = end };
            }

            /// The text of capturing group `number`, or null when there is no
            /// range to report, for either of the two reasons `groupRange`
            /// gives. The slice is a window on `subject` and is copied by
            /// nothing, so a write through the subject is visible in an answer
            /// given earlier and the slice must not outlive the buffer it came
            /// from.
            ///
            /// Resolves the range against `MatchData.subject`, which is why that
            /// field is not a caller's to overwrite.
            pub fn group(self: *const MatchData, number: u32) Error!?[]const code_unit {
                const range = (try self.groupRange(number)) orelse return null;
                return self.subject[range.start..range.end];
            }

            /// PCRE2's start-offset record for the last attempt, and nothing more
            /// than that: this is `pcre2_get_startchar`, one field of the block,
            /// and it is only meaningful on the outcomes below.
            ///
            /// * On a match, where the match starts.
            /// * On `MatchOutcome.invalid_utf` from the validator, the offset of
            ///   the first malformed code unit, which is the value the
            ///   validator's `erroroffset` was left at
            ///   (`src/pcre2_match.c:7334`).
            /// * On `MatchOutcome.failed` with `PCRE2_ERROR_PARTIAL`, -2, where
            ///   the partially matched part begins
            ///   (`src/pcre2_match.c:8206`).
            ///
            /// After `no_match`, a match/depth ceiling, or an invalid UTF
            /// character boundary, the native matcher leaves this field at its
            /// reset value, zero (`src/pcre2_match.c:7120`, `:7272-7276`).
            ///
            /// A facade refusal (`error.OvectorTooSmall` or
            /// `error.StartOffsetOutOfRange`) does not enter the matcher or reset
            /// this field. Some native failures also precede the reset: partial
            /// matching combined with end anchoring returns
            /// `PCRE2_ERROR_BADOPTION`, -34 (`src/pcre2_match.c:7095-7097`),
            /// retaining the previous value.
            ///
            /// Read this field only with one of the meaningful outcomes listed
            /// above, never as proof that `MatchData.matched` is true.
            pub inline fn startOffset(self: *const MatchData) usize {
                return Raw.get_startchar(self.raw.?);
            }

            /// PCRE2's own offset vector, for a caller that needs a range this
            /// facade does not split out: the end of a partial match, for
            /// instance.
            ///
            /// Only meaningful on an attempt that matched: the same rule
            /// `groupRange` follows, because upstream writes the vector only on
            /// that path (`src/pcre2_match.c:1045-1053`). The pointer is into
            /// PCRE2's block and is invalidated by the next attempt on it, by
            /// `deinit`, and by nothing else.
            pub inline fn ovector(self: *const MatchData) Error![*c]usize {
                if (!self.matched) return error.SubstringUnavailable;
                return Raw.get_ovector_pointer(self.raw.?);
            }

            /// The last MARK label from a successful attempt, or null.
            /// This is not the match-start reset performed by `\K`.
            ///
            /// PCRE2 stores the label in compiled code (`pcre2_match.c:6777-6779`).
            /// The returned slice borrows that code. Keep the pattern alive.
            /// `copy_matched_subject` does not affect this label.
            pub fn mark(self: *const MatchData) Error!?[]const code_unit {
                if (!self.matched) return null;
                const pointer = Raw.get_mark(self.raw.?);
                if (pointer == null) return null;
                return std.mem.span(pointer);
            }

            /// How many bytes PCRE2's block for this match data occupies,
            /// including the offset vector (`src/pcre2_match_data.c:96-110`).
            /// It is a fact about the block, not a bound: this facade allocates
            /// nothing.
            pub inline fn size(self: *const MatchData) usize {
                return Raw.get_match_data_size(self.raw.?);
            }

            /// How many bytes the heap frames this block accumulated hold. Zero
            /// unless a match used more heap than its own frames
            /// (`src/pcre2_match_data.c:118-131`), and it is released by PCRE2
            /// at `deinit`.
            pub inline fn heapFramesSize(self: *const MatchData) usize {
                return Raw.get_match_data_heapframes_size(self.raw.?);
            }

            /// Capturing group `number` as a copy PCRE2 allocated, owned.
            ///
            /// This is `pcre2_substring_get_bynumber_N`
            /// (`src/pcre2_substring.c:205-224`): it allocates a block of its
            /// own, copies the group into it and answers the address and the
            /// length, so what comes back is released with `Owned.deinit`, which
            /// calls `pcre2_substring_free_N` (`:237-245`) and by nothing else.
            ///
            /// It copies from the block's own record of the subject, and that
            /// record is the caller's own subject unless the match was made with
            /// `MatchOptions.copy_matched_subject`
            /// (`src/pcre2_match.c:8165-8179`). So the copy does not need the
            /// option, and what it copies has to still be there: the subject
            /// `subject` holds is the one PCRE2 reads.
            ///
            /// A negative answer is `error.SubstringUnavailable`, which is the
            /// condition `pcre2_substring_length_bynumber_N` reports and not a
            /// code this file has to choose between.
            pub fn get(self: *const MatchData, number: u32) Error!Owned {
                if (number >= self.captureCount()) return error.NoSuchGroup;
                if (!self.matched) return error.SubstringUnavailable;
                var out: [*c]code_unit = null;
                var got: usize = 0;
                const rc = Raw.substring_get_bynumber(self.raw, number, &out, &got);
                if (rc < 0) return error.SubstringUnavailable;
                return .{ .bytes = out, .len = got };
            }

            /// Copies capturing group `number` into `buffer`, the caller's own
            /// storage, and answers how many code units it wrote.
            ///
            /// This is `pcre2_substring_copy_bynumber_N`
            /// (`src/pcre2_substring.c:117-130`), and the difference from `get`
            /// is that nothing is allocated: `buffer.len` goes in as the room
            /// there is and comes back holding the number of code units copied.
            /// The terminating null PCRE2 writes after them (`:127`) is part of
            /// the room needed and is not in that count, and a buffer one unit
            /// short of `length + 1` is `error.SubstringBufferTooSmall`, which
            /// is `PCRE2_ERROR_NOMEMORY`, -48, answered before anything is
            /// written.
            ///
            /// The count is what tells a caller how much of `buffer` is text.
            /// The terminator makes the answer a NUL-terminated string in
            /// `buffer[0..count]`, so this reaches for code units that may hold
            /// one.
            pub fn copy(self: *const MatchData, number: u32, buffer: []code_unit) Error!usize {
                if (number >= self.captureCount()) return error.NoSuchGroup;
                if (!self.matched) return error.SubstringUnavailable;
                var capacity: usize = buffer.len;
                const rc = Raw.substring_copy_bynumber(self.raw, number, buffer.ptr, &capacity);
                if (rc == -48) return error.SubstringBufferTooSmall; // PCRE2_ERROR_NOMEMORY
                if (rc < 0) return error.SubstringUnavailable;
                return capacity;
            }

            /// Every capture of the attempt that filled this block, in group
            /// order, as PCRE2's own NUL-separated list, owned.
            ///
            /// This is `pcre2_substring_list_get_N`
            /// (`src/pcre2_substring.c:379-438`). It allocates one block and
            /// answers two pointers into it: the array of `pairs` `PCRE2_UCHAR
            /// *` that points at each capture, null-terminated (`:407`, `:436`),
            /// and the array of `pairs` `PCRE2_SIZE` beside the strings
            /// (`:408-419`). Both are here, in `SubstringList`, because the
            /// out-parameters are one slot each and hold nothing a caller has to
            /// own; the block is released by `SubstringList.deinit`, which calls
            /// `pcre2_substring_list_free_N` from the array of pointers
            /// (`:451-459`).
            ///
            /// A group that did not take part is reported as an empty string,
            /// which is what the list format has for it
            /// (`src/pcre2_substring.c:421-434`).
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

            /// Whether another attempt should be made from this block.
            ///
            /// This is `pcre2_next_match_N`
            /// (`src/pcre2_match_next.c:96-169`), which a caller iterating
            /// over every match in a subject calls after each successful
            /// attempt. It answers `TRUE`, 1, when another attempt should be
            /// made and `FALSE`, 0, when there is none, and it never answers
            /// anything else, so there is nothing here to refuse and this is a
            /// plain `bool`.
            ///
            /// `start_offset` and `options` are the two out-parameters upstream
            /// takes (`src/pcre2.h.generic:775`) and it writes each of them at
            /// most once, and only on the paths that return `TRUE`
            /// (`src/pcre2_match_next.c:138-139`, `:157-158`, `:166-167`); the
            /// three `FALSE` returns write neither (`:109`, `:134`, `:152`).
            /// Pass `start_offset` to the next attempt as it stands, and
            /// `options` combined with the application's own match options
            /// (`doc/pcre2.txt:3433-3444`).
            ///
            /// The start offset advances on every `TRUE`, which is what makes
            /// such a loop terminate (`doc/pcre2.txt:3465-3470`).
            pub fn next(self: *const MatchData, start_offset: *usize, options: *u32) bool {
                return Raw.next_match(self.raw, start_offset, options) != 0;
            }
        };

        /// A capture PCRE2 allocated, owned.
        ///
        /// What `MatchData.get` answers with: the block
        /// `pcre2_substring_get_bynumber_N` allocated behind a `pcre2_memctl`
        /// header naming the allocator that produced it
        /// (`src/pcre2_substring.c:213-217`), so it is released by
        /// `pcre2_substring_free_N` and by nothing else: not
        /// `pcre2_code_free`, and not a Zig allocator.
        ///
        /// `deinit` clears the handle, which makes a second call on the same
        /// value a no-op; a copy taken before it keeps the same pointer and is
        /// not made safe by the one being cleared.
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

        /// Every capture of one attempt, as PCRE2's own NUL-separated list,
        /// owned.
        ///
        /// Both fields are inside the one block
        /// `pcre2_substring_list_get_N` allocated, and `bytes` is the address
        /// `pcre2_substring_list_free_N` is given: that function frees the
        /// block from the array of pointers, which is why `bytes` is the array
        /// and not the first string in it (`src/pcre2_substring.c:407-419`,
        /// `:451-459`). `deinit` releases it and clears `bytes`, so a second call
        /// on the same value is a no-op.
        pub const SubstringList = struct {
            /// PCRE2's array of `count` capture addresses, null-terminated, at
            /// the head of the block. `null` once `deinit` has run.
            bytes: ?[*c][*c]code_unit = null,
            /// How many captures this list reports: the pairs the attempt that
            /// filled the block wrote, which is `MatchData.pairs` and not the
            /// block's `captureCount()`.
            count: u32 = 0,
            /// PCRE2's array of `count` lengths, in the same block and under
            /// the same `deinit`. Only read below `count`, which is what
            /// `get` checks first.
            lengths: [*c]usize = null,

            /// Capture `index`, as a window on the list block rather than on the
            /// caller's subject. Null when `index` is at or above `count`.
            /// Valid until `deinit`.
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

        /// The smallest workspace `pcre2_dfa_match_N` accepts. A smaller one is
        /// refused with `PCRE2_ERROR_DFA_WSSIZE`, -43
        /// (`src/pcre2_dfa_match.c:3437`), and 20 is what upstream's own worked
        /// example passes (`doc/pcre2.txt:4279-4288`).
        pub const minimum_workspace: usize = 20;

        /// The caller's buffer for the DFA matcher.
        ///
        /// `pcre2_dfa_match_N` takes this buffer for one job: it is the
        /// matcher's own working storage, filled with its active and new state
        /// blocks (`src/pcre2_dfa_match.c:605-606`) and left holding whatever
        /// the last attempt put there. **The matched ranges are not in it.** They
        /// go into the `MatchData` block's offset vector
        /// (`src/pcre2_dfa_match.c:4062-4063`;
        /// `src/pcre2_substring.c:334-341`), which is what `Regex.dfa` leaves
        /// readable and what a caller reads through `MatchData.ovector()`.
        ///
        /// It is also the resumable state `DfaOptions.restart` needs: PCRE2
        /// reads its own bookkeeping out of the first two entries and refuses a
        /// restart whose state it did not write
        /// (`src/pcre2_dfa_match.c:3486-3489`;
        /// `doc/pcre2.txt:4325-4331`), so a caller that sets that bit and adds
        /// subject characters has to hand the same buffer back. That is why
        /// this holds a slice rather than taking it by value.
        ///
        /// Nothing is allocated here: the buffer is the caller's own storage, a
        /// fixed array or an `std.ArrayList` or anything else, and PCRE2
        /// neither keeps nor frees it.
        pub const DfaWorkspace = struct {
            /// The caller's buffer. Scratch for the matcher, and the only place a
            /// restart's state can live; its contents are the matcher's own.
            offsets: []c_int,
            /// The workspace size to pass for a subject of `subject_len` code
            /// units.
            ///
            /// Never below 20: `pcre2_dfa_match_N` refuses anything smaller
            /// with `PCRE2_ERROR_DFA_WSSIZE`, -43
            /// (`src/pcre2_dfa_match.c:3437`), and 20 is the size upstream's own
            /// worked example passes (`doc/pcre2.txt:4279-4288`). Above that it
            /// is the subject's length, which is the other thing the matcher
            /// needs the room for.
            pub inline fn wscount(self: *const DfaWorkspace, subject_len: usize) usize {
                _ = self;
                return @max(subject_len, minimum_workspace);
            }
        };
    };
}
