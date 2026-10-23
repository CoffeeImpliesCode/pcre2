// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//
//! PCRE2 runtime-provider descriptor for the translated API.
//! Requires all declared symbols and probes each declared width before publication.

const std = @import("std");
const rt = @import("rt");

/// Namespaced synchronization functions required by the generic loader.
/// The symbol prefix must match the one compiled into `runtime/sync.c`.
pub const Sync = struct {
    extern fn pcre2_rt_lock() void;
    extern fn pcre2_rt_unlock() void;
    extern fn pcre2_rt_wait() void;
    extern fn pcre2_rt_broadcast() void;
    // C `unsigned long long` matches `u64` on the supported ABIs.
    extern fn pcre2_rt_thread_self() u64;

    pub fn lock() void {
        pcre2_rt_lock();
    }
    pub fn unlock() void {
        pcre2_rt_unlock();
    }
    pub fn wait() void {
        pcre2_rt_wait();
    }
    pub fn broadcast() void {
        pcre2_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return pcre2_rt_thread_self();
    }
};

/// Bind the generic loader to one generated dispatch type.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name shown in a pre-load panic.
        pub const library_name = "pcre2";

        /// Dispatch table type for all translated routed symbols.
        pub const table = dispatch.Table;

        /// `PCRE2_CONFIG_VERSION`, which the probe asks every width about.
        const config_version: u32 = @intCast(dispatch.PCRE2_CONFIG_VERSION);

        /// Code-unit widths declared by the translated header.
        const all_widths = [_][]const u8{ "8", "16", "32" };

        /// `PCRE2_UCHAR<N>` for one of `all_widths`.
        fn unit(comptime bits: []const u8) type {
            if (std.mem.eql(u8, bits, "8")) return u8;
            if (std.mem.eql(u8, bits, "16")) return u16;
            if (std.mem.eql(u8, bits, "32")) return u32;
            @compileError(
                "runtime/library.zig: all_widths names a width PCRE2_UCHAR has " ++
                    "no type for.",
            );
        }

        /// The width-suffixed spelling the translated header declares for a
        /// generic entry point.
        fn field_name(comptime base: []const u8, comptime bits: []const u8) []const u8 {
            return base ++ "_" ++ bits;
        }

        /// Required exports in dispatch order; missing symbols reject provider loading.
        /// Includes every code-unit width declared by the header.
        pub const symbols: []const rt.Symbol = dispatch.symbols;

        /// Optional exports in dispatch order; none are optional for this descriptor.
        pub const optional_symbols: []const rt.Symbol = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        /// Store one resolved address in its dispatch table field.
        pub inline fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// Store or clear one optional dispatch table field.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Whether the table contains a width's probe functions.
        fn declaresWidth(comptime bits: []const u8) bool {
            return @hasField(table, field_name("pcre2_config", bits)) and
                @hasField(table, field_name("pcre2_compile", bits)) and
                @hasField(table, field_name("pcre2_match", bits)) and
                @hasField(table, field_name("pcre2_match_data_create_from_pattern", bits)) and
                @hasField(table, field_name("pcre2_match_data_free", bits)) and
                @hasField(table, field_name("pcre2_code_free", bits));
        }

        /// Compile, match, and release a trivial pattern at one width.
        /// Release all allocations on every exit path.
        fn exerciseWidth(dst: *const table, comptime bits: []const u8) ?[]const u8 {
            const U = unit(bits);
            const config = @field(dst, field_name("pcre2_config", bits));
            const compile = @field(dst, field_name("pcre2_compile", bits));
            const create_from_pattern =
                @field(dst, field_name("pcre2_match_data_create_from_pattern", bits));
            const run_match = @field(dst, field_name("pcre2_match", bits));
            const match_data_free = @field(dst, field_name("pcre2_match_data_free", bits));
            const code_free = @field(dst, field_name("pcre2_code_free", bits));

            const needed = config(config_version, null);
            if (needed < 1) {
                return "pcre2_config_" ++ bits ++ "(PCRE2_CONFIG_VERSION, NULL) did " ++
                    "not answer a length, so this provider's configuration " ++
                    "table is not one this header describes";
            }

            const pattern: [2:0]U = .{ 'a', 0 };
            const subject: [2:0]U = .{ 'a', 0 };
            var errorcode: c_int = 0;
            var erroroffset: usize = 0;

            const compiled = compile(&pattern, 1, 0, &errorcode, &erroroffset, null) orelse
                return "pcre2_compile_" ++ bits ++ " answered NULL for the pattern " ++
                    "'a', so this provider cannot compile a pattern of this width " ++
                    "that this header accepts";
            const data = create_from_pattern(compiled, null) orelse {
                code_free(compiled);
                return "pcre2_match_data_create_from_pattern_" ++ bits ++ " " ++
                    "answered NULL, so this provider cannot allocate a match " ++
                    "block of this width";
            };
            const rc = run_match(compiled, &subject, 1, 0, 0, data, null);
            match_data_free(data);
            code_free(compiled);

            if (rc != 1) {
                return "pcre2_match_" ++ bits ++ " did not match the subject 'a' " ++
                    "against the pattern 'a' that pcre2_compile_" ++ bits ++ " " ++
                    "had just accepted, so this provider is not doing what " ++
                    "these declarations describe";
            }
            return null;
        }

        /// Validate each declared width before publication; return a refusal message on failure.
        /// The probe does not establish pointer width or compiled-in limits.
        pub fn validate(dst: *const table) ?[]const u8 {
            inline for (all_widths) |bits| {
                if (comptime !declaresWidth(bits)) continue;
                if (exerciseWidth(dst, bits)) |why| return why;
            }
            return null;
        }
    };
}
