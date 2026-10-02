//! Consumes the `pcre2` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `b.dependency` in
//! `build.zig`, and `@import("pcre2")` here. No path reaches into the library's
//! own tree, and nothing is imported from the library's tests or fixtures, so
//! if this builds and produces the answers below, the module contract is real.
//!
//! The task is a structured-log reader, which is the shape most callers have:
//! one anchored pattern with named groups, an optional group that sometimes
//! does not take part, and a result assembled into a buffer the caller owns.
//! Every expected value is worked out by hand from the subject strings, so a
//! mismatch is a real fault rather than a restatement of what the library just
//! did. Any mismatch returns an error, so the process exits non-zero.

const std = @import("std");
const pcre2 = @import("pcre2");

/// `level[id] message`, with the bracketed id optional and the rest of the
/// line taken verbatim. Anchored at both ends, so a trailing newline or a
/// prefix is a non-match rather than a partial one.
const pattern = "^(?<level>[A-Z]+)(?:\\[(?<id>[0-9]+)\\])? (?<message>.*)$";

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
                "the consumer's pattern did not compile: error {d} at offset {d}: {s}\n",
                .{ rejection.code, rejection.offset, rejection.text.slice() },
            );
            return error.PatternRejected;
        },
    };
}

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // Printed, never asserted: which release this binary linked against is a
    // provenance fact. The buffer is this function's, and what comes back is a
    // slice of it, so a consumer that copied that shape gets a string it is
    // still holding at the next line without allocating anything. 64 bytes is
    // past the 24 code units every release so far has needed
    // (`doc/pcre2.txt:1468-1469`); a library that wanted more reports it
    // rather than having this print a shortened version.
    var version_buffer: [64]u8 = undefined;
    const version = pcre2.version(&version_buffer) catch |err| {
        try w.print("the linked library did not report a version: {s}\n", .{@errorName(err)});
        try w.flush();
        return error.VersionNotReported;
    };
    try w.print("pcre2 consumer, linked against {s}\n", .{version});

    var regex = try compilePattern();
    defer regex.deinit();
    try w.print("pattern {s}\n", .{pattern});
    try w.print("{d} capturing groups, {d} names\n", .{ regex.captureCount(), regex.nameCount() });

    // The names are reached through `numberForName` rather than written down,
    // so a pattern whose numbering changed would show up here instead of
    // quietly reading the wrong group.
    const level_group = regex.numberForName("level") orelse return error.NameMissing;
    const id_group = regex.numberForName("id") orelse return error.NameMissing;
    const message_group = regex.numberForName("message") orelse return error.NameMissing;

    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();
    var context = try pcre2.MatchContext.init();
    defer context.deinit();
    context.setMatchLimit(1_000_000);

    var out: [128]u8 = undefined;

    for ([_]Line{ with_id, without_id }) |line| {
        switch (try regex.match(line.subject, 0, .{}, &match_data, &context)) {
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

        try expect(w, line, "level", try match_data.groupRange(level_group), .{ .text = level, .start = line.level.start, .end = line.level.end });
        try expect(w, line, "message", try match_data.groupRange(message_group), .{ .text = message, .start = line.message.start, .end = line.message.end });

        // The optional group. A line with no bracketed id leaves it unset, and
        // that is a different answer from an empty one, so it is checked as
        // "no range at all" rather than as a zero-length slice.
        const id_range = try match_data.groupRange(id_group);
        if (line.id) |want| {
            const id_text = id orelse return error.IdExpectedButUnset;
            if (!std.mem.eql(u8, id_text, want.text)) return error.IdTextMismatch;
            if (id_range == null) return error.IdExpectedButUnset;
            try expect(w, line, "id", id_range, .{
                .text = id_text,
                .start = want.start,
                .end = want.end,
            });
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

fn expect(
    w: *std.Io.Writer,
    line: Line,
    what: []const u8,
    got: ?pcre2.Group,
    want: Capture,
) !void {
    const range = got orelse {
        try w.print("{s}: {s} was expected to take part in the match\n", .{ line.subject, what });
        try w.flush();
        return error.GroupExpectedButUnset;
    };
    if (range.start != want.start or range.end != want.end) {
        try w.print("{s}: {s} expected bytes {d}..{d}, PCRE2 reported {d}..{d}\n", .{
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
    if (!std.mem.eql(u8, want.text, line.subject[range.start..range.end])) {
        try w.print("{s}: {s} captured the wrong bytes\n", .{ line.subject, what });
        try w.flush();
        return error.TextMismatch;
    }
}

/// Assembles `level/id/message` into the caller's buffer.
///
/// The buffer belongs to the caller and nothing is allocated, which is the
/// point of borrowing captures: the three pieces are already windows on the
/// caller's own subject, so the only copy here is the one the caller asked
/// for. The length is checked before anything is written, so a short buffer is
/// an error rather than a truncated result.
fn render(
    out: []u8,
    level: []const u8,
    id: ?[]const u8,
    message: []const u8,
) ![]const u8 {
    const id_text = id orelse "-";
    const needed = level.len + 1 + id_text.len + 1 + message.len;
    if (out.len < needed) return error.BufferTooSmall;

    var at: usize = 0;
    @memcpy(out[at..][0..level.len], level);
    at += level.len;
    out[at] = '/';
    at += 1;
    @memcpy(out[at..][0..id_text.len], id_text);
    at += id_text.len;
    out[at] = '/';
    at += 1;
    @memcpy(out[at..][0..message.len], message);
    at += message.len;
    return out[0..at];
}
