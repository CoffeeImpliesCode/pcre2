//! Consumes the `pcre2` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `b.dependency` in
//! `build.zig`, and `@import("pcre2")` here. No path reaches into the library's
//! own tree, and nothing is imported from the library's tests or fixtures, so
//! if this builds and produces the answers below, the module contract is real.
//!
//! The task is a structured-log reader, which is the shape most callers have:
//! one anchored pattern with named groups, an optional group that sometimes does
//! not take part, and a result assembled into a buffer the caller owns. Every
//! expected value is worked out by hand from the subject strings, so a mismatch
//! is a real fault rather than a restatement of what the library just did. Any
//! mismatch returns an error, so the process exits non-zero.
//!
//! ## Every width, and both linkages
//!
//! The pattern is widened into the compiled width's code units at compile time
//! and each line's text at run time, into buffers this program owns, so the
//! same hand-worked offsets are the answer at 8, 16 and 32 bits: the offsets
//! below are code-unit offsets, which is what a 16- or 32-bit library reports
//! as well, and every comparison is made in the width's code units rather than
//! in bytes.
//!
//! The same source builds against a linked package and against a
//! runtime-loaded one. `pcre2.runtime_loaded` is a comptime constant, so the
//! difference is one branch and no duplicated program: in the runtime-loaded
//! build the provider is named on the command line (`--provider <path>`) or in
//! `PCRE2_TEST_PROVIDER`, loaded once, and the same published answers follow.
//! Nothing is loaded by default and no other file is tried.

const std = @import("std");
const pcre2 = @import("pcre2");

/// The code unit this build compiled.
const Unit = pcre2.compiled_unit;

/// ASCII text as this width's code units.
///
/// A comptime array rather than a run-time widening, so the slices are
/// container-level constants that outlive `main` and need no cleanup. This
/// consumer's own text is ASCII, and a byte that the width's code unit could not
/// hold would be a compile error rather than a pattern that means something
/// else.
fn wide(comptime ascii: []const u8) []const Unit {
    if (ascii.len == 0) return &.{};
    const widened = comptime blk: {
        var buf: [ascii.len]Unit = undefined;
        for (ascii, 0..) |byte, i| {
            if (byte > std.math.maxInt(Unit))
                @compileError("consumer: this consumer's text is ASCII, so it " ++
                    "cannot be widened to this width's code units");
            buf[i] = byte;
        }
        break :blk buf;
    };
    return &widened;
}

/// ASCII text as this width's code units, widened at run time.
///
/// `wide` above serves the pattern this file writes out, which is known at
/// compile time. The two lines' own text comes out of a run-time loop, so it
/// is widened here into a buffer the caller owns. Neither refusal below can
/// fire for this consumer's own table: every line in it is ASCII, and the
/// buffers `main` hands over are past its longest line.
fn widen(ascii: []const u8, out: []Unit) error{TextNotWidened}![]const Unit {
    if (out.len < ascii.len) return error.TextNotWidened;
    for (ascii, 0..) |byte, i| {
        if (byte > std.math.maxInt(Unit)) return error.TextNotWidened;
        out[i] = byte;
    }
    return out[0..ascii.len];
}

/// `level[id] message`, with the bracketed id optional and the rest of the
/// line taken verbatim. Anchored at both ends, so a trailing newline or a
/// prefix is a non-match rather than a partial one.
const pattern = wide("^(?<level>[A-Z]+)(?:\\[(?<id>[0-9]+)\\])? (?<message>.*)$");

/// One line, one expected result. The offsets are counted from the subject
/// string above and are not read back out of the library.
const Line = struct {
    subject: []const u8,
    /// `level/id/message`, with `-` where the optional id did not take part.
    rendered: []const u8,
    level: Capture,
    id: ?Capture,
    message: Capture,
};

const Capture = struct {
    text: []const u8,
    start: usize,
    end: usize,
};

// "ERROR[4171] disk full on /dev/sda1", 34 bytes:
//   0..5  ERROR
//   5     [
//   6..10 4171
//   10    ]
//   11    space
//   12..34 "disk full on /dev/sda1", which is 4+1+4+1+2+1+9 = 22 bytes.
const with_id: Line = .{
    .subject = "ERROR[4171] disk full on /dev/sda1",
    .rendered = "ERROR/4171/disk full on /dev/sda1",
    .level = .{ .text = "ERROR", .start = 0, .end = 5 },
    .id = Capture{ .text = "4171", .start = 6, .end = 10 },
    .message = .{ .text = "disk full on /dev/sda1", .start = 12, .end = 34 },
};

// "WARN disk nearly full", 21 bytes:
//   0..4  WARN
//   4     space
//   5..21 "disk nearly full", which is 4+1+6+1+4 = 16 bytes.
// The optional id group does not take part, so its offset vector pair stays
// PCRE2_UNSET and the facade reports no range for it.
const without_id: Line = .{
    .subject = "WARN disk nearly full",
    .rendered = "WARN/-/disk nearly full",
    .level = .{ .text = "WARN", .start = 0, .end = 4 },
    .id = null,
    .message = .{ .text = "disk nearly full", .start = 5, .end = 21 },
};

/// The compiled pattern, one instance for both lines: a caller that reads a
/// stream compiles once.
fn compilePattern() !pcre2.Regex {
    return switch (try pcre2.Regex.compile(pattern, .{})) {
        .compiled => |compiled| compiled,
        .rejected => |rejection| {
            std.debug.print(
                "the consumer's pattern did not compile: error {d} at offset {d}\n",
                .{ rejection.code, rejection.offset },
            );
            return error.PatternRejected;
        },
    };
}

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build every call below goes through a table that this
    // one call fills. In a linked build the branch is not analysed at all and
    // nothing is loaded.
    if (comptime pcre2.runtime_loaded) {
        try pcre2.load(.{ .path = try providerRequest(init) });
    }

    try w.print("pcre2 consumer, {s} library, {d}-bit code units\n", .{
        @tagName(if (pcre2.runtime_loaded) .loaded else .linked),
        switch (pcre2.compiled_width) {
            .@"8" => 8,
            .@"16" => 16,
            .@"32" => 32,
        },
    });

    // Printed, never asserted: which release this binary linked against is a
    // provenance fact. The buffer is this function's, and what comes back is a
    // slice of it, so a consumer that copied that shape gets a string it is
    // still holding at the next line without allocating anything. 64 units is
    // past the 24 code units every release so far has needed
    // (`doc/pcre2.txt:1468-1469`); a library that wanted more reports it
    // rather than having this print a shortened version.
    var version_buffer: [64]Unit = undefined;
    const version = pcre2.version(&version_buffer) catch |err| {
        try w.print("the library did not report a version: {s}\n", .{@errorName(err)});
        try w.flush();
        return error.VersionNotReported;
    };
    // `version` is a slice of this build's code units, and `{s}` writes the
    // bytes of that memory rather than the characters the code units stand
    // for: at 16 and 32 bits the line would be the version string with a NUL
    // after every character. Narrowed to bytes first, the way `smoke.zig`
    // does it, so all three widths print the same line.
    var version_bytes: [version_buffer.len]u8 = undefined;
    for (version, 0..) |unit, index| version_bytes[index] = @intCast(unit);
    try w.print("pcre2 consumer, linked against {s}\n", .{version_bytes[0..version.len]});

    var regex = try compilePattern();
    defer regex.deinit();
    try w.print("{d} capturing groups, {d} names\n", .{ regex.captureCount(), regex.nameCount() });

    // The names are reached through `numberForName` rather than written down,
    // so a pattern whose numbering changed would show up here instead of
    // quietly reading the wrong group.
    const level_group = regex.numberForName(wide("level")) orelse return error.NameMissing;
    const id_group = regex.numberForName(wide("id")) orelse return error.NameMissing;
    const message_group = regex.numberForName(wide("message")) orelse return error.NameMissing;

    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();
    var context = try pcre2.MatchContext.init();
    defer context.deinit();
    context.setMatchLimit(1_000_000);

    // `out` holds the assembled line; the other two hold this line's text and
    // the hand-worked expectations, which are run-time values. 64 units is past
    // the longest line below (34 code units) and past its longest expectation.
    var out: [128]u8 = undefined;
    var subject_units: [64]Unit = undefined;
    var expect_units: [64]Unit = undefined;

    for ([_]Line{ with_id, without_id }) |line| {
        const subject = try widen(line.subject, &subject_units);
        switch (try regex.match(subject, 0, .{}, &match_data, &context)) {
            .matched => {},
            .no_match => {
                try w.print("{s}: did not match\n", .{line.subject});
                try w.flush();
                return error.SubjectDidNotMatch;
            },
            else => {
                try w.print("{s}: the match failed rather than answering\n", .{line.subject});
                try w.flush();
                return error.MatchFailed;
            },
        }

        const level = (try match_data.group(level_group)) orelse return error.LevelUnset;
        const message = (try match_data.group(message_group)) orelse return error.MessageUnset;
        const id = try match_data.group(id_group);

        try expect(w, line, "level", try match_data.groupRange(level_group), level, line.level, &expect_units);
        try expect(w, line, "message", try match_data.groupRange(message_group), message, line.message, &expect_units);

        // The optional group. A line with no bracketed id leaves it unset, and
        // that is a different answer from an empty one, so it is checked as
        // "no range at all" rather than as a zero-length slice.
        const id_range = try match_data.groupRange(id_group);
        if (line.id) |want| {
            const id_text = id orelse return error.IdExpectedButUnset;
            if (id_range == null) return error.IdExpectedButUnset;
            // The id's own text is checked inside `expect`, in this width's
            // code units like every other capture here.
            try expect(w, line, "id", id_range, id_text, .{
                .text = want.text,
                .start = want.start,
                .end = want.end,
            }, &expect_units);
        } else if (id_range != null) {
            try w.print("{s}: id was expected to be unset\n", .{line.subject});
            try w.flush();
            return error.IdExpectedToBeUnset;
        }

        const rendered = try render(&out, level, id, message);
        if (!std.mem.eql(u8, line.rendered, rendered)) {
            try w.print("{s}: expected {s}, assembled {s}\n", .{ line.subject, line.rendered, rendered });
            try w.flush();
            return error.RenderedMismatch;
        }
        try w.print("{s} -> {s}\n", .{ line.subject, rendered });
    }

    try w.print("every line matched with the offsets worked out by hand\n", .{});
    try w.flush();
}

/// Checks one group's reported range against the offsets this file worked out
/// by hand, and its capture against the text it worked out by hand.
///
/// The capture arrives in this width's code units, so the expectation is
/// widened into `scratch` the same way. Comparing the capture rather than the
/// subject's own bytes is what makes this a statement about the library: at
/// 16 and 32 bits the reported offsets are code-unit offsets, and the subject
/// is a different string from the one those offsets count into. `scratch` is
/// reused by the caller between calls and nothing here keeps it.
fn expect(
    w: *std.Io.Writer,
    line: Line,
    what: []const u8,
    got: ?pcre2.Group,
    captured: ?[]const Unit,
    want: Capture,
    scratch: []Unit,
) !void {
    const range = got orelse {
        try w.print("{s}: {s} was expected to take part in the match\n", .{ line.subject, what });
        try w.flush();
        return error.GroupExpectedButUnset;
    };
    if (range.start != want.start or range.end != want.end) {
        try w.print("{s}: {s} expected units {d}..{d}, PCRE2 reported {d}..{d}\n", .{
            line.subject,
            what,
            want.start,
            want.end,
            range.start,
            range.end,
        });
        try w.flush();
        return error.OffsetMismatch;
    }
    const units = captured orelse {
        try w.print("{s}: {s} was expected to take part in the match\n", .{ line.subject, what });
        try w.flush();
        return error.GroupExpectedButUnset;
    };
    if (!std.mem.eql(Unit, units, try widen(want.text, scratch))) {
        try w.print("{s}: {s} captured the wrong code units\n", .{ line.subject, what });
        try w.flush();
        return error.TextMismatch;
    }
}

/// Assembles `level/id/message` into the caller's buffer.
///
/// The buffer belongs to the caller and nothing is allocated, which is the point
/// of borrowing captures: the three pieces are already windows on the caller's
/// own subject, so the only copy here is the one the caller asked for. The
/// length is checked before anything is written, so a short buffer is an error
/// rather than a truncated result.
fn render(
    out: []u8,
    level: []const Unit,
    id: ?[]const Unit,
    message: []const Unit,
) ![]const u8 {
    const id_text: []const Unit = if (id) |text| text else wide("-");
    const needed = level.len + 1 + id_text.len + 1 + message.len;
    if (out.len < needed) return error.BufferTooSmall;

    var at: usize = 0;
    for (level) |unit| at += try writeByte(out, at, unit);
    out[at] = '/';
    at += 1;
    for (id_text) |unit| at += try writeByte(out, at, unit);
    out[at] = '/';
    at += 1;
    for (message) |unit| at += try writeByte(out, at, unit);
    return out[0..at];
}

/// Writes one code unit into `out` at `at`, as the byte it stands for.
///
/// Every character in this consumer's subjects is ASCII, so a code unit that is
/// not a byte cannot be one of them and is refused rather than truncated. The
/// result is written as bytes so it can be printed and compared against the
/// fixture without a cast that would discard this width's alignment and
/// element size.
fn writeByte(out: []u8, at: usize, unit: Unit) error{NonAsciiAssembly}!usize {
    if (unit > std.math.maxInt(u8)) return error.NonAsciiAssembly;
    out[at] = @intCast(unit);
    return 1;
}

/// The provider this run should load, from `--provider <path>` or from
/// `PCRE2_TEST_PROVIDER`.
///
/// Both are explicit. Nothing here looks in a default location, and a build that
/// was not told which file to load says so rather than loading something else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get("PCRE2_TEST_PROVIDER") orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "consumer: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export PCRE2_TEST_PROVIDER with a shared object that exports " ++
            "every entry point this build's translated pcre2.h declares: all " ++
            "three code-unit widths, not only the one this build is about. A " ++
            "single-width upstream libpcre2-8 is not one. Nothing is loaded by " ++
            "default and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}
