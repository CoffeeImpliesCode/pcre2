//! A runnable, deterministic demonstration of the facade. `zig build smoke`
//! runs this.
//!
//! One anchored pattern with three named groups is matched against one literal
//! subject, and every capture is compared with a hand-worked byte offset:
//!
//! ```text
//! offset 0         1         2         3         4
//!        0123456789012345678901234567890123456789012345
//!        https://example.org:8443
//! ```
//!
//! The whole match is bytes 0..24, `scheme` is `https` at 0..5, `host` is
//! `example.org` at 8..19 and `port` is `8443` at 20..24. Nothing here is
//! derived from the library's own answer, so a change in the output is a
//! change in PCRE2 or in the binding rather than a restatement of either.
//!
//! The last thing it demonstrates is the lifetime. One `MatchData` is reused
//! for both subjects, and after the second attempt, which does not match, no
//! capture is readable. PCRE2 leaves the first attempt's offsets in the vector
//! and those offsets describe the first subject, so handing them back next to
//! the second subject would be indexing one string with another's offsets.
//!
//! Each offset is compared with an ordinary comparison and a mismatch returns
//! an error, so the process exits non-zero. A debug assertion would be
//! compiled out of a release build, which is not a check.
//!
//! About JIT: this fork builds with `SUPPORT_JIT` off, so every number printed
//! here is the interpreted answer. Nothing about the JIT path is exercised.

const std = @import("std");
const pcre2 = @import("pcre2");

/// Anchored at both ends, so the two `^` and `$` and the group layout are all
/// part of what is being demonstrated. `[^/:]+` cannot run past the authority,
/// and `{1,5}` cannot swallow the digits of a longer port.
const pattern = "^(?<scheme>[a-z][a-z0-9+.-]*)://(?<host>[^/:]+):(?<port>[0-9]{1,5})$";
const subject = "https://example.org:8443";

const expectation = struct {
    /// The group number, or null when the group is reached by name so that
    /// `Regex.numberForName` is part of what is demonstrated.
    number: ?u32 = null,
    name: ?[]const u8 = null,
    text: []const u8,
    start: usize,
    end: usize,
};

const expected = [_]expectation{
    .{ .number = 0, .text = subject, .start = 0, .end = 24 },
    .{ .name = "scheme", .text = "https", .start = 0, .end = 5 },
    .{ .name = "host", .text = "example.org", .start = 8, .end = 19 },
    .{ .name = "port", .text = "8443", .start = 20, .end = 24 },
};

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // Printed, never asserted. Which release this binary was linked against is
    // a provenance fact, and a smoke run should report it rather than fail when
    // the pin moves. The buffer belongs to this function and the answer is a
    // window on it, which is the point: the string is still here at the next
    // line because both are this frame's, not a callee's. 64 bytes is well
    // past the 24 code units every release so far has needed
    // (`doc/pcre2.txt:1468-1469`), and a library that asked for more would say
    // so rather than have this print a truncated or invented version.
    var version_buffer: [64]u8 = undefined;
    const version = pcre2.version(&version_buffer) catch |err| {
        try w.print("the linked library did not report a version: {s}\n", .{@errorName(err)});
        try w.flush();
        return error.VersionNotReported;
    };
    try w.print("pcre2 smoke, linked against {s}\n", .{version});
    try w.print("pattern  {s}\n", .{pattern});
    try w.print("subject  {s} ({d} bytes)\n", .{ subject, subject.len });

    var regex = switch (try pcre2.Regex.compile(pattern, .{})) {
        .compiled => |compiled| compiled,
        .rejected => |rejection| {
            try w.print("the demonstration pattern did not compile: error {d} at offset {d}: {s}\n", .{
                rejection.code,
                rejection.offset,
                rejection.text.slice(),
            });
            try w.flush();
            return error.ExamplePatternRejected;
        },
    };
    defer regex.deinit();
    try w.print("compiled, {d} capturing groups, {d} names\n", .{
        regex.captureCount(),
        regex.nameCount(),
    });

    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();

    var context = try pcre2.MatchContext.init();
    defer context.deinit();
    // A ceiling a caller who chose the subject would want. It is set so the
    // demonstration runs through the same context a real caller would.
    context.setMatchLimit(1_000_000);

    switch (try regex.match(subject, 0, .{}, &match_data, &context)) {
        .matched => {},
        else => {
            try w.print("the demonstration subject did not match\n", .{});
            try w.flush();
            return error.ExampleSubjectDidNotMatch;
        },
    }
    try w.print("match starts at byte {d}\n", .{match_data.startOffset()});

    for (expected) |want| {
        const group = blk: {
            if (want.number) |number| break :blk number;
            const number = regex.numberForName(want.name.?) orelse {
                try w.print("the pattern declares no group named {s}\n", .{want.name.?});
                try w.flush();
                return error.ExampleNameMissing;
            };
            break :blk number;
        };

        const range = (try match_data.groupRange(group)) orelse {
            try w.print("group {d} ({s}) did not take part in the match\n", .{ group, want.name orelse "whole match" });
            try w.flush();
            return error.ExampleGroupUnset;
        };
        if (range.start != want.start or range.end != want.end) {
            try w.print("group {d} ({s}): expected bytes {d}..{d}, PCRE2 reported {d}..{d}\n", .{
                group,
                want.name orelse "whole match",
                want.start,
                want.end,
                range.start,
                range.end,
            });
            try w.flush();
            return error.ExampleOffsetMismatch;
        }

        const captured = (try match_data.group(group)) orelse return error.ExampleGroupUnset;
        if (!std.mem.eql(u8, captured, want.text)) {
            try w.print("group {d} ({s}): expected {s}, PCRE2 captured {s}\n", .{
                group,
                want.name orelse "whole match",
                want.text,
                captured,
            });
            try w.flush();
            return error.ExampleTextMismatch;
        }
        try w.print("group {d} {s}: bytes {d}..{d} = {s}\n", .{
            group,
            want.name orelse "(whole match)",
            range.start,
            range.end,
            captured,
        });
    }

    // A subject the pattern must refuse, so the demonstration shows the
    // negative answer and not only the positive one. "https://example.org" has
    // no ":port" and `^...$` will not let the group go missing.
    switch (try regex.match("https://example.org", 0, .{}, &match_data, &context)) {
        .no_match => {},
        else => {
            try w.print("a subject without a port was accepted\n", .{});
            try w.flush();
            return error.ExampleUnexpectedMatch;
        },
    }

    try w.print("subject without a port: no match, as expected\n", .{});

    // What the block still holds after an attempt that did not match. It is
    // the same block that answered above, and the offsets in it are still the
    // ones PCRE2 wrote for the subject above; the facade reports that there is
    // nothing to read rather than returning a window on this subject.
    if ((try match_data.groupRange(0)) != null or (try match_data.group(0)) != null) {
        try w.print("a capture was readable after an attempt that did not match\n", .{});
        try w.flush();
        return error.ExampleStaleCapture;
    }
    try w.print("and no capture from the failed attempt is readable\n", .{});

    try w.flush();
}
