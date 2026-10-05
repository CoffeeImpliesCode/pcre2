//! A runnable, deterministic demonstration of the facade. `zig build smoke`
//! runs this.
//!
//! One anchored pattern with three named groups is matched against one literal
//! subject, and every capture is compared with a hand-worked code-unit offset:
//!
//! ```text
//! offset 0         1         2         3         4
//!        0123456789012345678901234567890123456789012345
//!        https://example.org:8443
//! ```
//!
//! The whole match is units 0..24, `scheme` is `https` at 0..5, `host` is
//! `example.org` at 8..19 and `port` is `8443` at 20..24. Nothing here is
//! derived from the library's own answer, so a change in the output is a change
//! in PCRE2 or in the binding rather than a restatement of either. The offsets
//! are code-unit offsets, which is what a 16- or 32-bit library reports too, so
//! the same numbers are the answer at every width.
//!
//! The pattern and the subject are widened into the compiled width's code units
//! at compile time, because the pattern text is ASCII and a byte literal is not
//! a `[]const u16`. The names and texts the capture table carries are widened
//! at run time instead, into buffers `main` owns, because the loop over that
//! table is a run-time loop and a comptime widening has nothing to read. The
//! units are the same either way.
//!
//! The last thing it demonstrates is the lifetime. One `MatchData` is reused for
//! both subjects, and after the second attempt, which does not match, no capture
//! is readable. PCRE2 leaves the first attempt's offsets in the vector and those
//! offsets describe the first subject, so handing them back next to the second
//! subject would be indexing one string with another's offsets.
//!
//! Each offset is compared with an ordinary comparison and a mismatch returns an
//! error, so the process exits non-zero. A debug assertion would be compiled out
//! of a release build, which is not a check.
//!
//! About JIT: this fork builds with `SUPPORT_JIT` off, so every number printed
//! here is the interpreted answer. Nothing about the JIT path is exercised.

const std = @import("std");
const pcre2 = @import("pcre2");

/// The code unit this build compiled.
const Unit = pcre2.compiled_unit;

/// Anchored at both ends, so the two `^` and `$` and the group layout are all
/// part of what is being demonstrated. `[^/:]+` cannot run past the authority,
/// and `{1,5}` cannot swallow the digits of a longer port.
const pattern_text = "^(?<scheme>[a-z][a-z0-9+.-]*)://(?<host>[^/:]+):(?<port>[0-9]{1,5})$";
const subject_text = "https://example.org:8443";

/// ASCII text as this width's code units.
///
/// A comptime array rather than a run-time widening, so the slices are
/// container-level constants that outlive `main` and need no cleanup. A byte
/// above what the code unit can hold is a compile error here rather than a
/// truncation at run time, because every string in this file is ASCII and a
/// silent truncation would produce a pattern that means something else.
fn wide(comptime ascii: []const u8) []const Unit {
    if (ascii.len == 0) return &.{};
    const widened = comptime blk: {
        var buf: [ascii.len]Unit = undefined;
        for (ascii, 0..) |byte, i| {
            if (byte > std.math.maxInt(Unit))
                @compileError("smoke.zig: this example's text is ASCII, so it " ++
                    "cannot be widened to this width's code units");
            buf[i] = byte;
        }
        break :blk buf;
    };
    return &widened;
}

/// ASCII text as this width's code units, widened at run time.
///
/// `wide` above serves the text this file writes out, which is known at compile
/// time. The capture table's names and texts come out of a run-time loop, so
/// they are widened here instead, into storage the caller owns. The answer is
/// the same; only the moment it is computed differs.
///
/// Neither refusal below can fire for this file's own table: every string in
/// it is ASCII, and the buffers `main` hands over are past the longest name and
/// the longest capture in it.
fn widen(ascii: []const u8, out: []Unit) error{ExampleTextNotWidened}![]const Unit {
    if (out.len < ascii.len) return error.ExampleTextNotWidened;
    for (ascii, 0..) |byte, i| {
        if (byte > std.math.maxInt(Unit)) return error.ExampleTextNotWidened;
        out[i] = byte;
    }
    return out[0..ascii.len];
}

const pattern = wide(pattern_text);
const subject = wide(subject_text);

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
    .{ .number = 0, .text = subject_text, .start = 0, .end = 24 },
    .{ .name = "scheme", .text = "https", .start = 0, .end = 5 },
    .{ .name = "host", .text = "example.org", .start = 8, .end = 19 },
    .{ .name = "port", .text = "8443", .start = 20, .end = 24 },
};

/// What this program was asked to do.
const Mode = enum { run, pre_load };

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args;
    _ = &args;

    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // In a runtime-loading build every call below goes through a table that this
    // one call fills. In a linked build the branch is not analysed at all, and
    // nothing is loaded, which is the ordinary configuration.
    if (comptime pcre2.runtime_loaded) {
        try pcre2.load(.{ .path = try providerRequest(init) });
    }

    try w.print("pcre2 smoke, {s} library, {d}-bit code units\n", .{
        @tagName(if (pcre2.runtime_loaded) .loaded else .linked),
        switch (pcre2.compiled_width) {
            .@"8" => 8,
            .@"16" => 16,
            .@"32" => 32,
        },
    });

    // Printed, never asserted. Which release this binary was linked against is
    // a provenance fact, and a smoke run should report it rather than fail when
    // the pin moves. The buffer belongs to this function and the answer is a
    // window on it, which is the point: the string is still here at the next
    // line because both are this frame's, not a callee's. 64 units is well past
    // the 24 code units every release so far has needed
    // (`doc/pcre2.txt:1468-1469`), and a library that asked for more would say
    // so rather than have this print a truncated or invented version.
    var version_buffer: [64]Unit = undefined;
    const version = pcre2.version(&version_buffer) catch |err| {
        try w.print("the library did not report a version: {s}\n", .{@errorName(err)});
        try w.flush();
        return error.VersionNotReported;
    };
    var version_bytes: [64]u8 = undefined;
    for (version, 0..) |unit, index| version_bytes[index] = @intCast(unit);
    try w.print("pcre2 smoke, {s} against {s}\n", .{
        if (pcre2.runtime_loaded) "loaded" else "linked",
        version_bytes[0..version.len],
    });
    try w.print("pattern  {s}\n", .{pattern_text});
    try w.print("subject  {s} ({d} code units)\n", .{ subject_text, subject.len });

    var regex = switch (try pcre2.Regex.compile(pattern, .{})) {
        .compiled => |compiled| compiled,
        .rejected => |rejection| {
            try w.print("the demonstration pattern did not compile: error {d} at offset {d}\n", .{
                rejection.code,
                rejection.offset,
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
        }
    }
    try w.print("match starts at code unit {d}\n", .{match_data.startOffset()});

    // The table's names and texts are run-time values, so they are widened into
    // storage this function owns rather than through the comptime `wide` above.
    // Two buffers rather than one: a name and a text are both wanted in the
    // same pass, and a capture must never be compared beside a buffer something
    // else has just rewritten. 32 units is past the longest name ("scheme",
    // six) and past the longest capture, which is the whole 24-unit subject.
    var name_units: [32]Unit = undefined;
    var text_units: [32]Unit = undefined;
    // A third buffer for the failure line below. It has to be a different one
    // from `text_units`, because the comparison that decides to print it is
    // the one that fills that one with the expected text.
    var captured_bytes: [32]u8 = undefined;

    for (expected) |want| {
        const group = blk: {
            if (want.number) |number| break :blk number;
            const name = try widen(want.name.?, &name_units);
            const number = regex.numberForName(name) orelse {
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
            try w.print("group {d} ({s}): expected units {d}..{d}, PCRE2 reported {d}..{d}\n", .{
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
        if (!std.mem.eql(Unit, captured, try widen(want.text, &text_units))) {
            // The captured code units are what the line has to name, and `{s}`
            // writes a code unit's machine representation rather than the
            // character it stands for, so they are narrowed to bytes first --
            // the same narrowing the version string above gets. A capture that
            // is not a byte has no spelling on one line, and this is already a
            // failure.
            if (captured.len > captured_bytes.len) return error.ExampleTextMismatch;
            for (captured, 0..) |unit, index| {
                if (unit > std.math.maxInt(u8)) return error.ExampleTextMismatch;
                captured_bytes[index] = @intCast(unit);
            }
            try w.print("group {d} ({s}): expected {s}, PCRE2 captured {s}\n", .{
                group,
                want.name orelse "whole match",
                want.text,
                captured_bytes[0..captured.len],
            });
            try w.flush();
            return error.ExampleTextMismatch;
        }
        try w.print("group {d} {s}: units {d}..{d} = {s}\n", .{
            group,
            want.name orelse "(whole match)",
            range.start,
            range.end,
            want.text,
        });
    }

    // A subject the pattern must refuse, so the demonstration shows the
    // negative answer and not only the positive one. "https://example.org" has
    // no ":port" and `^...$` will not let the group go missing.
    switch (try regex.match(wide("https://example.org"), 0, .{}, &match_data, &context)) {
        .no_match => {},
        else => {
            try w.print("a subject without a port was accepted\n", .{});
            try w.flush();
            return error.ExampleUnexpectedMatch;
        }
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
        "smoke: this is a runtime-loading build. Pass --provider <path>, or " ++
            "export PCRE2_TEST_PROVIDER with a shared object that exports " ++
            "every entry point this build's translated pcre2.h declares: all " ++
            "three code-unit widths, not only the one this build is about. A " ++
            "single-width upstream libpcre2-8 is not one. Nothing is loaded by " ++
            "default and no other file is tried.\n",
        .{},
    );
    return error.NoProviderConfigured;
}
