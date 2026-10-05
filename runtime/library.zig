// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//
//! PCRE2's side of the runtime loader: the names its synchronization binding
//! has, which of the header's declarations a provider has to export, and what it
//! requires of that provider beyond resolving them.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them
//! PCRE2's, and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! Every export the translated `pcre2.h` declares: all three code-unit widths,
//! and the POSIX wrapper's four names where the header declares them.
//!
//! `src/pcre2.h.generic:1021-1031` emits the 8-, 16- and 32-bit declarations
//! into one header whatever `PCRE2_CODE_UNIT_WIDTH` is, and `PCRE2_SUFFIX`
//! (`:1064`) pastes the width onto every exported name. So the header this
//! route dispatches describes `pcre2_config_8`, `pcre2_config_16` and
//! `pcre2_config_32` in the same declaration list, and the generated table
//! carries a field for each of them. A table that required only the selected
//! width's names would leave the other two widths' fields `undefined` after a
//! successful load: the readiness flag would be set and every field behind it
//! would be an address nobody wrote. This descriptor therefore requires the
//! dispatch's whole `symbols` list, at the dispatch's own indices.
//!
//! Upstream ships `libpcre2-8`, `libpcre2-16` and `libpcre2-32` as three
//! separate libraries (`doc/pcre2.txt:494-503`) and none of them exports
//! another's names. **A standard single-width PCRE2 library is therefore not a
//! complete provider for this route.** It is a provider for one third of the
//! header this build translated. A provider for the translated surface has to
//! export every declared symbol in it, all three widths together; the artifact
//! this SDK builds and installs is one because the native graph compiles all
//! three widths' unmodified upstream sources into it (`build.zig`), and an
//! external file qualifies only when it exports everything below. A file that
//! opens and then lacks one of these names is refused with `MissingSymbol`
//! before anything is published, and there is no partial table behind it.
//!
//! The POSIX wrapper's four entry points, `src/pcre2posix.h:159-163`, need no
//! separate rule. `translate.h` includes `pcre2posix.h` under
//! `#if PCRE2_CODE_UNIT_WIDTH == 8`, so a width-8 translation declares
//! `pcre2_regcomp`, `pcre2_regexec`, `pcre2_regerror` and `pcre2_regfree` and
//! the generator routes them like any other declaration, and a 16- or 32-bit
//! translation does not declare them at all, so no field and no requirement
//! exist there. What the table declares is what is required; no name list is
//! written out in this file.
//!
//! ## The ABI boundary, stated honestly
//!
//! Every one of the three widths a provider carries must be a genuine library
//! of that width, built for this target: the C ABI, the scalar widths and the
//! calling convention are what a `dlopen` of a foreign object assumes and
//! cannot check. Beyond that:
//!
//!  * `PCRE2_SIZE` and every offset in the API is `size_t`
//!    (`src/pcre2.h.generic:307`), so a 32-bit host's provider is a different
//!    ABI from a 64-bit one's on every entry point that takes or returns an
//!    offset. This is upstream's ABI, not this fork's.
//!  * The compiled-in configuration a provider was built with is *not* fixed by
//!    the header, and this route cannot see it. `PCRE2_CONFIG_UNICODE`,
//!    `PCRE2_CONFIG_NEWLINE`, `PCRE2_CONFIG_BSR`, `PCRE2_CONFIG_LINK_SIZE`,
//!    `PCRE2_CONFIG_PARENSLIMIT`, `PCRE2_CONFIG_MATCH_LIMIT`,
//!    `PCRE2_CONFIG_DEPTH_LIMIT`, `PCRE2_CONFIG_RECURSION_LIMIT`,
//!    `PCRE2_CONFIG_HEAP_LIMIT` and `PCRE2_CONFIG_JIT` are all answers a
//!    provider gives and this header does not constrain, and a provider that
//!    answers them differently is still a provider of the same ABI. Nothing
//!    below rejects one.
//!  * The pattern's own `pcre2_jit_compile` needs `SUPPORT_JIT` and SLJIT
//!    (`src/pcre2_jit_compile.c`, and the `SLJIT_*` rows `build.zig` writes as
//!    false). This build compiles the six JIT names as upstream's
//!    `#ifndef SUPPORT_JIT` fallbacks, which all refuse; a provider built with
//!    SLJIT answers them instead. Both are the same ABI, and a caller that
//!    cares asks the provider rather than this loader.
//!
//! ## What is actually checked
//!
//! Resolving the symbols and translating the header are the boundary. They are
//! not proof that a provider is compatible, and this file does not pretend to
//! add one. The check below asks the provider, **for every code-unit width the
//! table declares**, to answer a configuration query and then to compile, match
//! and release one trivial pattern through the entry points that own memory,
//! so a provider that resolves every symbol and cannot actually allocate is
//! refused before anything is published. It proves the entry points behave at
//! each width. It does not prove the pointer width, or anything about the
//! compiled-in limits above.

const std = @import("std");
const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=pcre2_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols, and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn pcre2_rt_lock() void;
    extern fn pcre2_rt_unlock() void;
    extern fn pcre2_rt_wait() void;
    extern fn pcre2_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
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

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "pcre2";

        /// The table the generated dispatch declares. Every routed symbol has a
        /// field here, whatever width it belongs to, because the dispatch is
        /// generated from the whole translation and `pcre2.h` publishes all
        /// three widths. `symbols` below is what says which of those fields this
        /// load fills, and it is all of them.
        pub const table = dispatch.Table;

        /// `PCRE2_CONFIG_VERSION`, which the probe asks every width about.
        const config_version: u32 = @intCast(dispatch.PCRE2_CONFIG_VERSION);

        /// The three code-unit widths the translated header publishes.
        ///
        /// This is not a choice about which libraries exist; it is the list
        /// `src/pcre2.h.generic:1021-1031` emits and `PCRE2_SUFFIX` (`:1064`)
        /// suffixes.
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

        /// Every symbol a provider has to export, in the order `assign` below
        /// expects them. A provider that does not export all of them is refused
        /// with `MissingSymbol` before anything is published.
        ///
        /// This is the dispatch's own list, not a filtered copy of it. That is
        /// what makes the index `assign` receives the index the table field has
        /// and the index the dispatch's `assign` wants, with no count, no
        /// buffer and no name lookup anywhere between the two.
        pub const symbols: []const rt.Symbol = dispatch.symbols;

        /// The symbols the provider may legitimately not export, in the
        /// dispatch's own order, so `assignOptional` and `assignMissing` index
        /// it directly.
        ///
        /// `runtime/graph.zig` declares none today, which is a decision rather
        /// than an absence: every entry point of every width the table declares
        /// is expected from a provider. The declaration stays because the
        /// loader clears these fields before each attempt and fills the ones
        /// the provider does export, and that has to be the dispatch's list and
        /// nothing else.
        pub const optional_symbols: []const rt.Symbol = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        /// Write one resolved address into one table field.
        ///
        /// `index` is the position in `symbols` above, which is the position in
        /// the dispatch's own list, so this is the same field either way.
        pub inline fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// One resolved address into one optional table field, and the empty
        /// case beside it. Both index `optional_symbols`.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Whether the table carries one width's whole compile-match-release
        /// closure. The check is on the table type rather than on a name, so a
        /// translation that did not declare a width cannot produce a probe for
        /// a width whose fields do not exist.
        fn declaresWidth(comptime bits: []const u8) bool {
            return @hasField(table, field_name("pcre2_config", bits)) and
                @hasField(table, field_name("pcre2_compile", bits)) and
                @hasField(table, field_name("pcre2_match", bits)) and
                @hasField(table, field_name("pcre2_match_data_create_from_pattern", bits)) and
                @hasField(table, field_name("pcre2_match_data_free", bits)) and
                @hasField(table, field_name("pcre2_code_free", bits));
        }

        /// Ask one width's entry points to do the work, and release everything
        /// they allocate on every path out of here.
        ///
        /// Two things, both of which a provider answers by running its own code.
        ///
        /// The first is the configuration query for the version string's
        /// length: `pcre2_config_N(PCRE2_CONFIG_VERSION, NULL)` returns
        /// `1 + strlen` and writes nothing (`src/pcre2_config.c:73-103`,
        /// `:241-242`), so a provider that answers a positive count here has a
        /// configuration table behind it.
        ///
        /// The second is a whole compile-match-release round trip through the
        /// entry points that own memory: `pcre2_compile_N`,
        /// `pcre2_match_data_create_from_pattern_N`, `pcre2_match_N`,
        /// `pcre2_match_data_free_N` and `pcre2_code_free_N`. Every block in
        /// that probe is released on every path, including the failing ones,
        /// because a provider that resolved the symbols can still answer NULL
        /// and nothing here may leak it.
        ///
        /// The table is read through `dst` field by field. There is no copy of
        /// it: one function pointer at a time, and the table is large.
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

        /// The one library-specific check, run after every symbol resolved and
        /// before anything is published.
        ///
        /// Every width the table declares, in turn. The selected
        /// `-Dcode-unit-width` chooses the generic aliases, the primary
        /// artifact's name and the typed facade; it does not narrow the header,
        /// so it does not narrow this check either.
        ///
        /// What it does not prove is listed in this file's header: the pointer
        /// width and the compiled-in limits are not established by this probe,
        /// and the fact that a provider answered is not a compatibility verdict.
        pub fn validate(dst: *const table) ?[]const u8 {
            inline for (all_widths) |bits| {
                if (comptime !declaresWidth(bits)) continue;
                if (exerciseWidth(dst, bits)) |why| return why;
            }
            return null;
        }
    };
}
