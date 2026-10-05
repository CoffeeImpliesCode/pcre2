//! Behavioural tests for the PCRE2 facade.
//!
//! The expectations live in `testdata/foundation-fixtures.zig` and came out of
//! this repository's own `testdata/`, which is upstream's `pcre2test` input and
//! expected output for release 10.49, or were worked out by hand from the C and
//! say so. Nothing here was produced by running this fork, so a passing test is
//! PCRE2 agreeing with itself, not this binding agreeing with itself.
//!
//! ## Every width, not one
//!
//! `pcre2.h` publishes three libraries through one header and this build
//! compiles one of them, so a test that only ever spoke bytes would be a test of
//! the 8-bit library wearing the name of a test of PCRE2. Two helpers at the top
//! move a fixture's byte data into the compiled width's code units and back:
//!
//!   * a case marked `utf_bytes` is **decoded** from UTF-8, because its code
//!     points are what the pattern means, and its captures are compared after
//!     being re-encoded, so the same answer is checked in the terms each width
//!     uses;
//!   * every other case is **widened** one byte per code unit, which is exact
//!     for a pattern of ASCII literals and is what a byte-oriented expected
//!     output means at every width.
//!
//! Two cases are marked `eight_bit_only`, and both are kept rather than
//! loosened: they pin the 8-bit validator's own error numbers, which a 16- or
//! 32-bit library does not share. The statement all three widths do share is
//! checked separately, from `fixtures.malformed_units`, rather than by making
//! those two cases conditional on nothing.
//!
//! ## What is checked
//!
//! The known answers; the bounds the facade owns itself, which upstream would
//! answer differently or not at all; the lifetime of a capture, which is a
//! window on the caller's own buffer rather than a copy of it; and the parts of
//! the surface that only exist to own something -- the allocator, the JIT
//! refusal, substitution, the DFA matcher, serialization and the POSIX wrapper.
//! Those are behavioural because they are observable from outside: what was
//! called, what came back, and who released it.
//!
//! Nothing here compares a facade accessor with `pcre2.c`. Agreement between a
//! wrapper and the member it wraps is not evidence about PCRE2.

const std = @import("std");
const pcre2 = @import("pcre2");
const fixtures = @import("foundation_fixtures");

/// Load the explicit test provider once. Linked tests need no startup call.
fn nativeReady() void {
    if (comptime !pcre2.runtime_loaded) return;
    if (pcre2.loadedSource() != null) return;
    const path = std.testing.environ.getAlloc(std.testing.allocator, "PCRE2_TEST_PROVIDER") catch
        @panic("Set PCRE2_TEST_PROVIDER before running runtime-loaded tests");
    defer std.testing.allocator.free(path);
    pcre2.load(.{ .path = path }) catch |err| {
        std.debug.print("PCRE2_TEST_PROVIDER \"{s}\": {s}\n", .{ path, @errorName(err) });
        @panic("The explicit PCRE2 test provider could not load");
    };
}

/// The code unit this build compiled.
const Unit = pcre2.compiled_unit;

/// Which entry of `fixtures.malformed_units` this width uses.
const malformed_index: usize = switch (pcre2.compiled_width) {
    .@"8" => 0,
    .@"16" => 1,
    .@"32" => 2,
};

// ---------------------------------------------------------------------------
// Moving a fixture's bytes into this width's code units
// ---------------------------------------------------------------------------

/// Widen `bytes` into `out`, one byte per code unit.
///
/// Exact for a pattern of ASCII literals, which is what every non-`utf_bytes`
/// fixture is. A byte above what the width's code unit can hold is a caller
/// mistake rather than something to truncate silently, so it is refused.
fn widen(ascii: []const u8, out: []Unit) ![]const Unit {
    if (out.len < ascii.len) return error.BenchmarkWorkspaceTooSmall;
    for (ascii, 0..) |byte, i| {
        if (byte > std.math.maxInt(Unit)) return error.BenchmarkWorkspaceTooSmall;
        out[i] = byte;
    }
    return out[0..ascii.len];
}

/// Preserve UTF-8 bytes at width 8. Decode code points for width 32, or
/// encode them as UTF-16 code units for width 16.
fn widenUtf8(bytes: []const u8, out: []Unit) ![]const Unit {
    if (Unit == u8) {
        if (bytes.len > out.len) return error.BenchmarkWorkspaceTooSmall;
        @memcpy(out[0..bytes.len], bytes);
        return out[0..bytes.len];
    }
    var at: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) {
        const width: usize = try std.unicode.utf8ByteSequenceLength(bytes[i]);
        if (width > bytes.len - i) return error.InvalidUtf8;
        const value: u21 = switch (width) {
            1 => bytes[i],
            2 => try std.unicode.utf8Decode2(bytes[i..][0..2].*),
            3 => try std.unicode.utf8Decode3(bytes[i..][0..3].*),
            4 => try std.unicode.utf8Decode4(bytes[i..][0..4].*),
            else => unreachable,
        };
        const pair = Unit == u16 and value > 0xffff;
        const needed: usize = if (pair) 2 else 1;
        if (needed > out.len - at) return error.BenchmarkWorkspaceTooSmall;
        if (pair) {
            const supplementary = value - 0x10000;
            out[at] = @intCast(0xd800 + (supplementary >> 10));
            out[at + 1] = @intCast(0xdc00 + (supplementary & 0x3ff));
        } else {
            out[at] = @intCast(value);
        }
        at += needed;
        i += width;
    }
    return out[0..at];
}

/// The fixture's answer in this width's code units.
fn subjectOf(case: fixtures.Case, scratch: []Unit) ![]const Unit {
    return if (case.utf_bytes)
        widenUtf8(case.subject, scratch)
    else
        widen(case.subject, scratch);
}

/// A capture as the bytes the fixture wrote down.
///
/// `utf` selects re-encoding over narrowing, and a code unit that is not a byte
/// is refused rather than dropped, so a mismatch here is a real difference and
/// not a truncation.
fn render(out: []u8, units: []const Unit, utf: bool) ![]const u8 {
    if (!utf or Unit == u8) {
        if (out.len < units.len) return error.BenchmarkWorkspaceTooSmall;
        for (units, 0..) |unit, i| {
            if (unit > std.math.maxInt(u8)) return error.BenchmarkWorkspaceTooSmall;
            out[i] = @intCast(unit);
        }
        return out[0..units.len];
    }
    var at: usize = 0;
    var i: usize = 0;
    while (i < units.len) : (i += 1) {
        var value: u32 = units[i];
        if (Unit == u16 and value >= 0xd800 and value <= 0xdbff) {
            i += 1;
            if (i >= units.len or units[i] < 0xdc00 or units[i] > 0xdfff) return error.InvalidUtf16;
            value = 0x10000 + ((value - 0xd800) << 10) + (units[i] - 0xdc00);
        }
        if (value > 0x10ffff) return error.InvalidCodepoint;
        var encoded: [4]u8 = undefined;
        const width = try std.unicode.utf8Encode(@intCast(value), &encoded);
        if (width > out.len - at) return error.BenchmarkWorkspaceTooSmall;
        @memcpy(out[at..][0..width], encoded[0..width]);
        at += width;
    }
    return out[0..at];
}

/// Compiles a pattern the test expects PCRE2 to accept.
///
/// The union is unwrapped through a switch rather than by naming the field,
/// so a pattern that unexpectedly does not compile reports the diagnostic
/// upstream gave instead of tripping a union-tag safety panic.
fn mustCompile(pattern: []const Unit, options: pcre2.CompileOptions) !pcre2.Regex {
    return switch (try pcre2.Regex.compile(pattern, options)) {
        .compiled => |regex| regex,
        .rejected => |rejection| {
            std.debug.print("pattern of {d} code units was rejected: error {d} at offset {d}\n", .{
                pattern.len,
                rejection.code,
                rejection.offset,
            });
            return error.FixtureMismatch;
        },
    };
}

// ---------------------------------------------------------------------------
// The known answers
// ---------------------------------------------------------------------------

test "every known answer in the fixture table holds" {
    nativeReady();
    var pattern_units: [512]Unit = undefined;
    var subject_units: [512]Unit = undefined;
    // The names are widened into a buffer of their own rather than into
    // `subject_units`: `subject` below is a window into that one, and the match
    // this loop goes on to make is run against it.
    var name_workspace: [pcre2.max_name_length]Unit = undefined;
    var rendered: [1024]u8 = undefined;

    for (fixtures.cases) |case| {
        if (case.eight_bit_only and pcre2.compiled_width != .@"8") continue;
        const pattern = try if (case.utf_bytes)
            widenUtf8(case.pattern, &pattern_units)
        else
            widen(case.pattern, &pattern_units);
        const subject = try subjectOf(case, &subject_units);

        var compiled = switch (try pcre2.Regex.compile(pattern, case.compile)) {
            .compiled => |regex| regex,
            .rejected => |rejection| {
                const expected = switch (case.compile_answer) {
                    .rejected => |want| want,
                    .compiled => {
                        std.debug.print(
                            "fixture {s}: pcre2_compile rejected {s} with {d} at offset {d}, " ++
                                "but the fixture says it compiles\n",
                            .{ case.name, case.pattern, rejection.code, rejection.offset },
                        );
                        return error.FixtureMismatch;
                    },
                };
                // The three things a caller needs in order to point a user at
                // the offending code unit of the pattern.
                try std.testing.expectEqual(expected.code, rejection.code);
                try std.testing.expectEqual(expected.offset, rejection.offset);
                continue;
            },
        };
        defer compiled.deinit();

        if (case.capture_count) |expected| {
            try std.testing.expectEqual(expected, compiled.captureCount());
        }
        // Every fixture that declares names declares all of them, so the count
        // is a real comparison rather than a tautology.
        try std.testing.expectEqual(@as(u32, @intCast(case.names.len)), compiled.nameCount());
        for (case.names, 0..) |named, i| {
            const entry = compiled.nameAt(@intCast(i)) orelse return error.FixtureMismatch;
            try std.testing.expectEqual(named.number, entry.number);
            // A name is code units of this width, not bytes
            // (`src/pcre2_compile_cgroup.c:168`), so both directions are
            // converted rather than compared as text: the table's own units
            // narrow to the fixture's bytes, and the fixture's bytes widen
            // back for the lookups.
            try std.testing.expectEqualStrings(
                named.name,
                try render(&rendered, entry.name, false),
            );
            const name_units = try widen(named.name, &name_workspace);
            try std.testing.expectEqualSlices(
                Unit,
                name_units,
                compiled.nameForNumber(named.number) orelse return error.FixtureMismatch,
            );
            try std.testing.expectEqual(
                named.number,
                compiled.numberForName(name_units) orelse return error.FixtureMismatch,
            );
        }

        var match_data = try pcre2.MatchData.create(&compiled);
        defer match_data.deinit();
        // The block covers group 0 through the pattern's highest group, which
        // is what makes `groupRange` a bounds check and not a guess.
        try std.testing.expectEqual(compiled.captureCount() + 1, match_data.captureCount());

        var context = try pcre2.MatchContext.init();
        defer context.deinit();
        if (case.limits.match) |limit| context.setMatchLimit(limit);
        if (case.limits.depth) |limit| context.setDepthLimit(limit);
        if (case.limits.heap) |limit| context.setHeapLimit(limit);

        const result = try compiled.match(subject, case.start_offset, case.match_options, &match_data, &context);
        try expectAnswer(case, result, &compiled, &match_data, &rendered);
    }
}

/// Compares one `MatchOutcome` against the fixture's answer, group by group
/// where it matched.
fn expectAnswer(
    case: fixtures.Case,
    result: pcre2.MatchOutcome,
    regex: *const pcre2.Regex,
    match_data: *const pcre2.MatchData,
    rendered: []u8,
) !void {
    const expected = case.answer orelse {
        std.debug.print(
            "fixture {s} ({s}): pcre2_compile accepted the pattern, so there is " ++
                "a subject to match, but the fixture records no match answer\n",
            .{ case.name, case.provenance },
        );
        return error.FixtureMismatch;
    };
    switch (result) {
        .matched => {
            const captures = switch (expected) {
                .matched => |want| want,
                else => return mismatch(case, "matched", @tagName(expected)),
            };
            // The listed groups must run 0, 1, 2 ... with no gap, because a
            // group dropped from the middle of a fixture is a fixture that
            // stopped checking something. They need not reach the pattern's
            // highest group: upstream's heap-limit case
            // "testdata/testoutput6:7739" pins group 0 only, and the nested
            // captures a recursive pattern leaves behind are not something a
            // reader can confirm by looking at the expected output.
            for (captures, 0..) |want, i| {
                try std.testing.expectEqual(@as(u32, @intCast(i)), want.number);
                // A listed group that the pattern does not have would make
                // the loop below check an offset the block never wrote.
                try std.testing.expect(want.number <= regex.captureCount());
                const range = try match_data.groupRange(want.number);
                const text = try match_data.group(want.number);
                if (want.bytes) |bytes| {
                    const got = text orelse return mismatch(case, "a capture", "unset");
                    try std.testing.expectEqualStrings(
                        bytes,
                        try render(rendered, got, case.utf_bytes),
                    );
                    const found = range orelse return mismatch(case, "a capture", "unset");
                    try std.testing.expectEqualStrings(
                        bytes,
                        try render(rendered, match_data.subject[found.start..found.end], case.utf_bytes),
                    );
                } else {
                    if (range != null) return mismatch(case, "unset", "a range");
                    if (text != null) return mismatch(case, "unset", "a capture");
                }
            }
        },
        .no_match => switch (expected) {
            .no_match => {},
            else => return mismatch(case, "no_match", @tagName(expected)),
        },
        .match_limit => switch (expected) {
            .match_limit => {},
            else => return mismatch(case, "match_limit", @tagName(expected)),
        },
        .depth_limit => switch (expected) {
            .depth_limit => {},
            else => return mismatch(case, "depth_limit", @tagName(expected)),
        },
        .heap_limit => switch (expected) {
            .heap_limit => {},
            else => return mismatch(case, "heap_limit", @tagName(expected)),
        },
        .invalid_utf => |got| {
            const want = switch (expected) {
                .invalid_utf => |utf| utf,
                else => return mismatch(case, "invalid_utf", @tagName(expected)),
            };
            try std.testing.expectEqual(want.code, got.code);
            try std.testing.expectEqualStrings(want.text, try render(rendered, got.text.slice(), case.utf_bytes));
            // Only the validity failures that went through pcre2_valid_utf
            // write the offending offset; the two early returns at
            // pcre2_match.c:7270-7279 do not, and the fixture says so.
            if (want.bad_offset) |offset| {
                try std.testing.expectEqual(offset, match_data.startOffset());
            }
        },
        .failed => |got| {
            const want = switch (expected) {
                .other => |code| code,
                else => return mismatch(case, "failed", @tagName(expected)),
            };
            try std.testing.expectEqual(want, got.code);
        },
    }
}

fn mismatch(
    case: fixtures.Case,
    got: []const u8,
    want: []const u8,
) error{TestExpectedEqual} {
    std.debug.print(
        "fixture {s} ({s}): pcre2 answered {s}, the known answer is {s}\n",
        .{ case.name, case.provenance, got, want },
    );
    return error.TestExpectedEqual;
}

test "a subject this width's validator cannot read is a validity failure" {
    nativeReady();
    // One code unit per width that the width's own UTF validator refuses, so
    // the assertion is about the validator refusing and not about any one
    // width's numbering of it. The 8-bit numbers are upstream's, and are pinned
    // by the two fixture cases marked `eight_bit_only`.
    var units: [4]Unit = undefined;
    const wanted = fixtures.malformed_units[malformed_index];
    for (wanted, 0..) |value, i| {
        units[i] = @intCast(value);
    }
    const subject = units[0..wanted.len];

    var regex = try mustCompile(&[_]Unit{ '.' }, .{ .utf = true });
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match(subject, 0, .{}, &match_data, null)) {
        .invalid_utf => {
            try std.testing.expect(!match_data.matched);
        },
        else => return error.FixtureMismatch,
    }
}

// ---------------------------------------------------------------------------
// Bounds the facade owns
// ---------------------------------------------------------------------------

test "a start offset past the end of the subject is refused before matching" {
    nativeReady();
    var regex = try mustCompile(widenLiteral("abc"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    // One past the end of a three unit subject. PCRE2 answers this itself with
    // PCRE2_ERROR_BADOFFSET, from inside the matcher; the facade names the
    // condition instead, so a caller can act on it before spending a match.
    try std.testing.expectError(
        error.StartOffsetOutOfRange,
        regex.match(widenLiteral("abc"), 4, .{}, &match_data, null),
    );
    // Exactly the end of the subject is in range, and a pattern that needs
    // three units simply does not match there.
    switch (try regex.match(widenLiteral("abc"), 3, .{}, &match_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
}

test "a group number past the block's capture count is refused" {
    nativeReady();
    var regex = try mustCompile(widenLiteral("(a)(b)"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    try std.testing.expectEqual(@as(u32, 2), regex.captureCount());
    try std.testing.expectEqual(@as(u32, 3), match_data.captureCount());
    switch (try regex.match(widenLiteral("ab"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    // Group 3 does not exist. Reading it would be past the end of PCRE2's
    // offset vector, so the facade says so instead of indexing.
    try std.testing.expectError(error.NoSuchGroup, match_data.groupRange(3));
    try std.testing.expectError(error.NoSuchGroup, match_data.group(3));
}

test "a block too small for the regex is refused, and its earlier captures go with it" {
    nativeReady();
    // One block, two patterns, and the second one needs more offset-vector
    // pairs than the first. `MatchData.create` sized this block for `small`,
    // and nothing about the block remembers which pattern that was.
    var small = try mustCompile(widenLiteral("abc"), .{});
    defer small.deinit();
    var match_data = try pcre2.MatchData.create(&small);
    defer match_data.deinit();

    // The state a caller can read before the refusal, so that "nothing is
    // readable afterwards" is a change and not a property of an empty block.
    try std.testing.expectEqual(@as(u32, 0), small.captureCount());
    try std.testing.expectEqual(@as(u32, 1), match_data.captureCount());
    switch (try small.match(widenLiteral("abc"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(Unit,
        widenLiteral("abc"),
        (try match_data.group(0)) orelse return error.FixtureMismatch,
    );

    var larger = try mustCompile(widenLiteral("(a)(b)(c)"), .{});
    defer larger.deinit();
    try std.testing.expectEqual(@as(u32, 3), larger.captureCount());

    // Upstream's own answer to this is a return of zero: it fills what fits
    // and reports that the vector was too small
    // (`doc/html/pcre2api.html:3308-3312`). The facade refuses before matching,
    // so the caller learns that its block and its pattern do not belong
    // together rather than receiving a match it cannot read.
    try std.testing.expectError(
        error.OvectorTooSmall,
        larger.match(widenLiteral("abc"), 0, .{}, &match_data, null),
    );

    // The refusal is not a pause. PCRE2 leaves the offset vector of the last
    // match in place across every path that did not match
    // (`doc/html/pcre2api.html:3330-3334`), so the "abc" offsets from above are
    // still in the block and describe a subject this attempt never ran
    // against. The block reports nothing rather than handing them back.
    try std.testing.expect(!match_data.matched);
    try std.testing.expect((try match_data.groupRange(0)) == null);
    try std.testing.expect((try match_data.group(0)) == null);
    // The group-number bound is a statement about the index and holds whatever
    // the block last did: group 1 is past this block's own count, so it is
    // `NoSuchGroup` rather than an unreadable range.
    try std.testing.expectError(error.NoSuchGroup, match_data.groupRange(1));

    // A pattern the block does fit re-arms it, and the captures are that
    // subject's own.
    switch (try small.match(widenLiteral("abc"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(Unit,
        widenLiteral("abc"),
        (try match_data.group(0)) orelse return error.FixtureMismatch,
    );
}

test "releasing an owned block hands the memory back once" {
    nativeReady();
    // One owner, one release, and a second release that must be the same no-op
    // rather than a second free. What is checked is the transition: after the
    // first `deinit` the handle is null, and the second call leaves it null
    // without the program faulting. A test that only asked whether the field
    // was non-null before the call would prove that an allocation happened, not
    // that releasing it twice is safe.
    var regex = try mustCompile(widenLiteral("(a)"), .{});
    var match_data = try pcre2.MatchData.create(&regex);
    var context = try pcre2.MatchContext.init();

    match_data.deinit();
    context.deinit();
    regex.deinit();

    try std.testing.expectEqual(@as(?*pcre2.Surface.Types.MatchData, null), match_data.raw);
    try std.testing.expectEqual(@as(?*pcre2.Surface.Types.MatchContext, null), context.raw);
    try std.testing.expectEqual(@as(?*pcre2.Surface.Types.Code, null), regex.code);

    match_data.deinit();
    context.deinit();
    regex.deinit();

    try std.testing.expectEqual(@as(?*pcre2.Surface.Types.Code, null), regex.code);
}

test "a name the pattern did not declare, and a name too long to declare, are both null" {
    nativeReady();
    var regex = try mustCompile(widenLiteral("(?<abc>x)(?'xyz'y)"), .{});
    defer regex.deinit();

    // Upstream keeps the table in name order (`pcre2_compile_cgroup.c:106-108`),
    // and "abc" sorts before "xyz" here, so entry 1 is the last one and index 2
    // is past the end. The pattern also happens to write its two names in that
    // order, which is why this pattern cannot tell name order apart from the
    // order they were written in; the test below is the one that does.
    try std.testing.expectEqual(@as(u32, 2), regex.nameCount());
    const last = regex.nameAt(1) orelse return error.FixtureMismatch;
    try std.testing.expectEqual(@as(u32, 2), last.number);
    // Names come back in this width's code units
    // (`src/pcre2_compile_cgroup.c:168`), so they are compared in units
    // rather than as bytes.
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("xyz"),
        last.name,
    );
    if (regex.nameAt(2) != null) return error.FixtureMismatch;

    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("abc"),
        regex.nameForNumber(1) orelse return error.FixtureMismatch,
    );
    if (regex.numberForName(widenLiteral("nope")) != null) return error.FixtureMismatch;

    // pcre2_compile.c:2671 refuses a group name longer than MAX_NAME_SIZE, so
    // no pattern this fork accepted can have a name of this length and the
    // lookup must not go looking for one.
    var too_long: [pcre2.max_name_length + 1]Unit = @splat('a');
    if (regex.numberForName(&too_long) != null) return error.FixtureMismatch;
}

test "the name table is walked in name order, and an entry ends at its own NUL" {
    nativeReady();
    // Four names written in an order that is neither ascending by group
    // number nor sorted by name, two of them sharing a prefix and two of them
    // far shorter than the longest. Everything a walker of this table can get
    // wrong is reachable from this one pattern: the order of the entries, the
    // group number decoded out of each one, and where a name stops and the
    // next entry begins.
    //
    // The order is PCRE2's and not this file's. Names are inserted where they
    // belong alphabetically (`pcre2_compile_cgroup.c:106-108`, `:140-161`), a
    // name that is a prefix of another sorts before it (`:142-144`), and the
    // longest name in the pattern sizes every entry
    // (`pcre2_compile.c:5713-5716`). Group numbers are handed out in the order
    // the groups appear (`pcre2_compile.c:5701-5702`), so the table reads
    // 4, 3, 2, 1 rather than 1, 2, 3, 4.
    var regex = try mustCompile(widenLiteral("(?<zebra>1)(?<m>2)(?<alpha>3)(?<al>4)"), .{});
    defer regex.deinit();

    // The names below are runtime values, so they are widened through a
    // buffer; `widenLiteral` is the comptime form for the literals this file
    // writes inline. The expected names are kept as the bytes they are
    // written as here and converted on both sides of each comparison, because
    // the table this walks holds code units of the compiled width
    // (`src/pcre2_compile_cgroup.c:168`) and a `[]const u8` is not a
    // `[]const u16`.
    var name_workspace: [pcre2.max_name_length]Unit = undefined;
    var rendered: [pcre2.max_name_length]u8 = undefined;

    try std.testing.expectEqual(@as(u32, 4), regex.nameCount());

    const expected = [_]struct { number: u32, name: []const u8 }{
        .{ .number = 4, .name = "al" },
        .{ .number = 3, .name = "alpha" },
        .{ .number = 2, .name = "m" },
        .{ .number = 1, .name = "zebra" },
    };
    for (expected, 0..) |want, i| {
        const entry = regex.nameAt(@intCast(i)) orelse return error.FixtureMismatch;
        try std.testing.expectEqual(want.number, entry.number);
        // Three of these four names are shorter than the longest one, so their
        // entries carry zero padding behind the NUL. Comparing the whole slice
        // is what catches a name that ran to the end of its entry instead of
        // stopping at that NUL.
        try std.testing.expectEqualStrings(
            want.name,
            try render(&rendered, entry.name, false),
        );
        const wanted = try widen(want.name, &name_workspace);
        try std.testing.expectEqualSlices(
            Unit,
            wanted,
            regex.nameForNumber(want.number) orelse return error.FixtureMismatch,
        );
        try std.testing.expectEqual(
            want.number,
            regex.numberForName(wanted) orelse return error.FixtureMismatch,
        );
    }
    if (regex.nameAt(expected.len) != null) return error.FixtureMismatch;
}

test "the version answer is the caller's own buffer, and a short one is refused" {
    nativeReady();
    // A guard unit, not a version: nothing below can be satisfied by a value
    // this file put in the buffer itself. 64 units is past the 24 code units
    // every release so far has needed (`doc/pcre2.txt:1468-1469`); what the
    // library actually asks for is what the rest of this test works from.
    var buffer: [64]Unit = @splat(0xaa);
    const reported = try pcre2.version(&buffer);

    // Where the units live is the property under test. A facade that filled its
    // own frame and returned a slice of that frame would hand back the right
    // string and leave this comparison pointing into a frame that has already
    // been reused for something else.
    try std.testing.expectEqual(@intFromPtr(&buffer[0]), @intFromPtr(reported.ptr));
    // The slice ends on a terminator the copy actually wrote, so the sentinel
    // in its type is a fact about the buffer rather than a claim about a unit
    // nobody checked.
    try std.testing.expectEqual(@as(Unit, 0), buffer[reported.len]);
    // Nothing was written past it either: a unit beyond the terminator is still
    // the guard, which a copy that ran on would have replaced.
    if (reported.len + 1 < buffer.len) {
        try std.testing.expectEqual(@as(Unit, 0xaa), buffer[reported.len + 1]);
    }

    // One unit less than the library asked for, which is short by exactly the
    // terminator. A capacity check that forgot to count it would let this call
    // through and hand back a string with no room for its own zero.
    var short_buffer: [64]Unit = @splat(0xaa);
    const too_short = short_buffer[0..reported.len];
    try std.testing.expectError(error.VersionBufferTooSmall, pcre2.version(too_short));
    // And the refusal is before the call that writes, not after it: not one
    // unit of the caller's storage changed. A short buffer written and then
    // reported would leave the version string in the first units here.
    for (too_short) |unit| try std.testing.expectEqual(@as(Unit, 0xaa), unit);
}

// ---------------------------------------------------------------------------
// Ownership
// ---------------------------------------------------------------------------

test "a capture is a window on the caller's subject, not a copy of it" {
    nativeReady();
    var subject: [3]Unit = .{ 'x', 'b', 'x' };
    var regex = try mustCompile(widenLiteral("x(b)x"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match(&subject, 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    const captured = (try match_data.group(1)) orelse return error.FixtureMismatch;
    try std.testing.expectEqualSlices(Unit, widenLiteral("b"), captured);
    const range = (try match_data.groupRange(1)) orelse return error.FixtureMismatch;
    try std.testing.expectEqual(@as(usize, 1), range.start);
    try std.testing.expectEqual(@as(usize, 2), range.end);

    // Writing through the caller's own buffer is visible through the capture.
    // A binding that had copied the substring out would still be holding "b"
    // here, so this fails on a copy and passes only on a borrow.
    subject[1] = 'B';
    try std.testing.expectEqualSlices(Unit, widenLiteral("B"), captured);
    try std.testing.expectEqual(@as(usize, 3), match_data.subject.len);
}

test "an attempt that did not match leaves nothing readable, whatever the last one found" {
    nativeReady();
    var regex = try mustCompile(widenLiteral("(\\d+)-(\\w+)"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match(widenLiteral("123-abc"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("abc"),
        (try match_data.group(2)) orelse return error.FixtureMismatch,
    );
    const found = (try match_data.groupRange(2)) orelse return error.FixtureMismatch;
    try std.testing.expectEqual(@as(usize, 4), found.start);
    try std.testing.expectEqual(@as(usize, 7), found.end);

    // The same block, reused over a one unit subject the pattern cannot match.
    // PCRE2 writes the offset vector only on the path that matched
    // (`src/pcre2_match.c:1045-1053`); the non-match path returns through
    // `src/pcre2_match.c:8214-8220` having set only the subject, its length,
    // the start offset and the return code. Group 2 therefore still holds
    // 4..7 from the subject above, and those offsets are past the end of this
    // one: reading them is an out-of-bounds read.
    switch (try regex.match(widenLiteral("z"), 0, .{}, &match_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expect((try match_data.groupRange(2)) == null);
    try std.testing.expect((try match_data.group(2)) == null);
    // The whole match is no more readable than a capture, and the group-number
    // bound still comes first: it is a statement about the index, not about
    // the match.
    try std.testing.expect((try match_data.groupRange(0)) == null);
    try std.testing.expectError(error.NoSuchGroup, match_data.groupRange(3));

    // A further match re-arms the block, and the captures are then that
    // subject's own: "q" is unit 2 of "7-q", not units 4..7 of anything.
    switch (try regex.match(widenLiteral("7-q"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("q"),
        (try match_data.group(2)) orelse return error.FixtureMismatch,
    );
}

test "MARK returns the compiled label, not the subject or the K-reset capture" {
    nativeReady();
    var regex = try mustCompile(widenLiteral("(*MARK:selected)a\\Kb"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match(widenLiteral("ab"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(Unit, widenLiteral("selected"), (try match_data.mark()) orelse return error.FixtureMismatch);
    try std.testing.expectEqualSlices(Unit, widenLiteral("b"), (try match_data.group(0)) orelse return error.FixtureMismatch);
}

test "a group the pattern skipped reports no range, and one that took part reports its own" {
    nativeReady();
    var regex = try mustCompile(widenLiteral("(a)|(b)"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match(widenLiteral("b"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    // PCRE2 leaves PCRE2_UNSET in the offset vector for the alternative the
    // pattern did not take (`src/pcre2_match.c:1036-1037` and `:1053`), and a
    // group that did not take part is reported as having no range rather than
    // as a zero-length one. "b" is the one unit at 0..1.
    try std.testing.expect((try match_data.groupRange(1)) == null);
    try std.testing.expect((try match_data.group(1)) == null);
    const second = (try match_data.groupRange(2)) orelse return error.FixtureMismatch;
    try std.testing.expectEqual(@as(usize, 0), second.start);
    try std.testing.expectEqual(@as(usize, 1), second.end);
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("b"),
        (try match_data.group(2)) orelse return error.FixtureMismatch,
    );
}

test "a capture is copied out of the block, and the caller says where the copy lands" {
    nativeReady();
    // Two alternatives, so one of them does not take part and can be asked
    // about separately from the one that did.
    var regex = try mustCompile(widenLiteral("(\\d+)|(x)"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match(widenLiteral("12345"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }

    // `pcre2_substring_get_bynumber_N` is the route that allocates: the copy
    // is a block of its own, made with the match block's allocator
    // (`src/pcre2_substring.c:213-216`) and released by the caller through
    // `pcre2_substring_free_N` (`:237-245`), so it is the caller who owns it
    // and not the block. What it copies is the group, resolved against the
    // block's own subject -- which is the caller's own subject here, because
    // PCRE2 borrows that rather than keeping a copy of it
    // (`src/pcre2_match.c:8179`).
    var owned = try match_data.get(1);
    defer owned.deinit();
    try std.testing.expectEqualSlices(Unit, widenLiteral("12345"), owned.slice());

    // `pcre2_substring_copy_bynumber_N` is the other one
    // (`src/pcre2_substring.c:116-130`): it writes into storage the caller
    // already has and allocates nothing, so there is nothing to release
    // afterwards and nothing that can be forgotten. It appends the terminator
    // (`:127`), so a buffer for five units of text is six.
    var buffer: [6]Unit = @splat(0xaa);
    const written = try match_data.copy(1, &buffer);
    try std.testing.expectEqual(@as(usize, 5), written);
    try std.testing.expectEqualSlices(Unit, widenLiteral("12345"), buffer[0..written]);
    try std.testing.expectEqual(@as(Unit, 0), buffer[written]);

    // One unit too few is the check upstream makes first: `size + 1 > *sizeptr`
    // answers -48, `PCRE2_ERROR_NOMEMORY` (`src/pcre2_substring.c:124`), so the
    // refusal arrives before the copy rather than after it, and a truncated
    // capture is not something a caller has to notice on its own.
    var short: [5]Unit = @splat(0xaa);
    try std.testing.expectError(error.SubstringBufferTooSmall, match_data.copy(1, &short));
    for (short) |unit| try std.testing.expectEqual(@as(Unit, 0xaa), unit);

    // The alternative that did not take part is not a capture, and saying so
    // is a different answer from handing back an empty one: PCRE2 leaves
    // `PCRE2_UNSET` in both ends of it and reports that as an error
    // (`src/pcre2_substring.c:331-332`).
    try std.testing.expectError(error.SubstringUnavailable, match_data.get(2));
    try std.testing.expectError(error.SubstringUnavailable, match_data.copy(2, &short));

    // `copy_matched_subject` changes where the same call reads from and not
    // whether it answers: the block holds a copy of its own, and group 1 comes
    // back with the same text out of it (`src/pcre2_match.c:8165-8178`). The
    // copy is still the caller's to release.
    var other = try pcre2.MatchData.create(&regex);
    defer other.deinit();
    switch (try regex.match(
        widenLiteral("999"),
        0,
        .{ .copy_matched_subject = true },
        &other,
        null,
    )) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    var copied = try other.get(1);
    defer copied.deinit();
    try std.testing.expectEqualSlices(Unit, widenLiteral("999"), copied.slice());
}

test "every capture of an attempt comes back as one list the caller owns" {
    nativeReady();
    var regex = try mustCompile(widenLiteral("(a)(b)(c)"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match(widenLiteral("abc"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    // Three capturing groups plus group 0, which is what `captureCount` counts.
    const count = match_data.captureCount();
    try std.testing.expectEqual(@as(u32, 4), count);

    // One call, one block: `pcre2_substring_list_get_N` writes one
    // `PCRE2_UCHAR **` and one `PCRE2_SIZE *` of its own
    // (`src/pcre2_substring.c:404-437`) rather than a pair per group into two
    // arrays the caller had to provide and size, and the caller releases the
    // whole block in one call (`:451-459`).
    var list = try match_data.list();
    defer list.deinit();

    // How many the list carries is what the attempt reported, not how many the
    // block could have held, so it is the list's own count that bounds `get`.
    // All three groups took part here, which is what makes the two the same
    // number rather than the list being short.
    try std.testing.expectEqual(count, list.count);

    const expected = [_][]const u8{ "abc", "a", "b", "c" };
    // `want` comes out of a run-time loop, so it is widened through a buffer
    // the way the name table above is; `widenLiteral` is the comptime form for
    // the literals this file writes inline. Three units is the longest entry
    // here, so a fourth would be refused rather than quietly truncated.
    var text_workspace: [3]Unit = undefined;
    for (expected, 0..) |want, i| {
        const got = list.get(@intCast(i)) orelse return error.FixtureMismatch;
        try std.testing.expectEqualSlices(Unit, try widen(want, &text_workspace), got);
    }
    if (list.get(count) != null) return error.FixtureMismatch;
}

// ---------------------------------------------------------------------------
// Contexts, the allocator, and the entry points that own nothing
// ---------------------------------------------------------------------------

/// One block this pair handed out, remembered so the free side can hand back
/// that block rather than a slice that only names its address.
const LiveBlock = struct {
    address: [*]u8,
    size: usize,
};

const Counter = struct {
    allocations: usize = 0,
    frees: usize = 0,
    bytes: usize = 0,
    /// Every block that has been handed out and not yet handed back.
    ///
    /// The free side of a C allocator pair is given the pointer and nothing
    /// else (`runtime/library.zig`'s `GeneralContext.create` says the same
    /// thing), so the size that goes with an address is the only way to
    /// release the block itself. A block this pair was never asked for is
    /// **counted**, not dropped, so a free arriving for an address that is
    /// not in here cannot make a leak check pass by being ignored; the same
    /// goes for a block handed out with the table full.
    live: [16]?LiveBlock = @splat(null),
    /// Frees of blocks this pair did not hand out. Must be zero at the end.
    unknown_frees: usize = 0,
    /// Allocations this pair could not record. Must be zero at the end.
    unrecorded: usize = 0,
};

fn countingAllocate(size: usize, data: ?*anyopaque) callconv(.c) ?*anyopaque {
    const counter: *Counter = @ptrCast(@alignCast(data.?));
    // A page allocator is used because it is the one allocator a free can be
    // handed a pointer for: `std.heap.page_allocator.free` takes a slice and
    // ignores the length, so the length this function is given is free to be
    // the block's own.
    const memory = std.heap.page_allocator.alloc(u8, size) catch return null;
    counter.allocations += 1;
    counter.bytes += size;
    if (counter.allocations <= counter.live.len) {
        counter.live[counter.allocations - 1] = .{ .address = memory.ptr, .size = size };
    } else {
        // Recorded as a failure rather than dropped: the free for this block
        // would find nothing to match and be counted as unknown, which is
        // what should happen if the table is ever too small.
        counter.unrecorded += 1;
    }
    return @ptrCast(memory.ptr);
}

fn countingDeallocate(memory: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
    const counter: *Counter = @ptrCast(@alignCast(data.?));
    const address: [*]u8 = @ptrCast(memory orelse return);
    // A block this pair was not asked for is not one this pair releases, so a
    // pointer it cannot match against what it handed out is not freed at a
    // length this pair made up -- but it is counted, because dropping it
    // silently is what would let an ownership bug pass as a clean run.
    for (&counter.live) |*slot| {
        const block = slot.* orelse continue;
        if (block.address != address) continue;
        slot.* = null;
        counter.frees += 1;
        std.heap.page_allocator.free(address[0..block.size]);
        return;
    }
    counter.unknown_frees += 1;
}

/// Whether this pair handed out a block that begins at `block`.
///
/// Read out of `live` before the frees rather than after, because the count
/// lines that follow cannot tell a block this pair made from one it did not:
/// the contexts and the character tables raise `allocations` whatever a caller
/// does, so a conservation check on its own is satisfied by a decoder that used
/// upstream's default allocator throughout. Asking for each block's address is
/// the claim that is actually about ownership.
fn isLive(counter: *const Counter, block: *pcre2.Surface.Types.Code) bool {
    const address: [*]u8 = @ptrCast(block);
    for (counter.live) |slot| {
        const live = slot orelse continue;
        if (live.address == address) return true;
    }
    return false;
}

test "a caller's own allocator is used for the blocks it was given to, and every one is handed back" {
    nativeReady();
    var counter: Counter = .{};
    var general = try pcre2.GeneralContext.create(
        countingAllocate,
        countingDeallocate,
        &counter,
    );
    defer general.deinit();

    var compile_context = try pcre2.CompileContext.create(&general);
    defer compile_context.deinit();

    var compiled = switch (try pcre2.Regex.compileWith(widenLiteral("(a)(b)"), .{}, &compile_context)) {
        .compiled => |regex| regex,
        .rejected => return error.FixtureMismatch,
    };
    var match_data = try pcre2.MatchData.createWithOvector(
        compiled.captureCount() + 1,
        &general,
    );
    defer match_data.deinit();
    switch (try compiled.match(widenLiteral("ab"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }

    // Before anything is released, the caller's allocator is the one that has
    // been asked for memory and nothing has been handed back. **How many**
    // blocks that is not asserted: a context-driven compile is free to make
    // one block or several (`src/pcre2_context.c:117`, `:150` are two of
    // them), and pinning the number would pin PCRE2's internal allocation
    // strategy rather than anything a caller can rely on. What is asserted is
    // that the memory came from this pair at all, and that it was remembered
    // well enough to be released again.
    try std.testing.expect(counter.allocations > 0);
    try std.testing.expect(counter.bytes > 0);
    try std.testing.expectEqual(@as(usize, 0), counter.unrecorded);
    try std.testing.expectEqual(@as(usize, 0), counter.frees);

    // The block matched for real, so the pattern is exercised rather than only
    // allocated: a capture read out of the block this allocator produced is
    // the answer the pattern means.
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("b"),
        (try match_data.group(2)) orelse return error.FixtureMismatch,
    );

    // Each block carries its own allocator record, so releasing these goes
    // through the caller's pair and not through upstream's `free`. The
    // contexts are released too, because they were allocated through the same
    // pair and a run that leaves them outstanding would report a leak the
    // caller cannot see.
    compiled.deinit();
    match_data.deinit();
    compile_context.deinit();
    general.deinit();

    // Every block handed out came back, none came back that was never handed
    // out, and none was handed out that could not be tracked: a pair that
    // dropped what it could not match would satisfy "frees == allocations"
    // without ever having released anything, which is why the two counters
    // above exist.
    try std.testing.expect(counter.allocations > 0);
    try std.testing.expectEqual(counter.allocations, counter.frees);
    try std.testing.expectEqual(@as(usize, 0), counter.unknown_frees);
    try std.testing.expectEqual(@as(usize, 0), counter.unrecorded);
}

test "the newline convention the compile context sets changes what `$` accepts" {
    nativeReady();
    // `PCRE2_NEWLINE_LF` and `PCRE2_NEWLINE_CRLF` are two different answers to
    // the same question (`src/pcre2.h.generic:213-218`), and the difference is
    // observable: under CRLF a bare LF is not a line terminator, so `a$` does
    // not match "a\n". That is the setting doing the work, not a constant
    // being read back.
    //
    // **Each convention gets its own compiled block**, because the convention
    // is copied into the block while it is compiled (`src/pcre2_compile.c:10976`,
    // from the context field written at `:10708`) and `pcre2_set_newline_N`
    // only reaches the context (`src/pcre2_context.c:362-379`). Changing the
    // context afterwards cannot reach a block that already exists, so a test
    // that changed it and re-matched the same block would be checking nothing.
    var context = try pcre2.CompileContext.create(null);
    defer context.deinit();

    try context.setNewline(pcre2.newline.lf);
    var under_lf = switch (try pcre2.Regex.compileWith(widenLiteral("a$"), .{}, &context)) {
        .compiled => |regex| regex,
        .rejected => return error.FixtureMismatch,
    };
    defer under_lf.deinit();
    var lf_data = try pcre2.MatchData.create(&under_lf);
    defer lf_data.deinit();
    switch (try under_lf.match(widenLiteral("a\n"), 0, .{}, &lf_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }

    try context.setNewline(pcre2.newline.crlf);
    var under_crlf = switch (try pcre2.Regex.compileWith(widenLiteral("a$"), .{}, &context)) {
        .compiled => |regex| regex,
        .rejected => return error.FixtureMismatch,
    };
    defer under_crlf.deinit();
    var crlf_data = try pcre2.MatchData.create(&under_crlf);
    defer crlf_data.deinit();

    // The same subject, the same pattern, one answer each: LF is a line
    // terminator under the first convention and is not under the second.
    switch (try under_crlf.match(widenLiteral("a\n"), 0, .{}, &crlf_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
    // Which is not the block refusing to match: under CRLF a real CRLF is what
    // `$` accepts, so the same pattern and the same block do match there.
    switch (try under_crlf.match(widenLiteral("a\r\n"), 0, .{}, &crlf_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }

    // A value the switch in `src/pcre2_context.c:362-376` does not have is
    // refused rather than stored, and the previous setting survives the refusal
    // because the setter never reaches the field. Compiled once more, so that
    // is a statement about the setting the context still holds and not about a
    // block compiled before the refusal.
    try std.testing.expectError(error.SettingRefused, context.setNewline(99));
    var after_refusal = switch (try pcre2.Regex.compileWith(widenLiteral("a$"), .{}, &context)) {
        .compiled => |regex| regex,
        .rejected => return error.FixtureMismatch,
    };
    defer after_refusal.deinit();
    var refusal_data = try pcre2.MatchData.create(&after_refusal);
    defer refusal_data.deinit();
    switch (try after_refusal.match(widenLiteral("a\n"), 0, .{}, &refusal_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
}

test "a glob is converted into a pattern the same compiler then accepts" {
    nativeReady();
    var context = try pcre2.ConvertContext.create(null);
    defer context.deinit();
    try context.setGlobEscape('\\');
    try context.setGlobSeparator('/');

    var converted = switch (try context.convert(widenLiteral("*.txt"), pcre2.convert_option.glob, false)) {
        .converted => |pattern| pattern,
        .rejected => |rejection| {
            std.debug.print("the glob was refused: error {d} at offset {d}\n", .{
                rejection.code,
                rejection.offset,
            });
            return error.FixtureMismatch;
        },
    };
    defer converted.deinit();
    // The conversion allocated, so it is a block of its own rather than a
    // window on the caller's buffer. The block is NUL-terminated, but the
    // reported length is the text and not the terminator: the glob converter
    // writes the NUL and then answers `out.output_size - 1`
    // (`src/pcre2_convert.c:1080`, `:1092`), and `pcre2_compile` takes an
    // explicit length, so nothing downstream needs the terminator inside the
    // slice. What is checked is that the glob was really expanded into
    // something longer than itself, not where its last unit happens to sit.
    try std.testing.expect(converted.slice().len > "*.txt".len);

    var compiled = switch (try pcre2.Regex.compile(converted.slice(), .{})) {
        .compiled => |regex| regex,
        .rejected => return error.FixtureMismatch,
    };
    defer compiled.deinit();
    var match_data = try pcre2.MatchData.create(&compiled);
    defer match_data.deinit();

    switch (try compiled.match(widenLiteral("notes.txt"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    switch (try compiled.match(widenLiteral("notes.txt.bak"), 0, .{}, &match_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }

    // The separator is what makes this a glob and not a wildcard: `*` is
    // converted to a class that cannot match `/`, so the pattern is bounded by
    // path components on both sides. Both of these are the boundaries a caller
    // relies on, and neither is visible from the two matches above.
    switch (try compiled.match(widenLiteral("src/notes.txt"), 0, .{}, &match_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
    // Only the separator is excluded, which is worth saying out loud: a
    // backslash is an ordinary character in the subject and this pattern still
    // matches across one.
    switch (try compiled.match(widenLiteral("src\\notes.txt"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    // And a name that ends in the glob's own literal still matches, which says
    // the `.txt` part was converted as an escaped literal rather than dropped.
    switch (try compiled.match(widenLiteral("a.txt"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
}

const Callout = struct {
    calls: u32 = 0,
    first_number: u32 = 0,
    saw_this_subject: bool = false,
    subject: [*c]const Unit = undefined,
};

fn noteCallout(block: [*c]pcre2.Surface.Types.CalloutBlock, data: ?*anyopaque) callconv(.c) c_int {
    const state: *Callout = @ptrCast(@alignCast(data.?));
    state.calls += 1;
    if (state.calls == 1) {
        state.first_number = block.*.callout_number;
        // The block's subject is PCRE2's own pointer to the caller's buffer,
        // which is what makes the typed code-unit pointer visible here.
        state.saw_this_subject = (block.*.subject == state.subject);
    }
    // Zero continues the match at this position. The sign is what carries the
    // meaning: a positive value abandons the attempt at this position as a
    // non-match and a negative one abandons the whole attempt with that
    // number (`src/pcre2_match.c:5989-5994`, `:6028-6030`), so "non-zero"
    // is not a way of saying "keep going".
    return 0;
}

test "a callout reaches the matcher with this pattern's own callout block" {
    nativeReady();
    var state: Callout = .{};
    var context = try pcre2.MatchContext.init();
    defer context.deinit();
    try context.setCallout(noteCallout, &state);

    var compiled = try mustCompile(widenLiteral("(?C1)ab"), .{});
    defer compiled.deinit();
    var match_data = try pcre2.MatchData.create(&compiled);
    defer match_data.deinit();

    const subject = widenLiteral("ab");
    state.subject = subject.ptr;
    switch (try compiled.match(subject, 0, .{}, &match_data, &context)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    // The callback ran, it ran for callout 1, and the block it was handed
    // pointed at this caller's own subject rather than at a copy.
    try std.testing.expect(state.calls >= 1);
    try std.testing.expectEqual(@as(u32, 1), state.first_number);
    try std.testing.expect(state.saw_this_subject);
}

test "JIT is refused in a build with no SLJIT, and a JIT stack is refused with its own name" {
    nativeReady();
    var compiled = try mustCompile(widenLiteral("a+"), .{});
    defer compiled.deinit();

    // `deps/sljit` is an empty submodule, so `SUPPORT_JIT` is 0 and
    // `pcre2_jit_compile_8` is upstream's `#ifndef SUPPORT_JIT` fallback
    // (`src/pcre2_jit_compile.c:14303-14432`). The refusal is a value with
    // upstream's number in it, not an error, because a caller that asks may be
    // talking to a provider that has JIT -- so which answer this build gets is
    // recorded and the rest of the test is written against it rather than
    // against the configuration.
    var jit = false;
    switch (try compiled.jitCompile(pcre2.jit_option.complete)) {
        .compiled => jit = true,
        .refused => |refusal| {
            try std.testing.expectEqual(@as(i32, pcre2.c.PCRE2_ERROR_JIT_BADOPTION), refusal.code);
            try std.testing.expect(refusal.text.len > 0);
        },
    }

    // The stack is a different entry point with a different fallback: it answers
    // NULL rather than a code (`src/pcre2_jit_misc_inc.h:125-134`), and the two
    // arrive the same way at `pcre2_general_context_create`, so the facade names
    // this one for what it is.
    try std.testing.expectError(error.JitUnsupported, pcre2.JitStack.create(1024, 8192));

    var match_data = try pcre2.MatchData.create(&compiled);
    defer match_data.deinit();
    var context = try pcre2.MatchContext.init();
    defer context.deinit();

    // The interpreted matcher works for the same pattern and subject either
    // way, so it is what establishes that there is a real answer to compare
    // the JIT path against.
    const subject = widenLiteral("xxaaay");
    switch (try compiled.match(subject, 0, .{}, &match_data, &context)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("aaa"),
        (try match_data.group(0)) orelse return error.FixtureMismatch,
    );

    switch (try compiled.jitMatch(subject, 0, .{}, &match_data, &context)) {
        // With JIT code the two entry points are the same matcher.
        .matched => {
            try std.testing.expect(jit);
            try std.testing.expectEqualSlices(
                Unit,
                widenLiteral("aaa"),
                (try match_data.group(0)) orelse return error.FixtureMismatch,
            );
        },
        // Without it there is **no fallback**: `pcre2_jit_match_N` is upstream's
        // `#ifndef SUPPORT_JIT` body, which ignores every argument and answers
        // `PCRE2_ERROR_JIT_BADOPTION` (`src/pcre2_jit_match_inc.h:95-103`). It
        // does not call `pcre2_match_N`, so this is a refusal carrying upstream's
        // number rather than a quiet restatement of the interpreted answer.
        .failed => |failure| {
            try std.testing.expect(!jit);
            try std.testing.expectEqual(@as(i32, pcre2.c.PCRE2_ERROR_JIT_BADOPTION), failure.code);
            try std.testing.expect(failure.text.len > 0);
            // An attempt that failed leaves the block with nothing readable,
            // even though the interpreted attempt on the same block just
            // matched: the JIT attempt is a different attempt.
            try std.testing.expect(!match_data.matched);
            try std.testing.expect((try match_data.groupRange(0)) == null);
        },
        else => return error.FixtureMismatch,
    }
}

test "substitution answers the length it needs, then writes it" {
    nativeReady();
    var compiled = try mustCompile(widenLiteral("a"), .{});
    defer compiled.deinit();
    var match_data = try pcre2.MatchData.create(&compiled);
    defer match_data.deinit();

    const subject = widenLiteral("aaa");
    const replacement = widenLiteral("b");

    // Nothing to write into, and the overflow option set: the call answers the
    // length the result needs, including its terminating NUL, and writes
    // nothing (`src/pcre2_substitute.c:1746-1755`). Three replacements of one
    // unit each plus the NUL is four.
    switch (try compiled.substitute(
        subject,
        0,
        .{ .global = true, .overflow_length = true },
        replacement,
        &match_data,
        null,
        &.{},
    )) {
        .overflow => |needed| try std.testing.expectEqual(@as(usize, 4), needed),
        else => return error.FixtureMismatch,
    }

    // A buffer exactly that size, and no overflow option: the result lands in
    // the caller's own storage and the return is the number of replacements
    // (`src/pcre2_substitute.c:1757-1764`).
    var buffer: [4]Unit = undefined;
    switch (try compiled.substitute(
        subject,
        0,
        .{ .global = true },
        replacement,
        &match_data,
        null,
        &buffer,
    )) {
        .written => |written| {
            try std.testing.expectEqualSlices(Unit, widenLiteral("bbb"), written.text);
            try std.testing.expectEqual(@as(usize, 3), written.substitutions);
            try std.testing.expectEqual(@as(Unit, 0), buffer[3]);
        },
        else => return error.FixtureMismatch,
    }

    // One unit too few and nothing is written, which is a different answer from
    // the overflow one and says so.
    var short: [3]Unit = undefined;
    try std.testing.expectError(
        error.SubstituteBufferTooSmall,
        compiled.substitute(
            subject,
            0,
            .{ .global = true },
            replacement,
            &match_data,
            null,
            &short,
        ),
    );
}

// A block describes the last thing that ran on it, and `substitute` is that
// thing. Upstream matches into the caller's block
// (`src/pcre2_substitute.c:984`) and, on the way out, stores the number of
// replacements it made in `match_data->rc` (`:1762`, `:1768`) -- a field every
// native substring entry point reads as a pair count
// (`src/pcre2_substring.c:317`, `:390`). The vector itself holds the *last*
// internal match's pairs, so a description left over from an earlier match
// would hand the next caller offsets computed against a subject this block no
// longer remembers, and a pair count larger than the vector would make
// `pcre2_substring_list_get_N` walk past the end of it.
test "a substitution leaves the block describing nothing, whatever the match before it found" {
    nativeReady();
    var compiled = try mustCompile(widenLiteral("(a)"), .{});
    defer compiled.deinit();
    var match_data = try pcre2.MatchData.create(&compiled);
    defer match_data.deinit();

    // One code unit long, so an offset out of the substitute's subject is out
    // of this one too.
    switch (try compiled.match(widenLiteral("a"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("a"),
        (try match_data.group(1)) orelse return error.FixtureMismatch,
    );

    // Five matches replaced by two code units each. The result is longer than
    // the subject above, the last internal match ends at offset 5, and there
    // are more replacements than the block has pairs.
    var buffer: [16]Unit = undefined;
    switch (try compiled.substitute(
        widenLiteral("aaaaa"),
        0,
        .{ .global = true },
        widenLiteral("bb"),
        &match_data,
        null,
        &buffer,
    )) {
        .written => |written| {
            try std.testing.expectEqualSlices(Unit, widenLiteral("bbbbbbbbbb"), written.text);
            try std.testing.expectEqual(@as(usize, 5), written.substitutions);
            try std.testing.expectEqual(@as(Unit, 0), buffer[10]);
        },
        else => return error.FixtureMismatch,
    }

    // Every capture accessor now reports the one fact: there is no capture
    // here to read. The range comes first, because whether it is there
    // decides whether asking the rest is safe at all.
    if ((try match_data.groupRange(1)) != null) return error.FixtureMismatch;
    if ((try match_data.group(1)) != null) return error.FixtureMismatch;
    try std.testing.expectError(error.SubstringUnavailable, match_data.ovector());
    try std.testing.expectError(error.SubstringUnavailable, match_data.list());
    try std.testing.expectError(error.SubstringUnavailable, match_data.get(1));
    try std.testing.expectError(error.SubstringUnavailable, match_data.copy(1, &buffer));

    // And the block is not spent: it carries the next attempt like any other.
    switch (try compiled.match(widenLiteral("xa"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("a"),
        (try match_data.group(1)) orelse return error.FixtureMismatch,
    );
}

test "the DFA matcher finds the longest match and says when it could not fit them all" {
    nativeReady();
    // **How many** matches a DFA run reports is a fact about the compiled
    // pattern, not about the matcher: auto-possessification rewrites a
    // trailing `a+` as if it were `a++`, and then only one possible match
    // exists at all (`doc/pcre2.txt:4369-4374`). Both are checked here, on the
    // same subject, because that is what makes the count a real answer: the
    // greedy pattern has one candidate and the ungreedy one has three, and
    // "longest first" is an ordering *among the candidates that were found*.
    const subject = widenLiteral("aaab");
    var workspace: [32]c_int = undefined;
    // A named `var` rather than `&.{ .offsets = ... }`: taking the address of
    // a struct literal builds a constant temporary, and `dfa` wants a mutable
    // `*DfaWorkspace`. `too_small` below is spelled the same way for the same
    // reason.
    var found: pcre2.DfaWorkspace = .{ .offsets = &workspace };

    var greedy = try mustCompile(widenLiteral("a+"), .{});
    defer greedy.deinit();
    var greedy_data = try pcre2.MatchData.create(&greedy);
    defer greedy_data.deinit();
    switch (try greedy.dfa(subject, 0, .{}, &greedy_data, null, &found)) {
        .matched => |matched| {
            // One candidate, because that is all this compiled pattern has.
            // It is the whole run of 'a's: a possessive repeat takes everything
            // the repeat can take and gives nothing back, and the optimizer
            // applies it to a greedy repeat with nothing after it
            // (`src/pcre2_auto_possess.c:612-613`), so "the longest match" and
            // "the only match" are the same answer here rather than two
            // different claims.
            try std.testing.expectEqual(@as(usize, 1), matched.pairs);
            const offsets = try greedy_data.ovector();
            try std.testing.expectEqual(@as(usize, 0), offsets[0]);
            try std.testing.expectEqual(subject.len - 1, offsets[1]);
        },
        else => return error.FixtureMismatch,
    }

    // The ungreedy repeat is upstream's own recommendation for getting more
    // than one match out of this matcher (`doc/pcre2.txt:4373-4374`), and it
    // is what makes the ordering observable. The block is sized for the pairs
    // rather than taken from the pattern, because for this matcher the vector
    // has to hold every simultaneous match and not one pair per parenthesis
    // (`doc/pcre2_dfa_match.3:33-35`).
    var ungreedy = try mustCompile(widenLiteral("a+?"), .{});
    defer ungreedy.deinit();
    var roomy = try pcre2.MatchData.createWithOvector(8, null);
    defer roomy.deinit();
    switch (try ungreedy.dfa(subject, 0, .{}, &roomy, null, &found)) {
        .matched => |matched| {
            try std.testing.expectEqual(@as(usize, 3), matched.pairs);
            const offsets = try roomy.ovector();
            // The ordering is the documented one -- longest first, and every
            // shorter match an initial substring of the longer ones
            // (`doc/pcre2.txt:4365-4366`) -- so it is asserted as a property
            // over the pairs that were reported rather than as one hand-listed
            // triple. What each pair spans is then checked against the subject,
            // which is what makes it a match and not a bookkeeping offset.
            var previous: ?usize = null;
            var run: [8]Unit = @splat(@as(Unit, 'a'));
            for (0..matched.pairs) |i| {
                const start = offsets[2 * i];
                const end = offsets[2 * i + 1];
                try std.testing.expect(start <= end);
                try std.testing.expect(end <= subject.len);
                // Each pair is at most as long as the one before it, which is
                // the ordering, and each spans only 'a's, which is the match.
                if (previous) |was| try std.testing.expect(end - start <= was);
                previous = end - start;
                try std.testing.expectEqualSlices(Unit, run[0 .. end - start], subject[start..end]);
            }
            // The first pair is the longest, and for this subject the longest
            // possible match of this pattern is the whole run of 'a's: without
            // this an ordering property over three empty pairs would be
            // satisfied by nothing at all.
            try std.testing.expectEqual(subject.len - 1, offsets[1] - offsets[0]);
        },
        else => return error.FixtureMismatch,
    }

    // The same attempt against a block with room for one pair, which is what
    // `MatchData.create` gives for a pattern with no capturing groups. The
    // matcher fills the vector with the longest matches and answers zero
    // (`doc/pcre2.txt:4366-4368`), which is its own outcome rather than a
    // match with a short vector -- so the longest is still readable and the
    // two that did not fit are simply not there.
    var cramped = try pcre2.MatchData.create(&ungreedy);
    defer cramped.deinit();
    switch (try ungreedy.dfa(subject, 0, .{}, &cramped, null, &found)) {
        .truncated => {
            const offsets = try cramped.ovector();
            try std.testing.expectEqual(@as(usize, 0), offsets[0]);
            try std.testing.expectEqual(@as(usize, 3), offsets[1]);
        },
        else => return error.FixtureMismatch,
    }

    switch (try ungreedy.dfa(widenLiteral("zzz"), 0, .{}, &roomy, null, &found)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }

    // A workspace below the floor upstream accepts is not a workspace at all.
    // Twenty units is that floor (`src/pcre2_dfa_match.c:3437`), and the
    // refusal arrives before the matcher runs.
    var too_small_offsets: [1]c_int = undefined;
    var too_small: pcre2.DfaWorkspace = .{ .offsets = &too_small_offsets };
    try std.testing.expectError(
        error.DfaWorkspaceTooSmall,
        ungreedy.dfa(subject, 0, .{}, &roomy, null, &too_small),
    );
}

test "a compiled pattern survives a round trip through its serialized form" {
    nativeReady();
    var compiled = try mustCompile(widenLiteral("(?<word>[a-z]+)"), .{});
    defer compiled.deinit();

    var codes: [1]?*const pcre2.Surface.Types.Code = undefined;
    var stream = try compiled.serialize(&.{}, &codes);
    defer stream.deinit();
    try std.testing.expect(stream.len > 0);

    // The stream says how many blocks are in it, which is what `decode` needs,
    // and that number is a fact about the bytes rather than about this test.
    try std.testing.expectEqual(@as(u32, 1), try pcre2.Regex.serializedCodeCount(stream.slice()));

    var decoded: [1]?*pcre2.Surface.Types.Code = undefined;
    var round_tripped = try pcre2.Regex.decode(stream.slice(), 1, &decoded, null);
    defer round_tripped.deinit();

    // A decoded block is an ordinary one: it carries the same name table and
    // matches the same subject with the same capture. The name is compared in
    // this width's code units (`src/pcre2_compile_cgroup.c:168`), and a
    // missing entry is a mismatch reported rather than an unwrap that takes
    // the whole test binary down with it.
    try std.testing.expectEqual(compiled.captureCount(), round_tripped.captureCount());
    try std.testing.expectEqual(compiled.nameCount(), round_tripped.nameCount());
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("word"),
        (round_tripped.nameAt(0) orelse return error.FixtureMismatch).name,
    );

    var match_data = try pcre2.MatchData.create(&round_tripped);
    defer match_data.deinit();
    switch (try round_tripped.match(widenLiteral("42abc42"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("abc"),
        (try match_data.group(1)) orelse return error.FixtureMismatch,
    );
}

// The serialization entry points refuse several things that are not failures
// to allocate. `pcre2_serialize_encode_N` compares the character tables of the
// blocks it is given **by address** and answers `PCRE2_ERROR_MIXEDTABLES` when
// they differ (`src/pcre2_serialize.c:99-102`), and the two readers answer
// `PCRE2_ERROR_BADMAGIC` for bytes that are not a stream at all (`:179`,
// `:273`). The only allocation failure among them is
// `PCRE2_ERROR_NOMEMORY` (`:108`, `:192`, `:221`), so a caller that has to
// decide between trying again smaller and fixing its input cannot make that
// decision if every refusal arrives under one name that says the heap ran out.
test "a stream PCRE2 will not build or read is refused as a refusal, not as a failed allocation" {
    nativeReady();
    // Two blocks whose character tables are two different addresses holding
    // the same bytes: `pcre2_compile` stores whichever pointer the compile
    // context held (`src/pcre2_compile.c:10451`, `:10960`), and it is those
    // pointers that serialization compares.
    var general = try pcre2.GeneralContext.init();
    defer general.deinit();
    const tables = try general.tables();
    defer general.freeTables(tables);

    var context = try pcre2.CompileContext.create(null);
    defer context.deinit();
    try context.setCharacterTables(tables);

    var shared = try mustCompile(widenLiteral("a"), .{});
    defer shared.deinit();
    var own = switch (try pcre2.Regex.compileWith(widenLiteral("b"), .{}, &context)) {
        .compiled => |regex| regex,
        .rejected => return error.FixtureMismatch,
    };
    defer own.deinit();

    var mixed: [2]?*const pcre2.Surface.Types.Code = undefined;
    try std.testing.expectError(
        error.SerializationRefused,
        shared.serialize(&.{own.code.?}, &mixed),
    );

    // One block on its own has no second table to disagree with, so the same
    // call succeeds. That is what makes the refusal above about the pair.
    var single: [1]?*const pcre2.Surface.Types.Code = undefined;
    var stream = try shared.serialize(&.{}, &single);
    defer stream.deinit();

    // `magic` is the first field of the stream's header
    // (`src/pcre2_internal.h:2169-2174`, written at
    // `src/pcre2_serialize.c:114-115`), so one changed byte is enough to make
    // the whole stream something neither reader will accept. The rest of the
    // header, and every block in it, is upstream's own output and untouched.
    const bytes = stream.slice();
    const damaged = try std.testing.allocator.dupe(u8, bytes);
    defer std.testing.allocator.free(damaged);
    damaged[0] ^= 0xff;

    try std.testing.expectError(
        error.SerializationRefused,
        pcre2.Regex.serializedCodeCount(damaged),
    );
    var decoded: [1]?*pcre2.Surface.Types.Code = undefined;
    try std.testing.expectError(
        error.SerializationRefused,
        pcre2.Regex.decode(damaged, 1, &decoded, null),
    );
}

// `pcre2_next_match_N` answers TRUE(1) for "attempt again" and FALSE(0) when
// there is none, and never anything else (`src/pcre2_match_next.c:96-169`,
// `doc/pcre2.txt:3433-3439`), so `MatchData.next` answers a plain bool and a
// resumed loop terminates. `a*` over `a` is the shortest subject that reaches
// both answers: a non-empty match at 0, then the empty match at the end of the
// subject, which is the FALSE branch (`src/pcre2_match_next.c:148-152`).
test "resuming a match walks every match and then reports that there are no more" {
    nativeReady();
    var compiled = try mustCompile(widenLiteral("a*"), .{});
    defer compiled.deinit();

    var match_data = try pcre2.MatchData.create(&compiled);
    defer match_data.deinit();

    const subject = widenLiteral("a");
    var start_offset: usize = 0;
    var options: u32 = 0;
    var found: usize = 0;
    while (true) {
        switch (try compiled.match(subject, start_offset, .{}, &match_data, null)) {
            .matched => {},
            .no_match => break,
            else => return error.FixtureMismatch,
        }
        found += 1;
        if (found > 2) return error.FixtureMismatch;
        const span = (try match_data.groupRange(0)) orelse return error.FixtureMismatch;
        if (span.start != found - 1 or span.end != 1) return error.FixtureMismatch;
        // The first attempt matched the whole subject and the second matched
        // the empty string at its end. That second one is the end-of-subject
        // FALSE, so this is not decoration: it is what the loop turns on.
        try std.testing.expectEqualSlices(
            Unit,
            if (found == 1) widenLiteral("a") else widenLiteral(""),
            (try match_data.group(0)) orelse return error.FixtureMismatch,
        );
        if (!match_data.next(&start_offset, &options)) break;
    }
    try std.testing.expectEqual(@as(usize, 2), found);
    // The FALSE return writes neither out-parameter, so this is still what the
    // last TRUE asked for: zero (`src/pcre2_match_next.c:166-167`).
    try std.testing.expectEqual(@as(u32, 0), options);
}

// `pcre2_serialize_decode_N` writes one `pcre2_code *` per block it decodes and
// cannot see how long the caller's array is (`src/pcre2_serialize.c:183-184`,
// `:204`, `:243`), so a destination shorter than `count` is refused instead of
// overrun. Three blocks in the stream, one slot in the destination.
test "decoding refuses a destination shorter than the blocks asked for" {
    nativeReady();
    // The counting pair is the point of this general context, not decoration.
    // A decoded block is allocated through the `general` handed to `decode`
    // (`src/pcre2_serialize.c:215-218`), and `pcre2_code_free_N` releases it
    // through that block's own memctl (`src/pcre2_compile.c:1227`), so this
    // pair is what makes every decoded block observable on the free side.
    var counter: Counter = .{};
    var general = try pcre2.GeneralContext.create(
        countingAllocate,
        countingDeallocate,
        &counter,
    );
    const tables = try general.tables();

    var context = try pcre2.CompileContext.create(&general);
    try context.setCharacterTables(tables);

    var shared = try mustCompile(widenLiteral("a"), .{});
    // The same block three times, which the encoder accepts: it compares the
    // character tables of the blocks it is given by address, and one block
    // cannot disagree with itself (`src/pcre2_serialize.c:99-102`).
    var scratch: [3]?*const pcre2.Surface.Types.Code = undefined;
    var stream = try shared.serialize(&.{ shared.code.?, shared.code.? }, &scratch);

    // A fact about the bytes, not about this test: the stream really does hold
    // three blocks, so the refusal below is about the destination.
    const count = try pcre2.Regex.serializedCodeCount(stream.slice());
    try std.testing.expectEqual(@as(u32, 3), count);

    // Initialised rather than `undefined`, so the check below is that the call
    // wrote nothing rather than a read of memory this test never set.
    var short = [_]?*pcre2.Surface.Types.Code{null};
    try std.testing.expectError(
        error.OvectorTooSmall,
        pcre2.Regex.decode(stream.slice(), count, &short, &general),
    );
    try std.testing.expectEqual(@as(?*pcre2.Surface.Types.Code, null), short[0]);

    // The same bytes into a destination that is long enough, which is what
    // makes the refusal about the length rather than about the stream.
    var roomy: [3]?*pcre2.Surface.Types.Code = undefined;
    var decoded = try pcre2.Regex.decode(stream.slice(), count, &roomy, &general);
    try std.testing.expectEqual(shared.captureCount(), decoded.captureCount());
    try std.testing.expect(roomy[0] != null);
    try std.testing.expect(roomy[1] != null);
    try std.testing.expect(roomy[2] != null);

    // Each of the three is a block this pair handed out, asked of the pair
    // rather than of a count: `allocations` is already positive from the two
    // contexts and the character tables, so only the addresses say the decode
    // went through the allocator it was given. A decoder that quietly used
    // upstream's default would leave all three unclaimed here while still
    // balancing the counters at the end.
    try std.testing.expect(isLive(&counter, roomy[0].?));
    try std.testing.expect(isLive(&counter, roomy[1].?));
    try std.testing.expect(isLive(&counter, roomy[2].?));

    // Everything this test made through that pair, released exactly once.
    // `decode` answered the first block as a `Regex` and the other two as bare
    // pointers; each is released through the memctl it carries, which is this
    // pair's.
    for (roomy[1..]) |block| freeBlock(block);
    decoded.deinit();
    general.freeTables(tables);
    context.deinit();
    general.deinit();
    stream.deinit();
    shared.deinit();

    // Conservation and ownership, with nothing pinned. How many blocks a decode
    // allocates is upstream's business; what is asserted is that every block
    // this pair handed out came back, that none came back that it never handed
    // out, and that none was handed out that it could not track -- the last two
    // counters exist so that a pair which dropped what it could not match could
    // not satisfy the first line without releasing anything.
    try std.testing.expectEqual(counter.allocations, counter.frees);
    try std.testing.expectEqual(@as(usize, 0), counter.unknown_frees);
    try std.testing.expectEqual(@as(usize, 0), counter.unrecorded);
}

/// Releases one compiled block through the published native route.
///
/// `pcre2_code_free_N` is the only thing that frees a compiled block, and the
/// facade hands out the translated header that declares it as `pcre2.c`
/// precisely for the entry points it does not wrap (`zig/root.zig:245`). The
/// typed surface cannot make a second owner instead: `Regex.code` is readable
/// and is handed to unwrapped calls, but its own documentation says writing it
/// is not a supported use (`zig/widthed.zig:1687-1691`), so a `Regex` built
/// from one of these pointers would not be a supported value either.
///
/// Which allocator this reaches is a fact about the block, and for a decoded
/// block the block's memctl is the one `decode` was handed, not the one that
/// was serialized: the new block is allocated through `gcontext`
/// (`src/pcre2_serialize.c:215-218`) and the copy that follows starts one
/// `pcre2_memctl` past both ends (`:225-228`), so the allocator that produced
/// the stream is dropped rather than carried over. `pcre2_code_free_N` then
/// releases the block, and for a decoded one its shared tables too, through
/// `code->memctl` (`src/pcre2_compile.c:1212-1227`). Passing the `Counter` pair
/// to `decode` is therefore what makes every one of these frees observable,
/// which is what the test above relies on.
///
/// The width is picked at compile time, so a build names the one symbol that
/// belongs to it and the other two are never referenced. All three are declared,
/// and all three are routed in a runtime-loaded build
/// (`runtime/library.zig:238`, `:270`).
fn freeBlock(block: ?*pcre2.Surface.Types.Code) void {
    switch (pcre2.compiled_width) {
        .@"8" => pcre2.c.pcre2_code_free_8(block),
        .@"16" => pcre2.c.pcre2_code_free_16(block),
        .@"32" => pcre2.c.pcre2_code_free_32(block),
    }
}

// ---------------------------------------------------------------------------
// The POSIX wrapper, where this build has one
// ---------------------------------------------------------------------------

test "the POSIX wrapper compiles, matches and reports its own codes" {
    nativeReady();
    if (pcre2.Posix.availability != .linked) {
        // Not a skip and not a narrowing of what is checked: the wrapper is 8-bit
        // by construction (`src/pcre2posix.h:104-119`), so a build of width 16
        // or 32 has no wrapper to call at all. The fact that this build says so
        // is the assertion; `Posix.compile` there is a compile-time refusal
        // naming the missing fact.
        try std.testing.expectEqual(
            @as(pcre2.Posix.Availability, .unavailable),
            pcre2.Posix.availability,
        );
        return;
    }

    // Under `-Druntime` this test is what checks that the four POSIX names go
    // through the dispatch rather than being left as direct externs: every call
    // below reads a table field, and a direct reference would be a link error
    // naming `pcre2_regcomp` and its three siblings rather than a runtime
    // answer. `build.zig` compiles the wrapper into the core for width 8 and
    // exports the four from it, which is what lets one provider carry them.
    // Under a linked build the same calls are ordinary linked calls, the
    // expectations are the same, and `pcre2.Posix.routed` says which mechanism
    // this build is in.

    // The subject is spelled with the sentinel type it is: the wrapper takes a
    // `const char *` and measures it with `strlen`
    // (`src/pcre2posix.c:385-388`), so that is what the typed surface asks
    // for rather than a slice whose length it would have to invent.
    const subject: [:0]const u8 = "xabc";
    var matches: [4]pcre2.Posix.Match = undefined;

    // `compile` answers with the wrapper's own block by value rather than a
    // pointer into its own frame, so the pattern is this test's: `exec` takes
    // a pointer to one, and the `deinit` below releases the compiled pattern and
    // the match-data block the wrapper put inside it, once
    // (`src/pcre2posix.c:254-259`).
    var compiled: pcre2.Posix.Compiled = switch (try pcre2.Posix.compile("a(b)c", 0)) {
        .compiled => |owned| owned,
        .rejected => |rejection| {
            std.debug.print("the POSIX pattern was refused with {d}\n", .{rejection.code});
            return error.FixtureMismatch;
        },
    };
    defer compiled.deinit();

    switch (try pcre2.Posix.exec(&compiled, subject, &matches, 0)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    // "xabc": group 0 is units 1..4 and group 1 is unit 2..3.
    try std.testing.expectEqualStrings("abc", pcre2.Posix.capture(subject, matches[0]).?);
    try std.testing.expectEqualStrings("b", pcre2.Posix.capture(subject, matches[1]).?);

    switch (try pcre2.Posix.exec(&compiled, "xyz", &matches, 0)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }

    // A pattern the wrapper refuses is a value carrying POSIX's own code, and
    // `pcre2_regerror` has a message for it.
    //
    // An unbalanced `(` is the parenthesis error and not the catch-all: the
    // wrapper translates PCRE2's compile errors through its own table, and the
    // missing-closing-parenthesis entry is `REG_EPAREN`
    // (`src/pcre2posix.c:146`, reached because `pcre2_compile` answers 114 and
    // the wrapper indexes with `errorcode - 100`, `:310-313`). `REG_BADPAT` is
    // what an error that is *not* in that table becomes, so pinning it here
    // would assert the fallback and not the classification.
    switch (try pcre2.Posix.compile("a(b", 0)) {
        .compiled => |compiled_regex| {
            // `deinit` takes the block mutably and the capture is const, so
            // the release goes through a mutable copy of it.
            var to_release = compiled_regex;
            to_release.deinit();
            return error.FixtureMismatch;
        },
        .rejected => |rejection| {
            try std.testing.expectEqual(@as(c_int, pcre2.Posix.code.eparen), rejection.code);
        },
    }
    // The other direction of the same parenthesis problem is classified the
    // same way rather than falling through to `REG_BADPAT`: `a)` is an
    // unmatched closing parenthesis, 122, which that table also maps to
    // `REG_EPAREN` (`src/pcre2posix.c:156`). Two patterns and two table entries
    // landing on one code is what shows the answer is the classification and
    // not the pattern text.
    switch (try pcre2.Posix.compile("a)", 0)) {
        .compiled => |compiled_regex| {
            var to_release = compiled_regex;
            to_release.deinit();
            return error.FixtureMismatch;
        },
        .rejected => |rejection| {
            try std.testing.expectEqual(@as(c_int, pcre2.Posix.code.eparen), rejection.code);
        },
    }

    // A genuinely non-participating optional group has unset offsets.
    var optional_group = switch (try pcre2.Posix.compile("a(b)?c", 0)) {
        .compiled => |owned| owned,
        .rejected => return error.FixtureMismatch,
    };
    defer optional_group.deinit();
    switch (try pcre2.Posix.exec(&optional_group, "ac", &matches, 0)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqual(pcre2.Posix.unset, matches[1].rm_so);
    try std.testing.expect((pcre2.Posix.capture("ac", matches[1]) == null));
    // Every slot the pattern did not fill is the same marker, and it is filled
    // because `nmatch` is the length of the array the caller passed rather than
    // anything about the subject: `rc` is clamped to it and the rest of the
    // vector is written out to it (`src/pcre2posix.c:400-408`).
    try std.testing.expectEqual(pcre2.Posix.unset, matches[3].rm_so);
    try std.testing.expectEqual(pcre2.Posix.unset, matches[3].rm_eo);

    // `REG_STARTEND` makes the subject argument carry offsets rather than a
    // string, so the typed surface refuses it instead of passing a pointer
    // where the wrapper reads two integers.
    try std.testing.expectError(
        error.UnsupportedOption,
        pcre2.Posix.exec(&compiled, "abc", &matches, pcre2.Posix.option.startend),
    );
}

/// The bytes of `ascii` as this width's code units, for a pattern or subject the
/// test writes inline.
///
/// A comptime array rather than a widening at run time, because every literal in
/// this file is ASCII and a comptime one cannot be read past its end. The
/// returned slice points at a container-level constant, so it lives as long as
/// the test binary does and needs no cleanup.
fn widenLiteral(comptime ascii: []const u8) []const Unit {
    if (ascii.len == 0) return &.{};
    const widened = comptime blk: {
        var buf: [ascii.len]Unit = undefined;
        for (ascii, 0..) |byte, i| buf[i] = byte;
        break :blk buf;
    };
    return &widened;
}
