//! External consumer of the published `pcre2` module.
//! Exercises named captures across code-unit widths and supports linked or runtime loading.

const std = @import("std");
const pcre2 = @import("pcre2");

/// Code-unit type selected by this build.
const Unit = pcre2.compiled_unit;

/// Widen an ASCII constant to this build's code units at comptime.
/// The returned slice has static storage and needs no cleanup.
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

/// Widen runtime ASCII into caller-owned code-unit storage.
/// Returns `TextNotWidened` when the output slice is too short.
fn widen(ascii: []const u8, out: []Unit) error{TextNotWidened}![]const Unit {
    if (out.len < ascii.len) return error.TextNotWidened;
    for (ascii, 0..) |byte, i| {
        if (byte > std.math.maxInt(Unit)) return error.TextNotWidened;
        out[i] = byte;
    }
    return out[0..ascii.len];
}

/// Anchored `level[id] message` pattern with an optional numeric id.
const pattern = wide("^(?<level>[A-Z]+)(?:\\[(?<id>[0-9]+)\\])? (?<message>.*)$");

/// Expected captures and code-unit offsets for one input line.
const Line = struct {
    subject: []const u8,
    /// Expected `level/id/message` rendering; `-` marks an unset id.
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

// ASCII input with an id; offsets are code-unit positions.
const with_id: Line = .{
    .subject = "ERROR[4171] disk full on /dev/sda1",
    .rendered = "ERROR/4171/disk full on /dev/sda1",
    .level = .{ .text = "ERROR", .start = 0, .end = 5 },
    .id = Capture{ .text = "4171", .start = 6, .end = 10 },
    .message = .{ .text = "disk full on /dev/sda1", .start = 12, .end = 34 },
};

// ASCII input without an id; the optional group is unset.
const without_id: Line = .{
    .subject = "WARN disk nearly full",
    .rendered = "WARN/-/disk nearly full",
    .level = .{ .text = "WARN", .start = 0, .end = 4 },
    .id = null,
    .message = .{ .text = "disk nearly full", .start = 5, .end = 21 },
};

/// Compile the shared pattern once for both input lines.
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

const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    // Load an explicit provider only for runtime-loaded builds.
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

    // Print the reported version through caller-owned code-unit storage.
    var version_buffer: [64]Unit = undefined;
    const version = pcre2.version(&version_buffer) catch |err| {
        try w.print("the library did not report a version: {s}\n", .{@errorName(err)});
        try w.flush();
        return error.VersionNotReported;
    };
    // Convert code units to bytes for identical output at every width.
    var version_bytes: [version_buffer.len]u8 = undefined;
    for (version, 0..) |unit, index| version_bytes[index] = @intCast(unit);
    try w.print("pcre2 consumer, linked against {s}\n", .{version_bytes[0..version.len]});

    var regex = try compilePattern();
    defer regex.deinit();
    try w.print("{d} capturing groups, {d} names\n", .{ regex.captureCount(), regex.nameCount() });

    // Resolve named groups rather than assuming their numbers.
    const level_group = regex.numberForName(wide("level")) orelse return error.NameMissing;
    const id_group = regex.numberForName(wide("id")) orelse return error.NameMissing;
    const message_group = regex.numberForName(wide("message")) orelse return error.NameMissing;

    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();
    var context = try pcre2.MatchContext.init();
    defer context.deinit();
    context.setMatchLimit(1_000_000);

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

        // An unset optional group has no range; it is not an empty capture.
        const id_range = try match_data.groupRange(id_group);
        if (line.id) |want| {
            const id_text = id orelse return error.IdExpectedButUnset;
            if (id_range == null) return error.IdExpectedButUnset;
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

/// Check capture text and code-unit offsets against hand-worked expectations.
/// Uses caller-owned scratch storage and retains no slices.
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

/// Assemble `level/id/message` into caller-owned output without allocating.
/// Returns an error if the output slice is too short.
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

/// Write one ASCII code unit as a byte.
/// Return `NonAsciiAssembly` instead of truncating a value above `u8`.
fn writeByte(out: []u8, at: usize, unit: Unit) error{NonAsciiAssembly}!usize {
    if (unit > std.math.maxInt(u8)) return error.NonAsciiAssembly;
    out[at] = @intCast(unit);
    return 1;
}

/// Read the provider path from `--provider <path>` or `PCRE2_TEST_PROVIDER`.
/// No default lookup or fallback is used.
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
