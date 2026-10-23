//! Deterministic example of typed PCRE2 captures and match-data ownership.
//! Builds an ASCII URL pattern for the selected code-unit width.
//! Runtime builds require an explicit provider; this JIT-disabled build uses the interpreter.

const std = @import("std");
const pcre2 = @import("pcre2");

/// The code unit this build compiled.
const Unit = pcre2.compiled_unit;

/// Anchored URL pattern with named scheme, host, and port captures.
const pattern_text = "^(?<scheme>[a-z][a-z0-9+.-]*)://(?<host>[^/:]+):(?<port>[0-9]{1,5})$";
const subject_text = "https://example.org:8443";

/// Converts compile-time ASCII text to the selected code-unit type.
/// Returned slices are static and outlive `main`.
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

/// Converts runtime ASCII text into caller-owned code units.
/// Returns `ExampleTextNotWidened` when output capacity is short.
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
    /// Capture group number, or a name to exercise lookup.
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

    // Runtime builds load an explicit provider; linked builds need no loader call.
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

    // Report the library version without pinning this example to a release.
    // The returned slice must point into this caller-owned buffer.
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
    // Bound matching work for the caller-chosen subject.
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

    // Separate buffers hold the name and capture text during each comparison.
    var name_units: [32]Unit = undefined;
    var text_units: [32]Unit = undefined;
    // Dedicated output buffer, since `text_units` may be rewritten.
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
            // Narrow captured code units only after verifying they fit in one byte.
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

    // The URL has no port, so the anchored pattern must reject it.
    switch (try regex.match(wide("https://example.org"), 0, .{}, &match_data, &context)) {
        .no_match => {},
        else => {
            try w.print("a subject without a port was accepted\n", .{});
            try w.flush();
            return error.ExampleUnexpectedMatch;
        }
    }

    try w.print("subject without a port: no match, as expected\n", .{});

    // Failed attempts must not expose offsets from a prior subject.
    if ((try match_data.groupRange(0)) != null or (try match_data.group(0)) != null) {
        try w.print("a capture was readable after an attempt that did not match\n", .{});
        try w.flush();
        return error.ExampleStaleCapture;
    }
    try w.print("and no capture from the failed attempt is readable\n", .{});

    try w.flush();
}

/// Reads the provider from `--provider <path>` or `PCRE2_TEST_PROVIDER`.
/// Runtime builds require an explicit path; no default is searched.
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

/// Error path for a runtime build without a provider argument.
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
