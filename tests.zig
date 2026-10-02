//! Behavioural tests for the PCRE2 facade.
//!
//! The expectations live in `testdata/foundation-fixtures.zig` and came out of
//! this repository's own `testdata/`, which is upstream's `pcre2test` input and
//! expected output for release 10.49, or were worked out by hand from the C and
//! say so. Nothing here was produced by running this fork, so a passing test is
//! PCRE2 agreeing with itself, not this binding agreeing with itself.
//!
//! Three things are checked, in this order: the known answers; the bounds the
//! facade owns itself, which upstream would answer differently or not at all;
//! and the lifetime of a capture, which is a window on the caller's own buffer
//! rather than a copy of it and is readable only while the offsets in the block
//! still describe the subject the caller passed to that attempt.
//!
//! Every public method on `pcre2.Regex`, `pcre2.MatchData` and
//! `pcre2.MatchContext` is called from this file, which is what makes building
//! the test binary a real check of the facade rather than of an unreferenced C
//! archive. `pcre2.version` is called below for where its answer lives rather
//! than for what it says, and from `smoke.zig`, which prints it.
//!
//! Nothing here compares a facade accessor with `pcre2.c`. Agreement between a
//! wrapper and the member it wraps is not evidence about PCRE2, and the known
//! answers above already hold the binding against upstream's own expected
//! output rather than against itself.

const std = @import("std");
const pcre2 = @import("pcre2");
const fixtures = @import("foundation_fixtures");

/// Compiles a pattern the test expects PCRE2 to accept.
///
/// The union is unwrapped through a switch rather than by naming the field,
/// so a pattern that unexpectedly does not compile reports the diagnostic
/// upstream gave instead of tripping a union-tag safety panic.
fn mustCompile(pattern: []const u8, options: pcre2.CompileOptions) !pcre2.Regex {
    return switch (try pcre2.Regex.compile(pattern, options)) {
        .compiled => |regex| regex,
        .rejected => |rejection| {
            std.debug.print("pattern {s} was rejected: error {d} at offset {d}: {s}\n", .{
                pattern,
                rejection.code,
                rejection.offset,
                rejection.text.slice(),
            });
            return error.FixtureMismatch;
        },
    };
}

test "every known answer in the fixture table holds" {
    for (fixtures.cases) |case| {
        var compiled = switch (try pcre2.Regex.compile(case.pattern, case.compile)) {
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
                // the offending byte of the pattern.
                try std.testing.expectEqual(expected.code, rejection.code);
                try std.testing.expectEqual(expected.offset, rejection.offset);
                try std.testing.expectEqualStrings(expected.text, rejection.text.slice());
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
            try std.testing.expectEqualStrings(named.name, entry.name);
            try std.testing.expectEqualStrings(
                named.name,
                compiled.nameForNumber(named.number) orelse return error.FixtureMismatch,
            );
            try std.testing.expectEqual(
                named.number,
                compiled.numberForName(named.name) orelse return error.FixtureMismatch,
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

        const result = try compiled.match(
            case.subject,
            case.start_offset,
            case.match_options,
            &match_data,
            &context,
        );
        try expectAnswer(case, result, &compiled, &match_data);
    }
}

/// Compares one `MatchOutcome` against the fixture's answer, group by group
/// where it matched.
fn expectAnswer(
    case: fixtures.Case,
    result: pcre2.MatchOutcome,
    regex: *const pcre2.Regex,
    match_data: *const pcre2.MatchData,
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
                    try std.testing.expectEqualStrings(bytes, got);
                    const found = range orelse return mismatch(case, "a capture", "unset");
                    try std.testing.expectEqualStrings(
                        bytes,
                        match_data.subject[found.start..found.end],
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
            try std.testing.expectEqualStrings(want.text, got.text.slice());
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

// ---------------------------------------------------------------------------
// Bounds the facade owns
// ---------------------------------------------------------------------------

test "a start offset past the end of the subject is refused before any C runs" {
    var regex = try mustCompile("abc", .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    // One past the end of a three byte subject. PCRE2 answers this itself with
    // PCRE2_ERROR_BADOFFSET, from inside the matcher; the facade names the
    // condition instead, so a caller can act on it before spending a match.
    try std.testing.expectError(
        error.StartOffsetOutOfRange,
        regex.match("abc", 4, .{}, &match_data, null),
    );
    // Exactly the end of the subject is in range, and a pattern that needs
    // three bytes simply does not match there.
    switch (try regex.match("abc", 3, .{}, &match_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
}

test "a group number past the block's capture count is refused" {
    var regex = try mustCompile("(a)(b)", .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    try std.testing.expectEqual(@as(u32, 2), regex.captureCount());
    try std.testing.expectEqual(@as(u32, 3), match_data.captureCount());
    switch (try regex.match("ab", 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    // Group 3 does not exist. Reading it would be past the end of PCRE2's
    // offset vector, so the facade says so instead of indexing.
    try std.testing.expectError(error.NoSuchGroup, match_data.groupRange(3));
    try std.testing.expectError(error.NoSuchGroup, match_data.group(3));
}

test "releasing an owned block hands the memory back once and marks it released" {
    var regex = try mustCompile("(a)", .{});
    var match_data = try pcre2.MatchData.create(&regex);
    var context = try pcre2.MatchContext.init();
    try std.testing.expect(match_data.raw != null);
    try std.testing.expect(context.raw != null);

    match_data.deinit();
    context.deinit();
    regex.deinit();

    // Each owner now holds null, so a caller that also has a `defer` in scope
    // cannot reach the same block twice. The second release below must be the
    // same no-op, not a second free.
    try std.testing.expectEqual(@as(?*pcre2.c.pcre2_match_data_8, null), match_data.raw);
    try std.testing.expectEqual(@as(?*pcre2.c.pcre2_match_context_8, null), context.raw);
    try std.testing.expectEqual(@as(?*pcre2.c.pcre2_code_8, null), regex.code);
    match_data.deinit();
    context.deinit();
    regex.deinit();
    try std.testing.expectEqual(@as(?*pcre2.c.pcre2_code_8, null), regex.code);
}

test "a name the pattern did not declare, and a name too long to declare, are both null" {
    var regex = try mustCompile("(?<abc>x)(?'xyz'y)", .{});
    defer regex.deinit();

    // Upstream keeps the table in name order (`pcre2_compile_cgroup.c:106-108`),
    // and "abc" sorts before "xyz" here, so entry 1 is the last one and index 2
    // is past the end. The pattern also happens to write its two names in that
    // order, which is why this pattern cannot tell name order apart from the
    // order they were written in; the test below is the one that does.
    try std.testing.expectEqual(@as(u32, 2), regex.nameCount());
    const last = regex.nameAt(1) orelse return error.FixtureMismatch;
    try std.testing.expectEqual(@as(u32, 2), last.number);
    try std.testing.expectEqualStrings("xyz", last.name);
    if (regex.nameAt(2) != null) return error.FixtureMismatch;

    try std.testing.expectEqualStrings("abc", regex.nameForNumber(1) orelse return error.FixtureMismatch);
    if (regex.nameForNumber(99) != null) return error.FixtureMismatch;
    if (regex.numberForName("nope") != null) return error.FixtureMismatch;

    // pcre2_compile.c:2671 refuses a group name longer than MAX_NAME_SIZE, so
    // no pattern this fork accepted can have a name of this length and the
    // lookup must not go looking for one.
    var too_long: [pcre2.max_name_length + 1]u8 = @splat('a');
    if (regex.numberForName(&too_long) != null) return error.FixtureMismatch;
}

test "the name table is walked in name order, and an entry ends at its own NUL" {
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
    var regex = try mustCompile("(?<zebra>1)(?<m>2)(?<alpha>3)(?<al>4)", .{});
    defer regex.deinit();

    try std.testing.expectEqual(@as(u32, 4), regex.nameCount());

    const expected = [_]pcre2.Name{
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
        try std.testing.expectEqualStrings(want.name, entry.name);
        try std.testing.expectEqualStrings(
            want.name,
            regex.nameForNumber(want.number) orelse return error.FixtureMismatch,
        );
        try std.testing.expectEqual(
            want.number,
            regex.numberForName(want.name) orelse return error.FixtureMismatch,
        );
    }
    if (regex.nameAt(expected.len) != null) return error.FixtureMismatch;
}

test "the version answer is the caller's own buffer, and a short one is refused" {
    // A guard byte, not a version: nothing below can be satisfied by a value
    // this file put in the buffer itself. 64 bytes is past the 24 code units
    // every release so far has needed (`doc/pcre2.txt:1468-1469`); what the
    // library actually asks for is what the rest of this test works from.
    var buffer: [64]u8 = @splat(0xaa);
    const reported = try pcre2.version(&buffer);

    // Where the bytes live is the property under test. A facade that filled
    // its own frame and returned a slice of that frame would hand back the
    // right string and leave this comparison pointing into a frame that has
    // already been reused for something else.
    try std.testing.expectEqual(@intFromPtr(&buffer[0]), @intFromPtr(reported.ptr));
    // The slice ends on a terminator the copy actually wrote, so the
    // sentinel in its type is a fact about the buffer rather than a claim
    // about a byte nobody checked.
    try std.testing.expectEqual(@as(u8, 0), buffer[reported.len]);
    // Nothing was written past it either: a byte beyond the terminator is
    // still the guard, which a copy that ran on would have replaced.
    if (reported.len + 1 < buffer.len) {
        try std.testing.expectEqual(@as(u8, 0xaa), buffer[reported.len + 1]);
    }

    // One byte less than the library asked for, which is short by exactly the
    // terminator. A capacity check that forgot to count it would let this
    // call through and hand back a string with no room for its own zero.
    var short_buffer: [64]u8 = @splat(0xaa);
    const too_short = short_buffer[0..reported.len];
    try std.testing.expectError(error.VersionBufferTooSmall, pcre2.version(too_short));
    // And the refusal is before the call that writes, not after it: not one
    // byte of the caller's storage changed. A short buffer written and then
    // reported would leave the version string in the first bytes here.
    for (too_short) |byte| try std.testing.expectEqual(@as(u8, 0xaa), byte);
}

// ---------------------------------------------------------------------------
// Ownership
// ---------------------------------------------------------------------------

test "a capture is a window on the caller's subject, not a copy of it" {
    var subject = [_]u8{ 'x', 'b', 'x' };
    var regex = try mustCompile("x(b)x", .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match(&subject, 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    const captured = (try match_data.group(1)) orelse return error.FixtureMismatch;
    try std.testing.expectEqualStrings("b", captured);
    const range = (try match_data.groupRange(1)) orelse return error.FixtureMismatch;
    try std.testing.expectEqual(@as(usize, 1), range.start);
    try std.testing.expectEqual(@as(usize, 2), range.end);

    // Writing through the caller's own buffer is visible through the capture.
    // A binding that had copied the substring out would still be holding "b"
    // here, so this fails on a copy and passes only on a borrow.
    subject[1] = 'B';
    try std.testing.expectEqualStrings("B", captured);
    try std.testing.expectEqual(@as(usize, 3), match_data.subject.len);
}

test "an attempt that did not match leaves nothing readable, whatever the last one found" {
    var regex = try mustCompile("(\\d+)-(\\w+)", .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match("123-abc", 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualStrings("abc", (try match_data.group(2)) orelse return error.FixtureMismatch);
    const found = (try match_data.groupRange(2)) orelse return error.FixtureMismatch;
    try std.testing.expectEqual(@as(usize, 4), found.start);
    try std.testing.expectEqual(@as(usize, 7), found.end);

    // The same block, reused over a one byte subject the pattern cannot match.
    // PCRE2 writes the offset vector only on the path that matched
    // (`src/pcre2_match.c:1045-1053`); the non-match path returns through
    // `src/pcre2_match.c:8214-8220` having set only the subject, its length,
    // the start offset and the return code. Group 2 therefore still holds
    // 4..7 from the subject above, and those offsets are past the end of this
    // one: reading them is an out-of-bounds read, which is a bounds panic in
    // Debug and ReleaseSafe and a silent read of unrelated memory in
    // ReleaseFast.
    switch (try regex.match("z", 0, .{}, &match_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expect((try match_data.groupRange(2)) == null);
    try std.testing.expect((try match_data.group(2)) == null);
    // The whole match is no more readable than a capture, and the group-number
    // bound still comes first: it is a statement about the index, not about the
    // match.
    try std.testing.expect((try match_data.groupRange(0)) == null);
    try std.testing.expectError(error.NoSuchGroup, match_data.groupRange(3));

    // A further match re-arms the block, and the captures are then that
    // subject's own: "q" is byte 2 of "7-q", not bytes 4..7 of anything.
    switch (try regex.match("7-q", 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualStrings("q", (try match_data.group(2)) orelse return error.FixtureMismatch);
}

test "a group the pattern skipped reports no range, and one that took part reports its own" {
    var regex = try mustCompile("(a)|(b)", .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match("b", 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    // PCRE2 leaves PCRE2_UNSET in the offset vector for the alternative the
    // pattern did not take (`src/pcre2_match.c:1036-1037` and `:1053`), and a
    // group that did not take part is reported as having no range rather than
    // as a zero-length one. "b" is the one byte at 0..1.
    try std.testing.expect((try match_data.groupRange(1)) == null);
    try std.testing.expect((try match_data.group(1)) == null);
    const second = (try match_data.groupRange(2)) orelse return error.FixtureMismatch;
    try std.testing.expectEqual(@as(usize, 0), second.start);
    try std.testing.expectEqual(@as(usize, 1), second.end);
    try std.testing.expectEqualStrings("b", (try match_data.group(2)) orelse return error.FixtureMismatch);
}
