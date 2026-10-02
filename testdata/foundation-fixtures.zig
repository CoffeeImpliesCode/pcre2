//! Independent known answers for the PCRE2 facade.
//!
//! Every expectation here was read out of this repository's own `testdata/`,
//! which is upstream's own `pcre2test` input and expected output for release
//! 10.49, or was worked out by hand from the C source and says so. Nothing in
//! this file was produced by running this fork, so a test that agrees with it
//! is agreeing with PCRE2 and not with itself.
//!
//! Three provenance classes appear below, and each fixture names which one it
//! is in its `provenance` field:
//!
//!   * `testdata/testoutput2` is the 8-bit, non-UTF, JIT-off expected output
//!     for `testdata/testinput2`. `testdata/testoutput5` is the same library
//!     with `utf` patterns. Both are what upstream's `RunTest` compares a
//!     freshly built `pcre2test` against.
//!   * `testdata/testoutput15` and `testdata/testoutput6` are upstream's
//!     dedicated limit tests: test 15 for match and depth limits, test 6 for
//!     heap limits.
//!   * Two UTF validity cases are hand-derived from `src/pcre2_valid_utf.c`
//!     and `src/pcre2_match.c`, because no checked-in test output exercises a
//!     malformed subject. The derivation is written out in full on the case.
//!
//! About JIT: every number below is the interpreted answer. This fork builds
//! with `SUPPORT_JIT` off, so those are the numbers its library can produce.
//! A JIT-only case is NOT EXERCISED here and must not be reported as passing.
//!
//! These expectations are pinned to PCRE2 10.49, the release this repository
//! is a fork of, because that is the `testdata/` that ships with it. A build
//! linked against a different system PCRE2, in `-fsys` mode, can legitimately
//! disagree: a compile error offset or a capture layout that changed between
//! releases is a real behavioural difference between two versions, not a
//! binding fault, and it must not be "fixed" here by loosening a fixture.
//! Read a red system-mode gate that way first.

const pcre2 = @import("pcre2");

/// The three ceilings a caller can impose through `pcre2.MatchContext`.
/// A null field means "leave the compiled-in default alone", which is what
/// upstream's `pcre2test` does when the subject line carries no `\=limit=`
/// modifier.
pub const Limits = struct {
    match: ?u32 = null,
    depth: ?u32 = null,
    heap: ?u32 = null,
};

/// What `pcre2_compile` must answer.
pub const CompileAnswer = union(enum) {
    compiled,
    rejected: struct {
        /// The number upstream printed after "error".
        code: i32,
        /// The byte offset upstream printed after "at offset".
        offset: usize,
        /// The sentence upstream printed after the colon.
        text: []const u8,
    },
};

/// What `pcre2_match` must answer.
pub const MatchAnswer = union(enum) {
    matched: []const Capture,
    no_match,
    match_limit,
    depth_limit,
    heap_limit,
    /// A UTF validity failure, with the exact number upstream returns.
    invalid_utf: struct {
        code: i32,
        text: []const u8,
        /// The byte offset `pcre2_get_startchar` reports afterwards, or null
        /// for the two early returns at `pcre2_match.c:7270-7279` that leave
        /// the field untouched.
        bad_offset: ?usize,
    },
    /// Any other negative return, with the number. Used to pin a code the
    /// facade deliberately does not split out.
    other: i32,
};

/// One capturing group, as upstream's `pcre2test` prints it under `\g`.
/// A null `bytes` is upstream's `<unset>`, which is `PCRE2_UNSET` in the
/// offset vector.
pub const Capture = struct {
    number: u32,
    bytes: ?[]const u8,
};

/// One entry of upstream's name table, in the order `pcre2test` prints it
/// under "Named capture groups".
pub const Named = struct {
    number: u32,
    name: []const u8,
};

/// One known answer.
pub const Case = struct {
    /// A short slug, used as the test name so a failure names the fixture.
    name: []const u8,
    /// Where the expected numbers come from, so a reader can go and look.
    provenance: []const u8,
    pattern: []const u8,
    compile: pcre2.CompileOptions = .{},
    compile_answer: CompileAnswer = .compiled,
    subject: []const u8,
    start_offset: usize = 0,
    match_options: pcre2.MatchOptions = .{},
    limits: Limits = .{},
    answer: CaseAnswer = null,
    /// Checked only when the pattern has names. Upstream's highest group
    /// number, so `captureCount()` has something to compare against.
    capture_count: ?u32 = null,
    /// Checked only when the pattern has names.
    names: []const Named = &.{},
};

/// The subject of upstream's heap-limit tests.
///
/// `testdata/testinput6:4935` is 120 bytes: one `a`, then 23 copies of the
/// five literal characters `[00](`, then `[00]`. The literal characters are
/// not backslash escapes, so the bytes really are the printable characters
/// `[`, `0`, `]`, `(`. Built by repetition so the count is the thing a
/// reader checks, and so a mistyped copy cannot pass for a deliberate edit.
const heap_subject_bytes = blk: {
    const open = "[00](";
    const close = "[00]";
    const repeats = 23;
    const total = 1 + repeats * open.len + close.len;
    var buf: [total]u8 = undefined;
    buf[0] = 'a';
    var at: usize = 1;
    for (0..repeats) |_| {
        @memcpy(buf[at..][0..open.len], open);
        at += open.len;
    }
    @memcpy(buf[at..][0..close.len], close);
    at += close.len;
    if (at != total or total != 120)
        @compileError("the heap-limit subject must be the 120 bytes of testdata/testinput6:4935");
    break :blk buf;
};

/// See `heap_subject_bytes`. 120 bytes long.
pub const heap_subject: []const u8 = &heap_subject_bytes;

/// The subject of upstream's limit tests, 14 bytes: 13 `a` and a `z`.
/// `testdata/testinput15:61`.
pub const a_run_then_z: []const u8 = "aaaaaaaaaaaaaz";

comptime {
    // A mistyped run of a's is the one way these two subjects could drift
    // away from the files they were read out of without any of it showing up
    // as a length error anywhere else.
    if (a_run_then_z.len != 14 or a_run_then_z[13] != 'z')
        @compileError("a_run_then_z must be 13 'a' followed by 'z', as in testdata/testinput15:61");
}

/// What `pcre2_match` must answer. Null for a pattern upstream refused: there
/// is nothing to match with, and a placeholder answer would be a claim nobody
/// checked.
pub const CaseAnswer = ?MatchAnswer;

/// Every known answer, in the order a reader would want to meet them.
pub const cases = [_]Case{
    // -- captures ----------------------------------------------------------
    .{
        .name = "named_captures_report_byte_offsets",
        .provenance =
        \\testdata/testoutput2:7310-7323, from testdata/testinput2:1798-1799.
        \\pcre2test prints the name table, then group 0 as "xy" and groups 1
        \\and 2 as the single bytes "x" and "y", under \g.
        ,
        .pattern = "(?<abc>x)(?'xyz'y)",
        .subject = "xy",
        .answer = .{ .matched = &.{
            .{ .number = 0, .bytes = "xy" },
            .{ .number = 1, .bytes = "x" },
            .{ .number = 2, .bytes = "y" },
        } },
        .capture_count = 2,
        .names = &.{
            .{ .number = 1, .name = "abc" },
            .{ .number = 2, .name = "xyz" },
        },
    },
    .{
        .name = "group_that_did_not_participate_is_unset",
        .provenance =
        \\testdata/testoutput2:284-291, from the block headed
        \\"/(a)bc|(a)(b)\2/I" in testdata/testinput2. The subject "abc" takes
        \\the first alternative, so pcre2test prints group 0, group 1 and
        \\nothing at all for groups 2 and 3. Upstream records the gap as
        \\PCRE2_UNSET (pcre2_match.c:1036-1037) and pcre2test renders that as
        \\<unset>, which is the null case here.
        ,
        .pattern = "(a)bc|(a)(b)\\2",
        .subject = "abc",
        .capture_count = 3,
        .answer = .{ .matched = &.{
            .{ .number = 0, .bytes = "abc" },
            .{ .number = 1, .bytes = "a" },
            .{ .number = 2, .bytes = null },
            .{ .number = 3, .bytes = null },
        } },
    },

    // -- compile rejection -------------------------------------------------
    .{
        .name = "unmatched_closing_parenthesis_is_rejected_at_its_offset",
        .provenance =
        \\testdata/testoutput2:395-396, from testdata/testinput2. pcre2test
        \\prints "Failed: error 122 at offset 1: unmatched closing
        \\parenthesis", and 122 is ERR22 by src/pcre2_compile.h:55-60, whose
        \\text is the 23rd entry of compile_error_texts in src/pcre2_error.c.
        ,
        .pattern = ")",
        .subject = "",
        .compile_answer = .{ .rejected = .{
            .code = 122,
            .offset = 1,
            .text = "unmatched closing parenthesis",
        } },
    },
    .{
        .name = "character_class_without_a_terminator_is_rejected",
        .provenance =
        \\testdata/testoutput2:399-400: "Failed: error 106 at offset 4:
        \\missing terminating ] for character class". Offset 4 is one past
        \\the last byte of the four-byte pattern "a[]b", which is where
        \\pcre2test's own caret marker points.
        ,
        .pattern = "a[]b",
        .subject = "",
        .compile_answer = .{ .rejected = .{
            .code = 106,
            .offset = 4,
            .text = "missing terminating ] for character class",
        } },
    },
    .{
        .name = "unterminated_group_name_is_rejected",
        .provenance =
        \\testdata/testoutput2:7325-7326: "Failed: error 142 at offset 6:
        \\syntax error in subpattern name (missing terminator?)". Offset 6 is
        \\the apostrophe in "(?<abc'x)".
        ,
        .pattern = "(?<abc'x)(?'xyz'y)",
        .subject = "",
        .compile_answer = .{ .rejected = .{
            .code = 142,
            .offset = 6,
            .text = "syntax error in subpattern name (missing terminator?)",
        } },
    },

    // -- options that change the answer ------------------------------------
    .{
        .name = "dollar_endonly_rejects_a_trailing_newline",
        .provenance =
        \\testdata/testoutput2:329-339, from testdata/testinput2:130-133.
        \\With dollar_endonly the pattern "abc$" must not match "abc\n", and
        \\pcre2test prints "No match" on the line after that subject.
        ,
        .pattern = "abc$",
        .compile = .{ .dollar_endonly = true },
        .subject = "abc\n",
        .answer = .no_match,
    },

    // -- UTF ---------------------------------------------------------------
    .{
        .name = "utf_capture_offsets_are_byte_offsets",
        .provenance =
        \\testdata/testoutput5:4239-4246, from testdata/testinput5. The
        \\pattern is "/../utf,auto_callout"; auto_callout only inserts
        \\callout operations and cannot move a match, so the facade does not
        \\set it. The subject is a newline followed by U+0123 four times, nine
        \\bytes long, and pcre2test prints group 0 as the two characters after
        \\the newline. U+0123 encodes as 0xC4 0xA3, so a dot matches two bytes
        \\and the match is bytes 1 through 5.
        ,
        .pattern = "..",
        .compile = .{ .utf = true },
        .subject = "\n\u{123}\u{123}\u{123}\u{123}",
        .answer = .{ .matched = &.{
            .{ .number = 0, .bytes = "\u{123}\u{123}" },
        } },
    },
    .{
        .name = "overlong_two_byte_sequence_is_an_invalid_utf_failure",
        .provenance =
        \\Hand-derived, because no checked-in test output uses a malformed
        \\subject. Walking src/pcre2_valid_utf.c for the subject "A\xC0\xAF",
        \\whose bytes are 0x41 0xC0 0xAF: 0x41 is below 128 and is skipped at
        \\:140; 0xC0 fails neither the "isolated 0x80 byte" test at :142-146
        \\nor the 0xfe/0xff test at :148-152; :154 looks up one additional
        \\byte in PRIV(utf8_table4); :155-166 finds a byte available, so no
        \\"missing at end" return; :171 finds 0xAF's top bits are 0x10, which
        \\is 0x80 as required; and the case 1 arm at :186-190 evaluates
        \\"(c & 0x3e) == 0" for 0xC0, which is true, so it stores
        \\"(p - string) - 1". p is then at index 2, so the stored offset is 1,
        \\and it returns PCRE2_ERROR_UTF8_ERR15. src/pcre2_match.c:7334 keeps
        \\that offset and :7335 returns the code, because
        \\PCRE2_MATCH_INVALID_UTF is not set. The 17th entry of
        \\match_error_texts in src/pcre2_error.c is "UTF-8 error: overlong
        \\2-byte sequence".
        ,
        .pattern = ".",
        .compile = .{ .utf = true },
        .subject = "A\xC0\xAF",
        .answer = .{ .invalid_utf = .{
            .code = -17,
            .text = "UTF-8 error: overlong 2-byte sequence",
            .bad_offset = 1,
        } },
    },
    .{
        .name = "isolated_continuation_byte_is_an_invalid_utf_failure",
        .provenance =
        \\Hand-derived, for the same reason. src/pcre2_match.c:7270-7279 runs
        \\before the validator: the subject is not empty, NOT_FIRSTCU is true
        \\for 0x80, and the start offset is 0, so the interpreter returns
        \\PCRE2_ERROR_UTF8_ERR20 immediately. That path does not write
        \\startchar, which is why bad_offset is null and why this facade
        \\documents startOffset as meaningful only after a match or after a
        \\validity failure that went through the validator. The 22nd entry of
        \\match_error_texts in src/pcre2_error.c is "UTF-8 error: isolated byte
        \\with 0x80 bit set".
        ,
        .pattern = ".",
        .compile = .{ .utf = true },
        .subject = "\x80",
        .answer = .{ .invalid_utf = .{
            .code = -22,
            .text = "UTF-8 error: isolated byte with 0x80 bit set",
            .bad_offset = null,
        } },
    },

    // -- no match against the three resource ceilings ----------------------
    .{
        .name = "run_of_a_against_a_trailing_zz_does_not_match",
        .provenance =
        \\testdata/testoutput15:128-131, from testdata/testinput15:60-62.
        \\With no limit modifier, pcre2test prints "No match" for the subject
        \\"aaaaaaaaaaaaaz" against "(a+)*zz". This is the control for the two
        \\cases below: identical pattern, identical subject, and the only
        \\difference is a ceiling.
        ,
        .pattern = "(a+)*zz",
        .subject = a_run_then_z,
        .answer = .no_match,
    },
    .{
        .name = "match_limit_is_not_a_non_match",
        .provenance =
        \\testdata/testoutput15:132-134. The same pattern and subject with
        \\\=match_limit=3000 print "Failed: error -47: match limit exceeded",
        \\not "No match". An attacker who can pick a subject must not be able
        \\to make a resource refusal look like an ordinary miss.
        ,
        .pattern = "(a+)*zz",
        .subject = a_run_then_z,
        .limits = .{ .match = 3000 },
        .answer = .match_limit,
    },
    .{
        .name = "depth_limit_is_not_a_non_match",
        .provenance =
        \\testdata/testoutput15:136-139. The same pattern and subject with
        \\\=depth_limit=10 print "Failed: error -53: matching depth limit
        \\exceeded".
        ,
        .pattern = "(a+)*zz",
        .subject = a_run_then_z,
        .limits = .{ .depth = 10 },
        .answer = .depth_limit,
    },
    .{
        .name = "heap_limit_is_not_a_non_match",
        .provenance =
        \\testdata/testoutput6:7734-7737. The pattern there is spelled
        \\"(*LIMIT_HEAP=0)^((.)(?1)|.)$", and (*LIMIT_HEAP=n) is pcre2test
        \\setting the heap limit on the match context rather than anything in
        \\the pattern, so the facade sets the same ceiling through
        \\MatchContext and compiles the pattern without the verb. The subject
        \\is the 120-byte literal in testdata/testinput6:4935. The expected
        \\line is "Failed: error -63: heap limit exceeded".
        ,
        .pattern = "^((.)(?1)|.)$",
        .subject = heap_subject,
        .limits = .{ .heap = 0 },
        .answer = .heap_limit,
    },
    .{
        .name = "the_same_pattern_matches_once_the_heap_ceiling_is_raised",
        .provenance =
        \\testdata/testoutput6:7739-7742. The control for the case above: the
        \\same pattern and the same 120-byte subject with the heap limit at
        \\50000 match the whole subject, which pcre2test prints as group 0.
        ,
        .pattern = "^((.)(?1)|.)$",
        .subject = heap_subject,
        .limits = .{ .heap = 50000 },
        .answer = .{ .matched = &.{
            .{ .number = 0, .bytes = heap_subject },
        } },
    },
    .{
        .name = "disabling_the_recursion_check_reaches_the_match_limit",
        .provenance =
        \\testdata/testoutput2:19532-19534. The pattern "(?0)" recurses into
        \\itself at the same subject position, so with the recursion check in
        \\force PCRE2 reports PCRE2_ERROR_RECURSELOOP before it ever reaches
        \\the match limit. pcre2test's subject line here carries
        \\\=disable_recurseloop_check,match_limit=100 and the expected line is
        \\"Failed: error -47: match limit exceeded". Both modifiers are set
        \\here, one as a match option and one as a ceiling.
        ,
        .pattern = "(?0)",
        .subject = "abc",
        .match_options = .{ .disable_recurseloop_check = true },
        .limits = .{ .match = 100 },
        .answer = .match_limit,
    },
};
