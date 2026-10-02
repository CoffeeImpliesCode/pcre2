//! Public Zig surface of the PCRE2 fork.
//!
//! Scope: the 8-bit (`pcre2_8`) library compiled from this repository's own
//! `src/`, with Unicode support and with JIT left off. Every declaration below
//! carries a pointer, a count or a status code across the C boundary; no PCRE2
//! algorithm is reimplemented here, and no constant is taken from prose. Each
//! one names the line of `src/pcre2.h.generic`, `src/pcre2_match.c` or
//! `src/pcre2_context.c` that it was read out of, so a reader can check the
//! binding against the source instead of against this file.
//!
//! Two ways in:
//!   * `pub const c` is the complete translated `pcre2.h`, including the
//!     16-bit and 32-bit declarations, `pcre2_dfa_match`, `pcre2_substitute`
//!     and the serialization calls that this facade deliberately does not
//!     wrap. Nothing is filtered out; reach for it when you need an entry
//!     point that is not below.
//!   * Everything else is the typed surface: an owned compiled pattern, an
//!     owned match-data block, an owned match context, and results whose
//!     captures borrow the caller's subject instead of copying it.
//!
//! Ownership and lifetime:
//!   * `Regex` owns the `pcre2_code` and releases it in `deinit`. PCRE2
//!     allocates that block itself (`pcre2_compile.c`) and there is no
//!     allocator to confuse: no Zig allocator is handed to PCRE2, no
//!     general context is created, and no global allocator hook is installed.
//!   * `MatchData` and `MatchContext` are owned separately and released by
//!     their own `deinit`. `Regex.match` never frees the caller's `MatchData`,
//!     so `defer` around a `MatchData` cannot double free.
//!   * Capture ranges are byte offsets into the subject the caller passed.
//!     `MatchData` borrows that slice and never copies it, so a capture is
//!     valid until the next `match` on the same `MatchData`, until that
//!     `MatchData` is deinitialised, or until the subject is written to.
//!     PCRE2 fills its offset vector only when an attempt matched
//!     (`src/pcre2_match.c:1045-1053`), so a block whose last attempt did not
//!     match reports no capture at all: `groupRange` and `group` answer null
//!     rather than hand back offsets that describe an earlier subject.
//!   * `version` writes into a buffer the caller owns and answers with a slice
//!     of that same buffer. Nothing it returns is a borrow of a frame that has
//!     already gone: the storage and the string in it have one lifetime, and it
//!     is the caller's.

const std = @import("std");

/// The complete translated `pcre2.h` for this build.
///
/// This is the raw C surface, not a filtered one: the 16-bit and 32-bit
/// declarations are present because `src/pcre2.h.generic:1019-1030` emits all
/// three widths, and `pcre2_dfa_match`, `pcre2_substitute` and the
/// serialization calls are present because this facade does not wrap them.
///
/// The declarations are read from this repository's own 10.49 header as the
/// compiler for this target expands it. On a GNU-libc target Aro reads
/// `translate.h` for itself, because Aro reads that C library's headers and
/// the target's own preprocessor's expansion of them is not a file Aro can
/// parse; on every other target build.zig expands it first with
/// `zig cc -E -dD -fno-blocks` for the target and hands over the result,
/// because Aro's own preprocessor cannot read that C library. Either route adds
/// nothing to PCRE2's surface and takes nothing from it: every declaration the
/// header publishes is present, for all three widths, and the C library
/// declarations `src/pcre2.h.generic:87-89` includes are here as expanded,
/// beside PCRE2's own. Where two front ends read the same header they are held
/// to one language and to the types the target really has - blocks off, because
/// Aro cannot parse a block pointer, and the compiler's own
/// `__int128_t`/`__uint128_t` restated in `translate.h`, because the C library
/// headers spell those names without declaring them - so what reaches this
/// module is what the translator could have read for itself.
pub const c = @import("c");

/// Everything this facade can refuse to do, and nothing else.
///
/// The taxonomy stops where the checks stop. Each name is a claim about what
/// this file compared, not a guess at what PCRE2 might have meant.
pub const Error = error{
    /// A PCRE2 entry point that can only fail by failing to allocate returned
    /// NULL. The three such sites reached from here are `pcre2_compile.c`
    /// (which also reports this as compile error 121,
    /// "failed to allocate heap memory"), `pcre2_match_data.c:62` and
    /// `pcre2_context.c:188`.
    OutOfMemory,
    /// `pcre2_pattern_info_8` refused a query that this facade believes is
    /// valid for a compiled block. Named for the missing result; it claims no
    /// cause, because this file did not establish one.
    PatternInfoUnavailable,
    /// The caller's start offset is past the end of the subject. Checked here
    /// before any C runs, because PCRE2 answers the same condition with
    /// `PCRE2_ERROR_BADOFFSET` (-33) from inside the matcher and the facade
    /// owns this bound as an ordinary comparison rather than an assertion.
    StartOffsetOutOfRange,
    /// The requested group number is not below `MatchData.captureCount()`.
    /// PCRE2's own substring helpers would index its offset vector past the
    /// end, so the facade checks first and names the condition.
    NoSuchGroup,
    /// The pattern's capture count does not fit the offset vector this block
    /// was given. `pcre2_match_data_create_8` clamps the pair count to
    /// `UINT16_MAX` (`pcre2_match_data.c:57-58`) and says nothing, so the
    /// facade compares what it got against what the pattern needs instead of
    /// handing back a block whose tail was never written.
    OvectorTooSmall,
    /// `version`'s buffer is shorter than the size the library reports it
    /// needs. `pcre2_config_8` takes a `void *` and writes `1 + strlen(v)`
    /// code units into whatever that pointer is (`pcre2_config.c:241-242`), so
    /// it cannot know the capacity: the bound belongs to the caller, and this
    /// file compares against the required size before anything is written
    /// rather than finding out afterwards.
    VersionBufferTooSmall,
    /// The library declined the `PCRE2_CONFIG_VERSION` query instead of
    /// answering it. `pcre2_config_8` answers a request it does not recognise
    /// with `PCRE2_ERROR_BADOPTION`, -34 (`src/pcre2.h.generic:398`), which is
    /// the default of the switch it dispatches on (`pcre2_config.c:105-108`)
    /// and of the length query in front of it (`:73-78`). Substituting a
    /// placeholder string would report a release the archive was never built
    /// with, so the refusal is what this is.
    VersionUnavailable,
};

/// `PCRE2_UNSET`, `src/pcre2.h.generic:539`: the value PCRE2 leaves in the
/// offset vector for a capturing group that did not take part in the match
/// (`pcre2_match.c:1036-1037`, `:1053`).
pub const unset: usize = ~@as(usize, 0);

/// The largest number of bytes a diagnostic is kept in. Upstream's message
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

/// Options for `pcre2_compile_8`.
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

    /// The 32-bit word `pcre2_compile_8` expects.
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

/// Options for `pcre2_match_8`, copied from `src/pcre2.h.generic:102-104` and
/// `:179-197`. The `pcre2_dfa_match` and `pcre2_substitute` bits of that
/// range are left out: this facade does not call those functions, and a bit
/// that names another entry point is not an option here.
pub const match_option = struct {
    pub const notbol: u32 = 0x0000_0001; // :179 PCRE2_NOTBOL
    pub const noteol: u32 = 0x0000_0002; // :180 PCRE2_NOTEOL
    pub const notempty: u32 = 0x0000_0004; // :181 PCRE2_NOTEMPTY
    pub const notempty_atstart: u32 = 0x0000_0008; // :182 PCRE2_NOTEMPTY_ATSTART
    pub const partial_soft: u32 = 0x0000_0010; // :183 PCRE2_PARTIAL_SOFT
    pub const partial_hard: u32 = 0x0000_0020; // :184 PCRE2_PARTIAL_HARD
    pub const no_jit: u32 = 0x0000_2000; // :192 PCRE2_NO_JIT
    pub const copy_matched_subject: u32 = 0x0000_4000; // :193 PCRE2_COPY_MATCHED_SUBJECT
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
    partial_soft: bool = false,
    partial_hard: bool = false,
    no_jit: bool = false,
    copy_matched_subject: bool = false,
    disable_recurseloop_check: bool = false,
    endanchored: bool = false,
    no_utf_check: bool = false,
    anchored: bool = false,

    /// The 32-bit word `pcre2_match_8` expects.
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

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------

/// A message copied out of PCRE2's own text, plus the number of bytes that
/// are actually message.
///
/// `pcre2_get_error_message_8` returns the number of characters it wrote,
/// excluding the terminating NUL (`pcre2_error.c:382-383`), so `slice()` is
/// `bytes[0..len]`. A message too long for the buffer comes back as
/// `PCRE2_ERROR_NOMEMORY` with `size - 1` characters written and truncated, and
/// `len` is `size - 1` in that case, which is how a caller can tell that it was
/// cut rather than complete.
pub const Text = struct {
    bytes: [diagnostic_buffer_size]u8 = @splat(0),
    len: usize = 0,

    /// The message, without the terminating NUL.
    pub inline fn slice(self: *const Text) []const u8 {
        return self.bytes[0..self.len];
    }
};

fn diagnostic(code: i32) Text {
    var text: Text = .{};
    const written = c.pcre2_get_error_message_8(code, &text.bytes, text.bytes.len);
    if (written < 0) {
        // The buffer was filled to `size - 1` and the call reported
        // PCRE2_ERROR_NOMEMORY, which is how upstream says the message did not
        // fit (`pcre2_error.c:363-370`). The text is still usable; it is just
        // the beginning of the sentence.
        text.len = text.bytes.len - 1;
        return text;
    }
    text.len = @intCast(written);
    return text;
}

/// What `Regex.compile` did.
pub const CompileOutcome = union(enum) {
    /// The pattern compiled. Owns PCRE2's compiled block; release it with
    /// `Regex.deinit`.
    compiled: Regex,
    /// Upstream rejected the pattern. Both fields are upstream's own: `code`
    /// is the number from the table at `src/pcre2_error.c` (compile errors
    /// are 100 plus an index, `src/pcre2_compile.h:53`) and `offset` is
    /// the byte offset in the pattern that upstream reported, which is the
    /// same offset `pcre2test` prints after "at offset".
    rejected: Rejection,
};

/// A pattern upstream refused, with everything needed to point a user at it.
pub const Rejection = struct {
    code: i32,
    offset: usize,
    text: Text,
};

/// What one `Regex.match` call returned.
///
/// A negative return from `pcre2_match_8` is not one condition. It is a
/// non-match, or one of the resource ceilings, or a UTF validity failure, or
/// something this facade does not model, and an attacker who can choose the
/// subject needs to be able to tell those apart without reading a message
/// string. The split is taken from `src/pcre2_error.c`'s table and from the
/// call sites in `src/pcre2_match.c`.
pub const MatchOutcome = union(enum) {
    /// `pcre2_match_8` returned 0 or more. The capture groups may be read.
    /// A return of zero means upstream filled the offset vector only as far as
    /// it reached, which `MatchData.create` rules out for a block made from
    /// this pattern; if it ever happened, `MatchData.matched` would be false
    /// and no range would be readable.
    matched: void,
    /// `PCRE2_ERROR_NOMATCH`, -1 (`src/pcre2.h.generic:350`). The pattern did
    /// not match at or after the requested start offset. This is the ordinary
    /// negative answer, not a failure, and it is not an error.
    no_match: void,
    /// `PCRE2_ERROR_MATCHLIMIT`, -47 (:411): the match context's match limit
    /// was reached. The pattern may well match; the work was refused.
    match_limit: void,
    /// `PCRE2_ERROR_DEPTHLIMIT`, -53 (:417): the match context's depth limit
    /// was reached.
    depth_limit: void,
    /// `PCRE2_ERROR_HEAPLIMIT`, -63 (:428): the match context's heap limit
    /// was reached.
    heap_limit: void,
    /// The subject is not valid UTF-8 for a UTF pattern, or the start offset
    /// is not on a character boundary. `code` is upstream's own number:
    /// -3 to -23 for the eight-bit validity failures
    /// (`PCRE2_ERROR_UTF8_ERR1` to `PCRE2_ERROR_UTF8_ERR21`) and -36 for
    /// `PCRE2_ERROR_BADUTFOFFSET` (:400).
    ///
    /// The byte offset of the offending code unit is in
    /// `MatchData.startOffset`, for the validity failures only:
    /// `pcre2_match.c:7270-7279` returns before writing that field when the
    /// start offset itself is on a continuation byte.
    invalid_utf: struct { code: i32, text: Text },
    /// Any other negative return, with upstream's number and its text, so
    /// nothing is flattened into a generic failure.
    failed: struct { code: i32, text: Text },
};

// ---------------------------------------------------------------------------
// Compiled pattern
// ---------------------------------------------------------------------------

/// A capturing group's byte range inside the subject.
///
/// Both ends are byte offsets from the start of the subject, which is what
/// PCRE2's offset vector holds. For a pattern compiled with `PCRE2_UTF` these
/// are code-unit offsets, not character indices, so a three-byte character
/// advances `end` by three.
pub const Group = struct {
    start: usize,
    end: usize,
};

/// One entry of a pattern's name table.
pub const Name = struct {
    /// The group number the name is bound to. Group numbers start at 1.
    number: u32,
    /// The name, borrowed from the compiled block. It is not NUL-terminated
    /// in this slice and it is valid only while the `Regex` lives.
    name: []const u8,
};

/// A compiled pattern, owned.
///
/// Created by `compile`, released by `deinit`. Copying the struct copies the
/// pointer, so there is exactly one owner; `deinit` takes a mutable pointer and
/// clears it, which makes a second call a no-op rather than a double free.
pub const Regex = struct {
    code: ?*c.pcre2_code_8,
    /// `PCRE2_INFO_CAPTURECOUNT` is `re->top_bracket`
    /// (`pcre2_pattern_info.c:136-137`): the highest group number, so a
    /// pattern with no groups has 0 and `captureCount()` is 1.
    capture_count: u32,
    name_count: u32,
    name_entry_size: u32,
    /// Points into the compiled block, which this value owns. Absent only if
    /// the pattern metadata could not be read at all; PCRE2 answers a table
    /// address for every compiled block, including one with no names
    /// (`pcre2_pattern_info.c:229-232`), and a pattern with no names is
    /// already out of range for every `nameAt` index.
    name_table: ?[*c]const u8,

    /// Compiles `pattern`.
    ///
    /// A rejection is a value, not an error: a malformed pattern is a fact
    /// about the pattern, and the caller usually wants the code and the byte
    /// offset to show the user. Only the two conditions that are not about
    /// the pattern become an error, and both are the same one.
    ///
    /// No allocator is involved on either path. The compiled block is
    /// allocated by PCRE2 with `malloc` and released by `Regex.deinit`.
    pub fn compile(pattern: []const u8, options: CompileOptions) Error!CompileOutcome {
        var code: i32 = 0;
        var offset: usize = 0;
        const compiled = c.pcre2_compile_8(
            pattern.ptr,
            pattern.len,
            @intCast(options.toBits()),
            &code,
            &offset,
            null,
        ) orelse {
            // `pcre2_compile` returns NULL for exactly two reasons and sets
            // *errorcode for both: a pattern diagnostic, and ERR21, which is
            // 121, "failed to allocate heap memory"
            // (`pcre2_compile.c:10780`, `:10811`, `:10947`; `ERRn == 100 + n`
            // by `src/pcre2_compile.h:53`).
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
        c.pcre2_code_free_8(self.code);
        self.code = null;
    }

    /// The highest capturing group number in the pattern, so there are
    /// `captureCount() + 1` groups counting group 0.
    pub inline fn captureCount(self: *const Regex) u32 {
        return self.capture_count;
    }

    /// How many names the pattern declared. PCRE2 keeps the table in name
    /// order, not group order and not the order the names were written in
    /// (`pcre2_compile_cgroup.c:106-108`, `:140-161`; the lookup at
    /// `pcre2_substring.c:495-523` binary-searches it), so this is the bound
    /// for `nameAt` and not a group number.
    pub inline fn nameCount(self: *const Regex) u32 {
        return self.name_count;
    }

    /// Name-table entry `index`, or null when `index` is past the table.
    ///
    /// `index` walks the table in name order, so it is not a group number and
    /// the numbers it produces need not ascend. One entry is
    /// `name_entry_size` bytes: the group number big endian, then the name,
    /// then a NUL and zero padding out to the size the longest name in the
    /// pattern asked for (`pcre2_compile.c:5713-5716` sizes every entry that
    /// way; `pcre2_compile_cgroup.c:167-175` writes it). The size therefore
    /// depends on the pattern and not on `index`, and the name is ended by
    /// the NUL inside the entry rather than by the end of the entry, which is
    /// what makes a name shorter than the longest one readable.
    pub fn nameAt(self: *const Regex, index: u32) ?Name {
        if (index >= self.name_count) return null;
        const table = self.name_table orelse return null;
        const size = self.name_entry_size;
        // The floor for an entry this file can walk: the two group-number
        // bytes it reads, plus at least one byte of the name after them.
        // Upstream never produces a smaller one: `pcre2_compile.c:5713-5716`
        // sizes every entry to the longest name in the pattern plus those two
        // bytes and a NUL, and a name is at least one character wide. But the
        // walk below multiplies by this value, so the bound is checked here
        // rather than left as a comment about what upstream does.
        if (size < 3) return null;
        const base = @as(usize, index) * size;
        const entry = table[base..][0..size];
        const number = (@as(u32, entry[0]) << 8) | @as(u32, entry[1]);
        const rest = entry[2..];
        const end = std.mem.indexOfScalar(u8, rest, 0) orelse rest.len;
        return .{ .number = number, .name = rest[0..end] };
    }

    /// The name bound to `number`, or null when the pattern declared no such
    /// name. This is a scan, because the table is in name order rather than
    /// in group order, so the answer is not at a position `number` can index
    /// into.
    pub fn nameForNumber(self: *const Regex, number: u32) ?[]const u8 {
        var i: u32 = 0;
        while (i < self.name_count) : (i += 1) {
            const entry = self.nameAt(i) orelse return null;
            if (entry.number == number) return entry.name;
        }
        return null;
    }

    /// The group number `name` is bound to, or null when the pattern has no
    /// such name. `pcre2_substring_number_from_name_8` takes a NUL-terminated
    /// name, so the caller's slice is copied into a stack buffer; a name
    /// longer than `max_name_length` is not a name of any pattern PCRE2 would
    /// have accepted (`pcre2_compile.c:2671`).
    pub fn numberForName(self: *const Regex, name: []const u8) ?u32 {
        if (name.len > max_name_length) return null;
        var buffer: [max_name_length + 1]u8 = undefined;
        @memcpy(buffer[0..name.len], name);
        buffer[name.len] = 0;
        const number = c.pcre2_substring_number_from_name_8(self.code.?, &buffer);
        if (number < 0) return null;
        return @intCast(number);
    }

    /// The compiled block, for a caller that needs an entry point this facade
    /// does not wrap: `pcre2_dfa_match`, `pcre2_substitute`, the serialization
    /// calls, or any of the 16-bit and 32-bit declarations that
    /// `src/pcre2.h.generic:1019-1030` emits into the translated header.
    ///
    /// The pointer is const because that is how every PCRE2 entry point takes
    /// it except `pcre2_jit_compile`, and this fork builds with JIT off. It
    /// stays owned by this `Regex`; the caller must not free it.
    pub inline fn raw(self: *const Regex) *const c.pcre2_code_8 {
        return self.code.?;
    }

    /// Runs one match attempt over `subject` starting at `start_offset`.
    ///
    /// `match_data` is the caller's and is never freed here. `mcontext` is
    /// optional; without one, PCRE2 uses the compiled-in defaults
    /// `MATCH_LIMIT` of 10000000 and `MATCH_LIMIT_DEPTH` equal to it
    /// (`src/config.h.generic:195` and `:209`), which is upstream behaviour
    /// and is what a caller who passes no context gets.
    ///
    /// The subject is borrowed, not copied, and the offsets in the outcome
    /// and in `match_data` are byte offsets into it.
    ///
    /// A failed attempt leaves the block describing nothing at all. PCRE2 keeps
    /// the offsets of the previous match ("After a failed match attempt, the
    /// contents of the ovector are unchanged",
    /// `doc/html/pcre2api.html:3334`), so the facade clears its own validity
    /// state for every attempt and the capture accessors answer null until one
    /// of them matches.
    pub fn match(
        self: *const Regex,
        subject: []const u8,
        start_offset: usize,
        options: MatchOptions,
        match_data: *MatchData,
        mcontext: ?*MatchContext,
    ) Error!MatchOutcome {
        // The block now describes this attempt and nothing else, including
        // when the attempt is refused below: a block carries no readable
        // capture unless the attempt that last used it matched. PCRE2 keeps
        // the offset vector it wrote last time on every path except the one
        // that matched, so without this the next caller could be handed offsets
        // that belong to a subject it never saw.
        match_data.matched = false;
        match_data.subject = subject;

        // Checked here rather than left to the matcher: PCRE2 would answer
        // the same condition with PCRE2_ERROR_BADOFFSET (-33), and a bound the
        // caller can trip by accident is worth naming as a bound.
        if (start_offset > subject.len) return error.StartOffsetOutOfRange;

        const rc = c.pcre2_match_8(
            self.code.?,
            subject.ptr,
            subject.len,
            start_offset,
            @intCast(options.toBits()),
            match_data.raw,
            if (mcontext) |m| m.raw else null,
        );
        if (rc >= 0) {
            // A return of zero is upstream's way of saying the vector was too
            // small: it fills as much of it as fitted and leaves the rest
            // (`doc/html/pcre2api.html:3308-3312`), so the entries it did not
            // write are still an earlier attempt's. `MatchData.create` refuses
            // a block that cannot hold the pattern's own groups, so that return
            // does not arise from this facade; if it ever did, the accessors
            // would report no range rather than read what was left behind.
            if (rc > 0) match_data.matched = true;
            return .matched;
        }
        return switch (rc) {
            -1 => .no_match, // PCRE2_ERROR_NOMATCH
            -47 => .match_limit, // PCRE2_ERROR_MATCHLIMIT
            -53 => .depth_limit, // PCRE2_ERROR_DEPTHLIMIT
            -63 => .heap_limit, // PCRE2_ERROR_HEAPLIMIT
            -23...-3, -36 => .{ .invalid_utf = .{ .code = rc, .text = diagnostic(rc) } },
            else => .{ .failed = .{ .code = rc, .text = diagnostic(rc) } },
        };
    }
};

/// Builds a `Regex` from a compiled block and reads the pattern information
/// this facade needs once, so `captureCount`, `nameCount` and `nameAt` cost
/// nothing later.
fn fromRaw(code: *c.pcre2_code_8) Error!Regex {
    var capture_count: u32 = 0;
    var name_count: u32 = 0;
    var name_entry_size: u32 = 0;
    // The out-parameter for `PCRE2_INFO_NAMETABLE` is a bare C pointer, and
    // the difference between that and `?[*c]const u8` is the whole reason it
    // is spelled out here. A Zig optional of a C pointer is not a pointer:
    // `?[*c]const u8` is 16 bytes, an 8-byte payload with the tag byte after
    // it, because only `?*T` is given the null-pointer representation (which
    // is why `Regex.code`, an optional of an ordinary pointer, is 8 bytes).
    // `pcre2_pattern_info_8` writes `sizeof(PCRE2_SPTR)` bytes into that
    // payload (`pcre2_pattern_info.c:229-232`) and never touches the tag, so
    // an optional out-parameter comes back still reading as null however many
    // bytes of pointer were written into it. `Regex.name_table` stays
    // optional, because a caller wants to read an absent table; the
    // out-parameter must not be, because PCRE2 does not write the tag.
    var name_table: [*c]const u8 = undefined;
    // For a non-NULL compiled block these four queries are plain field reads
    // that return 0 (`pcre2_pattern_info.c:136-137`, `:221-223`, `:225-227`,
    // `:229-232`); the only nonzero return in the function is the
    // PCRE2_ERROR_BADOPTION default (:242). A failure therefore means the
    // facade asked something the function refuses, and the block is released
    // rather than leaked. The request numbers are the translated header's own
    // constants (`pcre2.h.generic:450`, `:463-465`) rather than numbers
    // written out here, so what this file asks for cannot drift from the
    // header the archive behind it was compiled against.
    if (c.pcre2_pattern_info_8(code, @intCast(c.PCRE2_INFO_CAPTURECOUNT), &capture_count) != 0)
        return failRaw(code, error.PatternInfoUnavailable);
    if (c.pcre2_pattern_info_8(code, @intCast(c.PCRE2_INFO_NAMECOUNT), &name_count) != 0)
        return failRaw(code, error.PatternInfoUnavailable);
    if (c.pcre2_pattern_info_8(code, @intCast(c.PCRE2_INFO_NAMEENTRYSIZE), &name_entry_size) != 0)
        return failRaw(code, error.PatternInfoUnavailable);
    if (c.pcre2_pattern_info_8(code, @intCast(c.PCRE2_INFO_NAMETABLE), @ptrCast(&name_table)) != 0)
        return failRaw(code, error.PatternInfoUnavailable);
    return .{
        .code = code,
        .capture_count = capture_count,
        .name_count = name_count,
        .name_entry_size = name_entry_size,
        .name_table = name_table,
    };
}

fn failRaw(code: *c.pcre2_code_8, err: Error) Error {
    c.pcre2_code_free_8(code);
    return err;
}

// ---------------------------------------------------------------------------
// Match data
// ---------------------------------------------------------------------------

/// The offset vector and the result of the last match on it, owned separately
/// from the pattern.
///
/// PCRE2 fills the vector in place; this facade never copies a capture out of
/// it and never reallocates it, so a capture is a pair of offsets into the
/// caller's own subject. The block is freed by `deinit` and by nothing else,
/// and `Regex.match` does not take ownership of it.
pub const MatchData = struct {
    raw: ?*c.pcre2_match_data_8,
    /// The subject handed to the most recent `Regex.match` on this block,
    /// whichever way that attempt ended. It is a borrow and not a copy, so it
    /// is valid until the next `match` on this block; read it to recover the
    /// bytes a range refers to. While `matched` is true it is the subject the
    /// readable ranges were computed from.
    subject: []const u8 = "",
    /// Whether the offset vector in `raw` was written by the most recent
    /// `Regex.match` on this block.
    ///
    /// `Regex.match` clears it for every attempt and sets it only when
    /// `pcre2_match_8` returned zero or more, because upstream writes
    /// `ovector[]` only on the path that matched
    /// (`src/pcre2_match.c:1045-1053`) and every other path returns through
    /// `src/pcre2_match.c:8184-8222` with the previous vector still in place.
    /// Defaulted, so a fresh block and a partial literal are both valid.
    /// That the previous vector survives a failed attempt is upstream's own
    /// documented contract rather than an inference from control flow:
    /// `doc/html/pcre2api.html:3330-3334`.
    matched: bool = false,

    /// Creates a block sized for `regex`'s capture count.
    ///
    /// `pcre2_match_data_create_from_pattern_8` passes
    /// `top_bracket + 1` to `pcre2_match_data_create_8`, which silently
    /// clamps the pair count to `UINT16_MAX` (`pcre2_match_data.c:57-58`) and
    /// reports no error. The facade checks the clamp instead of letting a
    /// caller read offsets that were never written.
    pub fn create(regex: *const Regex) Error!MatchData {
        const raw = c.pcre2_match_data_create_from_pattern_8(regex.code.?, null) orelse
            return error.OutOfMemory;
        if (c.pcre2_get_ovector_count_8(raw) < regex.capture_count + 1) {
            c.pcre2_match_data_free_8(raw);
            return error.OvectorTooSmall;
        }
        return .{ .raw = raw };
    }

    /// Releases the block. A second call does nothing.
    pub fn deinit(self: *MatchData) void {
        c.pcre2_match_data_free_8(self.raw);
        self.raw = null;
    }

    /// How many groups this block can report, which is one more than the
    /// pattern's highest group number. Every group number this facade accepts
    /// is below this.
    pub inline fn captureCount(self: *const MatchData) u32 {
        return c.pcre2_get_ovector_count_8(self.raw.?);
    }

    /// The byte range of capturing group `number`, or null when there is no
    /// range to report.
    ///
    /// There is no range for either of two reasons: the group did not take
    /// part in the match that filled the block, or the attempt that last used
    /// the block did not match at all. The second is not a guess: PCRE2
    /// writes `ovector[]` only on the path that matched
    /// (`src/pcre2_match.c:1045-1053`), so after `no_match` or any other
    /// negative return the vector still holds an earlier attempt's offsets,
    /// which describe a subject the caller may no longer even be holding.
    pub fn groupRange(self: *const MatchData, number: u32) Error!?Group {
        // The group number first, before the match state: it is a statement
        // about the index the caller passed, and it holds whatever the block
        // last did.
        if (number >= self.captureCount()) return error.NoSuchGroup;
        if (!self.matched) return null;
        const ovector = c.pcre2_get_ovector_pointer_8(self.raw.?);
        const index = @as(usize, number) * 2;
        const start = ovector[index];
        const end = ovector[index + 1];
        if (start == unset or end == unset) return null;
        return .{ .start = start, .end = end };
    }

    /// The text of capturing group `number`, or null when there is no range to
    /// report, for either of the two reasons `groupRange` gives. The slice is
    /// a window on `subject`; see `Regex.match` for the lifetime.
    pub fn group(self: *const MatchData, number: u32) Error!?[]const u8 {
        const range = (try self.groupRange(number)) orelse return null;
        return self.subject[range.start..range.end];
    }

    /// The byte offset PCRE2 recorded for the last attempt.
    ///
    /// On a successful match this is where the match starts. When the attempt
    /// ended in a UTF validity failure it is the offset of the first malformed
    /// code unit, because that is the value the validator's `erroroffset`
    /// and `src/pcre2_match.c:7334` keeps it. Every other negative return leaves
    /// the field untouched, including the two early returns at
    /// `src/pcre2_match.c:7270-7279`, so do not read it after `no_match`,
    /// `match_limit`, `depth_limit`, `heap_limit`, or after a start offset that
    /// is not on a character boundary. Every one of those leaves `matched`
    /// false as well, so the capture accessors are already reporting that
    /// there is nothing to read; this field is the one value that outlives a
    /// failed attempt, which is why it needs the warning.
    pub inline fn startOffset(self: *const MatchData) usize {
        return c.pcre2_get_startchar_8(self.raw.?);
    }
};

// ---------------------------------------------------------------------------
// Match context
// ---------------------------------------------------------------------------

/// The resource ceilings one match attempt runs under, owned.
///
/// Without a context PCRE2 uses the compiled-in defaults from
/// `src/config.h.generic:195`, which is upstream behaviour. Supplying one is
/// how a caller bounds work on a subject an attacker chose, which is why the
/// three ceilings below are the real operations here rather than a
/// convenience: `MatchOutcome` tells a match limit apart from no match
/// precisely because the limit can be reached.
pub const MatchContext = struct {
    raw: ?*c.pcre2_match_context_8,

    /// Creates a context holding upstream's current defaults. The only way
    /// this fails is the allocation in `pcre2_context.c:186-188`.
    pub fn init() Error!MatchContext {
        const raw = c.pcre2_match_context_create_8(null) orelse return error.OutOfMemory;
        return .{ .raw = raw };
    }

    /// Releases the context. A second call does nothing.
    pub fn deinit(self: *MatchContext) void {
        c.pcre2_match_context_free_8(self.raw);
        self.raw = null;
    }

    /// Caps the backtracking work for one attempt. Reaching it is
    /// `MatchOutcome.match_limit`.
    pub inline fn setMatchLimit(self: *MatchContext, limit: u32) void {
        _ = c.pcre2_set_match_limit_8(self.raw.?, limit);
    }

    /// Caps the backtracker depth for one attempt. Reaching it is
    /// `MatchOutcome.depth_limit`.
    pub inline fn setDepthLimit(self: *MatchContext, limit: u32) void {
        _ = c.pcre2_set_depth_limit_8(self.raw.?, limit);
    }

    /// Caps the heap frames one attempt may use. Reaching it is
    /// `MatchOutcome.heap_limit`.
    pub inline fn setHeapLimit(self: *MatchContext, limit: u32) void {
        _ = c.pcre2_set_heap_limit_8(self.raw.?, limit);
    }
};

// ---------------------------------------------------------------------------
// Library information
// ---------------------------------------------------------------------------

/// The version string the linked library reports, for example
/// `"10.49 2026-09-28"`, written into `buffer` and returned as a window on
/// it.
///
/// The buffer belongs to the caller and so does the answer: `buffer[0..len]`
/// is the string and `buffer[len]` is the NUL, both written by the library,
/// and the returned slice borrows that storage instead of anything this
/// function owns. Upstream's advice for this code is the same shape, query
/// the size first and then write into a buffer the caller sized
/// (`doc/pcre2.txt:1466-1475`).
///
/// This is the library answering, not a constant compiled into this file:
/// `pcre2_config.c:236-243` formats the version out of the `PCRE2_MAJOR`,
/// `PCRE2_MINOR`, `PCRE2_PRERELEASE` and `PCRE2_DATE` macros the rest of the
/// C was built with, so it moves when the pin moves and cannot drift from the
/// archive this binary is linked against.
///
/// Every release so far has needed no more than 24 code units
/// (`doc/pcre2.txt:1468-1469`), so a buffer that size or larger cannot be too
/// small for a real release; a caller that has to cope with anything wider can
/// size the buffer from what the first call asks for, which is the count this
/// function compares against.
pub fn version(buffer: []u8) Error![:0]const u8 {
    // The `where == NULL` path is the size query: it returns `1 + strlen(v)`
    // and writes nothing at all (`pcre2_config.c:73-103`, `:241-242`), so the
    // caller's bytes are untouched by the time this function returns, whichever
    // way it returns.
    const required = c.pcre2_config_8(c.PCRE2_CONFIG_VERSION, null);
    // A string request cannot answer zero, because the count is `1 + strlen`
    // of a compile-time literal. Zero therefore means the library declined in
    // the same way a negative return does, and neither is reported here as a
    // version.
    if (required < 1) return error.VersionUnavailable;
    // The count is the string plus its terminating zero (`pcre2_config.c:242`),
    // so it is the whole capacity: a buffer of exactly that many bytes is
    // enough and one byte less is not. Checked here, before the call that
    // writes, because that call has no way to know how big the buffer is.
    const required_capacity: usize = @intCast(required);
    if (buffer.len < required_capacity) return error.VersionBufferTooSmall;

    const written = c.pcre2_config_8(c.PCRE2_CONFIG_VERSION, buffer.ptr);
    if (written < 1) return error.VersionUnavailable;
    // `strcpy_c8` copied the string, wrote the zero after it
    // (`pcre2_string_utils.c:191-196`) and returned its length, which is this
    // count less one. The sentinel below is a check that the byte at that
    // offset really is that zero rather than an assumption about it, and the
    // slice cannot reach past `buffer.len` because the buffer was sized from
    // the count this same call returned.
    const length: usize = @intCast(written - 1);
    return buffer[0..length :0];
}
