//! Behavioural tests for the typed PCRE2 facade.
//! Fixtures and expected output come from upstream `pcre2test` data.
//! Helpers encode text per width and check observable behavior.

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

/// Copies ASCII bytes into caller storage, one code unit per byte.
fn widen(ascii: []const u8, out: []Unit) ![]const Unit {
    if (out.len < ascii.len) return error.BenchmarkWorkspaceTooSmall;
    for (ascii, 0..) |byte, i| {
        if (byte > std.math.maxInt(Unit)) return error.BenchmarkWorkspaceTooSmall;
        out[i] = byte;
    }
    return out[0..ascii.len];
}

/// Decodes UTF-8 to the selected width; width 8 preserves bytes.
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

/// Renders code units as fixture bytes, re-encoding UTF when requested.
/// Refuses unrepresentable units instead of truncating.
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

/// Unwraps expected compile success and reports unexpected rejection as a test error.
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

test "every known answer in the fixture table holds" {
    nativeReady();
    var pattern_units: [512]Unit = undefined;
    var subject_units: [512]Unit = undefined;
    // Keep name input separate from the subject buffer.
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
                // Compare the diagnostic code and pattern offset.
                try std.testing.expectEqual(expected.code, rejection.code);
                try std.testing.expectEqual(expected.offset, rejection.offset);
                continue;
            },
        };
        defer compiled.deinit();

        if (case.capture_count) |expected| {
            try std.testing.expectEqual(expected, compiled.captureCount());
        }
        // Compare every name declared by the fixture.
        try std.testing.expectEqual(@as(u32, @intCast(case.names.len)), compiled.nameCount());
        for (case.names, 0..) |named, i| {
            const entry = compiled.nameAt(@intCast(i)) orelse return error.FixtureMismatch;
            try std.testing.expectEqual(named.number, entry.number);
            // Names use this width's code units; convert both sides before comparing.
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
        // Capacity covers group 0 and all capturing groups.
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
            // Fixture groups must be contiguous from group 0; trailing groups may be omitted.
            for (captures, 0..) |want, i| {
                try std.testing.expectEqual(@as(u32, @intCast(i)), want.number);
                // Ensure each fixture group exists in the compiled pattern.
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
            // Only UTF validator failures report the offending code unit.
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
    // Each width uses its own malformed code unit and error number.
    var units: [4]Unit = undefined;
    const wanted = fixtures.malformed_units[malformed_index];
    for (wanted, 0..) |value, i| {
        units[i] = @intCast(value);
    }
    const subject = units[0..wanted.len];

    var regex = try mustCompile(&[_]Unit{'.'}, .{ .utf = true });
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

test "a start offset past the end of the subject is refused before matching" {
    nativeReady();
    var regex = try mustCompile(widenLiteral("abc"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    // The facade names the out-of-range offset before PCRE2 reports BADOFFSET.
    try std.testing.expectError(
        error.StartOffsetOutOfRange,
        regex.match(widenLiteral("abc"), 4, .{}, &match_data, null),
    );
    // Subject end is a valid offset; this pattern simply cannot match there.
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
    // Group 3 is outside the offset vector.
    try std.testing.expectError(error.NoSuchGroup, match_data.groupRange(3));
    try std.testing.expectError(error.NoSuchGroup, match_data.group(3));
}

test "a block too small for the regex is refused, and its earlier captures go with it" {
    nativeReady();
    // This block was sized for `small` and does not remember its pattern.
    var small = try mustCompile(widenLiteral("abc"), .{});
    defer small.deinit();
    var match_data = try pcre2.MatchData.create(&small);
    defer match_data.deinit();

    // Verify the previous match is readable before testing the refusal.
    try std.testing.expectEqual(@as(u32, 0), small.captureCount());
    try std.testing.expectEqual(@as(u32, 1), match_data.captureCount());
    switch (try small.match(widenLiteral("abc"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("abc"),
        (try match_data.group(0)) orelse return error.FixtureMismatch,
    );

    var larger = try mustCompile(widenLiteral("(a)(b)(c)"), .{});
    defer larger.deinit();
    try std.testing.expectEqual(@as(u32, 3), larger.captureCount());

    // PCRE2 would return a truncated zero; the facade rejects the undersized block first.
    try std.testing.expectError(
        error.OvectorTooSmall,
        larger.match(widenLiteral("abc"), 0, .{}, &match_data, null),
    );

    // A refusal clears match state although PCRE2 leaves the previous offsets in place.
    try std.testing.expect(!match_data.matched);
    try std.testing.expect((try match_data.groupRange(0)) == null);
    try std.testing.expect((try match_data.group(0)) == null);
    // Group bounds do not depend on the block's match state.
    try std.testing.expectError(error.NoSuchGroup, match_data.groupRange(1));

    // A pattern that fits can reuse the block.
    switch (try small.match(widenLiteral("abc"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("abc"),
        (try match_data.group(0)) orelse return error.FixtureMismatch,
    );
}

test "releasing an owned block hands the memory back once" {
    nativeReady();
    // Verify that releasing the owned contexts twice is safe and leaves them cleared.
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

    // PCRE2 sorts the name table, not by the order names appear in the pattern.
    try std.testing.expectEqual(@as(u32, 2), regex.nameCount());
    const last = regex.nameAt(1) orelse return error.FixtureMismatch;
    try std.testing.expectEqual(@as(u32, 2), last.number);
    // Names use the selected width's code units.
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

    // PCRE2 rejects names longer than `MAX_NAME_SIZE`.
    var too_long: [pcre2.max_name_length + 1]Unit = @splat('a');
    if (regex.numberForName(&too_long) != null) return error.FixtureMismatch;
}

test "the name table is walked in name order, and an entry ends at its own NUL" {
    nativeReady();
    // Names sort alphabetically while group numbers follow pattern order.
    // Prefix names and padding exercise the table decoder.
    var regex = try mustCompile(widenLiteral("(?<zebra>1)(?<m>2)(?<alpha>3)(?<al>4)"), .{});
    defer regex.deinit();

    // Convert runtime name-table code units to and from fixture bytes.
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
        // Full-slice comparison catches names that run past NUL into padding.
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
    // Use a guard-filled buffer to check the returned slice and writes.
    var buffer: [64]Unit = @splat(0xaa);
    const reported = try pcre2.version(&buffer);

    // Confirm the returned slice points into the caller's buffer.
    try std.testing.expectEqual(@intFromPtr(&buffer[0]), @intFromPtr(reported.ptr));
    // Confirm the returned slice includes a real NUL terminator.
    try std.testing.expectEqual(@as(Unit, 0), buffer[reported.len]);
    // The sentinel after NUL must remain untouched.
    if (reported.len + 1 < buffer.len) {
        try std.testing.expectEqual(@as(Unit, 0xaa), buffer[reported.len + 1]);
    }

    // One code unit short of required capacity, including the terminator.
    var short_buffer: [64]Unit = @splat(0xaa);
    const too_short = short_buffer[0..reported.len];
    try std.testing.expectError(error.VersionBufferTooSmall, pcre2.version(too_short));
    // A rejected short buffer must remain unchanged.
    for (too_short) |unit| try std.testing.expectEqual(@as(Unit, 0xaa), unit);
}

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

    // Mutation through the caller's subject must be visible through the capture.
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

    // PCRE2 leaves old offsets after a non-match; the facade must hide them.
    switch (try regex.match(widenLiteral("z"), 0, .{}, &match_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expect((try match_data.groupRange(2)) == null);
    try std.testing.expect((try match_data.group(2)) == null);
    // No match clears captures, but invalid group numbers still error.
    try std.testing.expect((try match_data.groupRange(0)) == null);
    try std.testing.expectError(error.NoSuchGroup, match_data.groupRange(3));

    // A later match re-arms the block with offsets for its own subject.
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
    // Unset groups have no range rather than an empty capture.
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
    // One alternative matches; the other remains unset.
    var regex = try mustCompile(widenLiteral("(\\d+)|(x)"), .{});
    defer regex.deinit();
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    switch (try regex.match(widenLiteral("12345"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }

    // `get` returns a PCRE2-owned capture copy; release it with `Owned.deinit`.
    var owned = try match_data.get(1);
    defer owned.deinit();
    try std.testing.expectEqualSlices(Unit, widenLiteral("12345"), owned.slice());

    // `copy` writes into caller storage and includes a NUL terminator.
    var buffer: [6]Unit = @splat(0xaa);
    const written = try match_data.copy(1, &buffer);
    try std.testing.expectEqual(@as(usize, 5), written);
    try std.testing.expectEqualSlices(Unit, widenLiteral("12345"), buffer[0..written]);
    try std.testing.expectEqual(@as(Unit, 0), buffer[written]);

    // An undersized output is refused before the buffer changes.
    var short: [5]Unit = @splat(0xaa);
    try std.testing.expectError(error.SubstringBufferTooSmall, match_data.copy(1, &short));
    for (short) |unit| try std.testing.expectEqual(@as(Unit, 0xaa), unit);

    // Unset captures return `SubstringUnavailable` from copy APIs.
    try std.testing.expectError(error.SubstringUnavailable, match_data.get(2));
    try std.testing.expectError(error.SubstringUnavailable, match_data.copy(2, &short));

    // `copy_matched_subject` preserves the same capture from PCRE2's owned subject.
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
    // `captureCount` includes group 0.
    const count = match_data.captureCount();
    try std.testing.expectEqual(@as(u32, 4), count);

    // PCRE2 returns the whole capture list in one owned block.
    var list = try match_data.list();
    defer list.deinit();

    // The list count bounds its captures, not the block capacity.
    try std.testing.expectEqual(count, list.count);

    const expected = [_][]const u8{ "abc", "a", "b", "c" };
    // Widen runtime names into a workspace sized for the longest expected capture.
    var text_workspace: [3]Unit = undefined;
    for (expected, 0..) |want, i| {
        const got = list.get(@intCast(i)) orelse return error.FixtureMismatch;
        try std.testing.expectEqualSlices(Unit, try widen(want, &text_workspace), got);
    }
    if (list.get(count) != null) return error.FixtureMismatch;
}

/// One allocator-owned block, with its size for release.
const LiveBlock = struct {
    address: [*]u8,
    size: usize,
};

const Counter = struct {
    allocations: usize = 0,
    frees: usize = 0,
    bytes: usize = 0,
    /// Outstanding blocks, retained so frees can use their original sizes.
    live: [16]?LiveBlock = @splat(null),
    /// Frees for pointers this pair did not allocate.
    unknown_frees: usize = 0,
    /// Allocations that could not be recorded.
    unrecorded: usize = 0,
};

fn countingAllocate(size: usize, data: ?*anyopaque) callconv(.c) ?*anyopaque {
    const counter: *Counter = @ptrCast(@alignCast(data.?));
    // Page allocator frees without needing the allocation length.
    const memory = std.heap.page_allocator.alloc(u8, size) catch return null;
    counter.allocations += 1;
    counter.bytes += size;
    if (counter.allocations <= counter.live.len) {
        counter.live[counter.allocations - 1] = .{ .address = memory.ptr, .size = size };
    } else {
        // Keep untracked allocations visible to the leak check.
        counter.unrecorded += 1;
    }
    return @ptrCast(memory.ptr);
}

fn countingDeallocate(memory: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
    const counter: *Counter = @ptrCast(@alignCast(data.?));
    const address: [*]u8 = @ptrCast(memory orelse return);
    // Count unknown pointers rather than freeing memory this pair does not own.
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

/// Checks whether this allocator pair owns `block`.
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

    // Allocation counts vary; check ownership and conservation instead.
    try std.testing.expect(counter.allocations > 0);
    try std.testing.expect(counter.bytes > 0);
    try std.testing.expectEqual(@as(usize, 0), counter.unrecorded);
    try std.testing.expectEqual(@as(usize, 0), counter.frees);

    // Read a capture from the block produced by this allocator.
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("b"),
        (try match_data.group(2)) orelse return error.FixtureMismatch,
    );

    // Release every block through the caller's allocator pair.
    compiled.deinit();
    match_data.deinit();
    compile_context.deinit();
    general.deinit();

    // Every allocation must be tracked and released once; unknown counts stay zero.
    try std.testing.expect(counter.allocations > 0);
    try std.testing.expectEqual(counter.allocations, counter.frees);
    try std.testing.expectEqual(@as(usize, 0), counter.unknown_frees);
    try std.testing.expectEqual(@as(usize, 0), counter.unrecorded);
}

test "the newline convention the compile context sets changes what `$` accepts" {
    nativeReady();
    // Newline settings are copied into each pattern, so test each convention with its own block.
    // CRLF mode distinguishes a bare LF and rejects invalid values.
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

    // LF ends a line in LF mode, but not in CRLF mode.
    switch (try under_crlf.match(widenLiteral("a\n"), 0, .{}, &crlf_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
    // CRLF mode still matches a real CRLF ending.
    switch (try under_crlf.match(widenLiteral("a\r\n"), 0, .{}, &crlf_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }

    // Invalid settings are refused without replacing the previous value.
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
    // Converted text is NUL-terminated, but its reported length excludes NUL.
    // Compile the returned slice by its explicit length.
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

    // A path glob's wildcard does not cross `/`.
    switch (try compiled.match(widenLiteral("src/notes.txt"), 0, .{}, &match_data, null)) {
        .no_match => {},
        else => return error.FixtureMismatch,
    }
    // Backslash remains an ordinary subject character.
    switch (try compiled.match(widenLiteral("src\\notes.txt"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    // The `.txt` suffix remains part of the converted pattern.
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
    // Zero continues; positive declines this start and negative aborts with that code.
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

    // This build has no SLJIT; record whether the provider nevertheless reports JIT support.
    var jit = false;
    switch (try compiled.jitCompile(pcre2.jit_option.complete)) {
        .compiled => jit = true,
        .refused => |refusal| {
            try std.testing.expectEqual(@as(i32, pcre2.c.PCRE2_ERROR_JIT_BADOPTION), refusal.code);
            try std.testing.expect(refusal.text.len > 0);
        },
    }

    // JIT-stack creation is independently unsupported in this build.
    try std.testing.expectError(error.JitUnsupported, pcre2.JitStack.create(1024, 8192));

    var match_data = try pcre2.MatchData.create(&compiled);
    defer match_data.deinit();
    var context = try pcre2.MatchContext.init();
    defer context.deinit();

    // Establish the interpreter result before comparing the JIT path.
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
        // JIT code uses the same matcher.
        .matched => {
            try std.testing.expect(jit);
            try std.testing.expectEqualSlices(
                Unit,
                widenLiteral("aaa"),
                (try match_data.group(0)) orelse return error.FixtureMismatch,
            );
        },
        // There is no interpreter fallback when JIT is disabled.
        .failed => |failure| {
            try std.testing.expect(!jit);
            try std.testing.expectEqual(@as(i32, pcre2.c.PCRE2_ERROR_JIT_BADOPTION), failure.code);
            try std.testing.expect(failure.text.len > 0);
            // A failed JIT attempt clears the prior match state.
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

    // Overflow mode reports required capacity, including NUL, without writing.
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

    // A fitting buffer receives the result and replacement count.
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

    // A short buffer is refused without writing.
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

// Substitution invalidates prior match data unless `matched` mode preserves it.
test "a substitution leaves the block describing nothing, whatever the match before it found" {
    nativeReady();
    var compiled = try mustCompile(widenLiteral("(a)"), .{});
    defer compiled.deinit();
    var match_data = try pcre2.MatchData.create(&compiled);
    defer match_data.deinit();

    // Start with a successful match to make stale captures observable.
    switch (try compiled.match(widenLiteral("a"), 0, .{}, &match_data, null)) {
        .matched => {},
        else => return error.FixtureMismatch,
    }
    try std.testing.expectEqualSlices(
        Unit,
        widenLiteral("a"),
        (try match_data.group(1)) orelse return error.FixtureMismatch,
    );

    // This substitution makes more replacements than the block has pairs.
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

    // After substitution, all capture accessors report unavailable.
    if ((try match_data.groupRange(1)) != null) return error.FixtureMismatch;
    if ((try match_data.group(1)) != null) return error.FixtureMismatch;
    try std.testing.expectError(error.SubstringUnavailable, match_data.ovector());
    try std.testing.expectError(error.SubstringUnavailable, match_data.list());
    try std.testing.expectError(error.SubstringUnavailable, match_data.get(1));
    try std.testing.expectError(error.SubstringUnavailable, match_data.copy(1, &buffer));

    // The block can be reused by a later match.
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
    // Greedy `a+` has one DFA match; ungreedy `a+?` exposes shorter candidates.
    const subject = widenLiteral("aaab");
    var workspace: [32]c_int = undefined;
    // Keep the workspace mutable because `dfa` takes a pointer.
    var found: pcre2.DfaWorkspace = .{ .offsets = &workspace };

    var greedy = try mustCompile(widenLiteral("a+"), .{});
    defer greedy.deinit();
    var greedy_data = try pcre2.MatchData.create(&greedy);
    defer greedy_data.deinit();
    switch (try greedy.dfa(subject, 0, .{}, &greedy_data, null, &found)) {
        .matched => |matched| {
            // Auto-possessification leaves only one candidate for greedy `a+`.
            try std.testing.expectEqual(@as(usize, 1), matched.pairs);
            const offsets = try greedy_data.ovector();
            try std.testing.expectEqual(@as(usize, 0), offsets[0]);
            try std.testing.expectEqual(subject.len - 1, offsets[1]);
        },
        else => return error.FixtureMismatch,
    }

    // Ungreedy matching exposes multiple longest-first candidates.
    var ungreedy = try mustCompile(widenLiteral("a+?"), .{});
    defer ungreedy.deinit();
    var roomy = try pcre2.MatchData.createWithOvector(8, null);
    defer roomy.deinit();
    switch (try ungreedy.dfa(subject, 0, .{}, &roomy, null, &found)) {
        .matched => |matched| {
            try std.testing.expectEqual(@as(usize, 3), matched.pairs);
            const offsets = try roomy.ovector();
            // Results are longest-first and each reported range must match the subject.
            var previous: ?usize = null;
            var run: [8]Unit = @splat(@as(Unit, 'a'));
            for (0..matched.pairs) |i| {
                const start = offsets[2 * i];
                const end = offsets[2 * i + 1];
                try std.testing.expect(start <= end);
                try std.testing.expect(end <= subject.len);
                // Each pair is no longer than the prior one and contains only `a`.
                if (previous) |was| try std.testing.expect(end - start <= was);
                previous = end - start;
                try std.testing.expectEqualSlices(Unit, run[0 .. end - start], subject[start..end]);
            }
            // Check the longest result as well as ordering.
            try std.testing.expectEqual(subject.len - 1, offsets[1] - offsets[0]);
        },
        else => return error.FixtureMismatch,
    }

    // A one-pair block reports truncation while keeping the longest range readable.
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

    // Workspaces below PCRE2's minimum are refused before matching.
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

    // The stream count is the value required by `decode`.
    try std.testing.expectEqual(@as(u32, 1), try pcre2.Regex.serializedCodeCount(stream.slice()));

    var decoded: [1]?*pcre2.Surface.Types.Code = undefined;
    var round_tripped = try pcre2.Regex.decode(stream.slice(), 1, &decoded, null);
    defer round_tripped.deinit();

    // The decoded block retains its metadata and match behavior.
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

// Serialization distinguishes incompatible tables and malformed data from allocation failure.
test "a stream PCRE2 will not build or read is refused as a refusal, not as a failed allocation" {
    nativeReady();
    // The two compiled blocks use distinct character-table addresses.
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

    // A single block has no table mismatch.
    var single: [1]?*const pcre2.Surface.Types.Code = undefined;
    var stream = try shared.serialize(&.{}, &single);
    defer stream.deinit();

    // Change the stream magic byte so both readers reject it.
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

// `next` updates its out-parameters only when another match exists.
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
        // The empty match at subject end is the final successful iteration.
        try std.testing.expectEqualSlices(
            Unit,
            if (found == 1) widenLiteral("a") else widenLiteral(""),
            (try match_data.group(0)) orelse return error.FixtureMismatch,
        );
        if (!match_data.next(&start_offset, &options)) break;
    }
    try std.testing.expectEqual(@as(usize, 2), found);
    // A false result leaves the last successful out-parameters unchanged.
    try std.testing.expectEqual(@as(u32, 0), options);
}

// Decode refuses a destination shorter than the stream's block count.
test "decoding refuses a destination shorter than the blocks asked for" {
    nativeReady();
    // Track allocations made by `decode` so every returned block is verified.
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
    // Repeating one block keeps all table addresses identical.
    var scratch: [3]?*const pcre2.Surface.Types.Code = undefined;
    var stream = try shared.serialize(&.{ shared.code.?, shared.code.? }, &scratch);

    // Confirm the stream contains three blocks before testing destination size.
    const count = try pcre2.Regex.serializedCodeCount(stream.slice());
    try std.testing.expectEqual(@as(u32, 3), count);

    // Initialize the short destination to verify refusal writes nothing.
    var short = [_]?*pcre2.Surface.Types.Code{null};
    try std.testing.expectError(
        error.OvectorTooSmall,
        pcre2.Regex.decode(stream.slice(), count, &short, &general),
    );
    try std.testing.expectEqual(@as(?*pcre2.Surface.Types.Code, null), short[0]);

    // Decode the same stream into a correctly sized destination.
    var roomy: [3]?*pcre2.Surface.Types.Code = undefined;
    var decoded = try pcre2.Regex.decode(stream.slice(), count, &roomy, &general);
    try std.testing.expectEqual(shared.captureCount(), decoded.captureCount());
    try std.testing.expect(roomy[0] != null);
    try std.testing.expect(roomy[1] != null);
    try std.testing.expect(roomy[2] != null);

    // Confirm each decoded block came from the supplied allocator.
    try std.testing.expect(isLive(&counter, roomy[0].?));
    try std.testing.expect(isLive(&counter, roomy[1].?));
    try std.testing.expect(isLive(&counter, roomy[2].?));

    // Release the decoded blocks and their contexts through the supplied allocator.
    for (roomy[1..]) |block| freeBlock(block);
    decoded.deinit();
    general.freeTables(tables);
    context.deinit();
    general.deinit();
    stream.deinit();
    shared.deinit();

    // Every allocation was tracked and freed once; unknown and unrecorded counts stay zero.
    try std.testing.expectEqual(counter.allocations, counter.frees);
    try std.testing.expectEqual(@as(usize, 0), counter.unknown_frees);
    try std.testing.expectEqual(@as(usize, 0), counter.unrecorded);
}

/// Frees a decoded PCRE2 block through this build's width-specific symbol.
/// The block's allocator metadata routes deallocation to the pair passed to `decode`.
fn freeBlock(block: ?*pcre2.Surface.Types.Code) void {
    switch (pcre2.compiled_width) {
        .@"8" => pcre2.c.pcre2_code_free_8(block),
        .@"16" => pcre2.c.pcre2_code_free_16(block),
        .@"32" => pcre2.c.pcre2_code_free_32(block),
    }
}

test "the POSIX wrapper compiles, matches and reports its own codes" {
    nativeReady();
    if (pcre2.Posix.availability != .linked) {
        // 16/32-bit builds lack POSIX declarations; assert availability instead of skipping.
        try std.testing.expectEqual(
            @as(pcre2.Posix.Availability, .unavailable),
            pcre2.Posix.availability,
        );
        return;
    }

    // Linked and runtime routes expose the same wrapper; `routed` identifies the route.

    // The wrapper takes a NUL-terminated subject.
    const subject: [:0]const u8 = "xabc";
    var matches: [4]pcre2.Posix.Match = undefined;

    // `compile` returns an owned value; `exec` borrows it until `deinit`.
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

    // A missing closing parenthesis maps to `REG_EPAREN`, not fallback `REG_BADPAT`.
    switch (try pcre2.Posix.compile("a(b", 0)) {
        .compiled => |compiled_regex| {
            // Release the owned value before returning from unexpected success.
            var to_release = compiled_regex;
            to_release.deinit();
            return error.FixtureMismatch;
        },
        .rejected => |rejection| {
            try std.testing.expectEqual(@as(c_int, pcre2.Posix.code.eparen), rejection.code);
        },
    }
    // An unmatched closing parenthesis also maps to `REG_EPAREN`.
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
    // Unused output slots are set to the POSIX `unset` marker.
    try std.testing.expectEqual(pcre2.Posix.unset, matches[3].rm_so);
    try std.testing.expectEqual(pcre2.Posix.unset, matches[3].rm_eo);

    // `REG_STARTEND` needs pointer-encoded bounds unsupported by this slice API.
    try std.testing.expectError(
        error.UnsupportedOption,
        pcre2.Posix.exec(&compiled, "abc", &matches, pcre2.Posix.option.startend),
    );
}

/// Converts inline ASCII literals to a static array of selected-width code units.
/// The array outlives tests; no runtime widening or cleanup is needed.
fn widenLiteral(comptime ascii: []const u8) []const Unit {
    if (ascii.len == 0) return &.{};
    const widened = comptime blk: {
        var buf: [ascii.len]Unit = undefined;
        for (ascii, 0..) |byte, i| buf[i] = byte;
        break :blk buf;
    };
    return &widened;
}
