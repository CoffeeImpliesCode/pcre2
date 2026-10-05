// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//
//! One typed binding per entry point `pcre2.h` declares, generic over the
//! code-unit width.
//!
//! Nothing here is a declaration of its own: every function is an `inline fn`
//! that forwards to the name the translated header declared for the width being
//! built, with the parameter and return types that translation already fixed.
//! `pcre2.h.generic:1021-1031` emits all three widths into one header, so the
//! name this file reaches for is `pcre2_<entry>_8`, `_16` or `_32`, and
//! `PCRE2_SUFFIX` (`:1064`) is what pastes the digits on.
//!
//! Two things this file deliberately does not do:
//!
//!   * It does not name a PCRE2 type twice. The opaque blocks, the callout
//!     blocks and the callback signatures come from the translation through the
//!     `Types` switch below, so `pcre2_code_8` in a facade, in this file and in
//!     the library are one nominal type and a value of one needs no cast.
//!   * It does not decide what is a call and what is not. Every function below
//!     is a call, including the six `pcre2_jit_*` names, which exist in this
//!     configuration as upstream's `#ifndef SUPPORT_JIT` fallbacks and answer
//!     `PCRE2_ERROR_JIT_BADOPTION`. Whether a JIT call can succeed is a
//!     property of the library a caller reached, not of the header.

/// The complete translated `pcre2.h` for this build.
///
/// This is `zig/root.zig`'s `c` under its own name, and it is the same module
/// in both configurations: the translated header when the library is linked,
/// and the generated dispatch that re-exports it when it is loaded at run time.
const c = @import("c");

/// The typed entry points of one code-unit width.
pub fn Raw(comptime code_unit: type) type {
    return struct {

        /// The width's digits, as `PCRE2_SUFFIX` spells them.
        const bits: []const u8 = switch (code_unit) {
            u8 => "8",
            u16 => "16",
            u32 => "32",
            else => @compileError(
                "pcre2: PCRE2_CODE_UNIT_WIDTH names 8, 16 or 32, and this " ++
                    "facade is written for those three and nothing else.",
            ),
        };

        /// The width-suffixed name of a generic entry point.
        inline fn n(comptime base: []const u8) []const u8 {
            return base ++ "_" ++ bits;
        }

        /// The width's own opaque blocks and callback types.
        ///
        /// A switch, and not a computed name, because these have to appear in
        /// type positions: a PCRE2 type reached through `@field` would have to
        /// be recovered with `@TypeOf`, and one that was computed rather than
        /// read out of the translation would not be the same nominal type the
        /// header declares. These six lines per width are the whole price.
        pub const Types = switch (code_unit) {
            u8 => struct {
                pub const Code = c.pcre2_code_8;
                pub const CodeReal = c.pcre2_real_code_8;
                pub const GeneralContext = c.pcre2_general_context_8;
                pub const CompileContext = c.pcre2_compile_context_8;
                pub const ConvertContext = c.pcre2_convert_context_8;
                pub const MatchContext = c.pcre2_match_context_8;
                pub const MatchData = c.pcre2_match_data_8;
                pub const JitStack = c.pcre2_jit_stack_8;
                pub const CalloutBlock = c.pcre2_callout_block_8;
                pub const CalloutEnumerateBlock = c.pcre2_callout_enumerate_block_8;
                pub const SubstituteCalloutBlock = c.pcre2_substitute_callout_block_8;
            },
            u16 => struct {
                pub const Code = c.pcre2_code_16;
                pub const CodeReal = c.pcre2_real_code_16;
                pub const GeneralContext = c.pcre2_general_context_16;
                pub const CompileContext = c.pcre2_compile_context_16;
                pub const ConvertContext = c.pcre2_convert_context_16;
                pub const MatchContext = c.pcre2_match_context_16;
                pub const MatchData = c.pcre2_match_data_16;
                pub const JitStack = c.pcre2_jit_stack_16;
                pub const CalloutBlock = c.pcre2_callout_block_16;
                pub const CalloutEnumerateBlock = c.pcre2_callout_enumerate_block_16;
                pub const SubstituteCalloutBlock = c.pcre2_substitute_callout_block_16;
            },
            else => struct {
                pub const Code = c.pcre2_code_32;
                pub const CodeReal = c.pcre2_real_code_32;
                pub const GeneralContext = c.pcre2_general_context_32;
                pub const CompileContext = c.pcre2_compile_context_32;
                pub const ConvertContext = c.pcre2_convert_context_32;
                pub const MatchContext = c.pcre2_match_context_32;
                pub const MatchData = c.pcre2_match_data_32;
                pub const JitStack = c.pcre2_jit_stack_32;
                pub const CalloutBlock = c.pcre2_callout_block_32;
                pub const CalloutEnumerateBlock = c.pcre2_callout_enumerate_block_32;
                pub const SubstituteCalloutBlock = c.pcre2_substitute_callout_block_32;
            },
        };

        /// The compiled-in type of one PCRE2 offset, `PCRE2_SIZE`
        /// (`src/pcre2.h.generic:536`): `size_t` on every target this SDK
        /// builds, and therefore the same type `[*c]usize` is for in the
        /// offset vector.
        pub const Size = c.PCRE2_SIZE;

        /// `PCRE2_SPTR<N>`: a possibly-null pointer to a code unit.
        pub const SPtr = [*c]const code_unit;

        /// `PCRE2_UCHAR<N>`: one code unit.
        pub const UChar = code_unit;

        // ---- Callback signatures the header declares --------------------
        //
        // Each is spelled with `?*const fn (...) callconv(.c) ...`, which is
        // what the translation emits for a C function-pointer parameter, so a
        // Zig function a caller writes coerces into it without a cast.

        /// `pcre2_set_callout`: called at each callout in a pattern.
        pub const Callout = ?*const fn ([*c]Types.CalloutBlock, ?*anyopaque) callconv(.c) c_int;

        /// `pcre2_set_substitute_callout`: called for each substitution.
        pub const SubstituteCallout = ?*const fn ([*c]Types.SubstituteCalloutBlock, ?*anyopaque) callconv(.c) c_int;

        /// `pcre2_set_substitute_case_callout`: supplies the replacement text
        /// for one substitution. Returning `c.pcre2_substitute_callout_free`
        /// hands ownership of `buffer` to PCRE2, which frees it with
        /// `pcre2_substring_free`; returning any other count copies that many
        /// code units out and frees `buffer` here.
        pub const SubstituteCaseCallout = ?*const fn (
            SPtr,
            usize,
            [*c]code_unit,
            usize,
            c_int,
            ?*anyopaque,
        ) callconv(.c) usize;

        /// `pcre2_set_compile_recursion_guard`: called when the compiler is
        /// about to recurse further. A non-zero return aborts the compile with
        /// `PCRE2_ERROR_RECURSELOOP`, -52.
        pub const RecursionGuard = ?*const fn (u32, ?*anyopaque) callconv(.c) c_int;

        /// `pcre2_jit_callback`: supplies a machine stack to `pcre2_jit_match`
        /// for one attempt. It may return null, which asks PCRE2 to use the
        /// small block on the stack.
        pub const JitCallback = ?*const fn (?*anyopaque) callconv(.c) ?*Types.JitStack;

        /// `pcre2_callout_enumerate`'s callback, walked once per callout in a
        /// compiled pattern. **Not optional, unlike the ones above**: upstream
        /// calls it for every `OP_CALLOUT` and `OP_CALLOUT_STR` and never tests
        /// it against null (`src/pcre2_pattern_info.c:405`, `:418`), so a
        /// caller cannot hand it one. The binding below still takes the
        /// translated header's optional function pointer, which is what the
        /// declaration is; this alias is the honest shape of a value to pass.
        pub const CalloutEnumerate = *const fn (
            [*c]Types.CalloutEnumerateBlock,
            ?*anyopaque,
        ) callconv(.c) c_int;

        /// The allocation pair `pcre2_general_context_create` takes. Both
        /// function pointers may be null, in which case PCRE2 uses `malloc` and
        /// `free` (`src/pcre2_context.c:120-159`).
        pub const Allocate = ?*const fn (usize, ?*anyopaque) callconv(.c) ?*anyopaque;
        pub const Deallocate = ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void;

        // ---- General information ----------------------------------------

        /// `pcre2_config`: one of the `PCRE2_CONFIG_*` queries. With a null
        /// `where` the string queries answer the size they need, including its
        /// terminating null, and write nothing.
        pub inline fn config(which: u32, where: ?*anyopaque) c_int {
            return @field(c, n("pcre2_config"))(which, where);
        }

        /// `pcre2_get_error_message`: writes at most `len - 1` code units and a
        /// null into `buffer`, and answers the number of code units written
        /// without the null, or `PCRE2_ERROR_NOMEMORY` when the message did not
        /// fit.
        pub inline fn get_error_message(code: c_int, buffer: [*c]code_unit, len: usize) c_int {
            return @field(c, n("pcre2_get_error_message"))(code, buffer, len);
        }

        // ---- Compiling a pattern -----------------------------------------

        /// `pcre2_compile`. `length` is in code units; `PCRE2_ZERO_TERMINATED`
        /// is upstream's own macro and this binding never passes it, because
        /// the translation has no value for it.
        pub inline fn compile(
            pattern: SPtr,
            length: usize,
            options: u32,
            errorcode: [*c]c_int,
            erroroffset: [*c]usize,
            context: ?*Types.CompileContext,
        ) ?*Types.Code {
            return @field(c, n("pcre2_compile"))(
                pattern,
                length,
                options,
                errorcode,
                erroroffset,
                context,
            );
        }

        /// `pcre2_code_free`. The only way a compiled block is released.
        pub inline fn code_free(code: ?*Types.Code) void {
            @field(c, n("pcre2_code_free"))(code);
        }

        /// `pcre2_code_copy`: a second compiled block the caller owns and must
        /// release with `pcre2_code_free`.
        pub inline fn code_copy(code: ?*const Types.Code) ?*Types.Code {
            return @field(c, n("pcre2_code_copy"))(code);
        }

        /// `pcre2_code_copy_with_tables`: the same, with the character tables
        /// copied too, so the copy does not depend on the process locale.
        pub inline fn code_copy_with_tables(code: ?*const Types.Code) ?*Types.Code {
            return @field(c, n("pcre2_code_copy_with_tables"))(code);
        }

        /// `pcre2_pattern_info`: one of the `PCRE2_INFO_*` queries. `where`
        /// is a pointer to the value's own type, which is `u32` for every query
        /// except `PCRE2_INFO_NAMETABLE`.
        pub inline fn pattern_info(code: ?*const Types.Code, what: u32, where: ?*anyopaque) c_int {
            return @field(c, n("pcre2_pattern_info"))(code, what, where);
        }

        /// `pcre2_callout_enumerate`: walk every callout in a compiled pattern.
        /// The callback returns non-zero to stop; the value is passed on.
        pub inline fn callout_enumerate(
            code: ?*const Types.Code,
            callback: ?*const fn ([*c]Types.CalloutEnumerateBlock, ?*anyopaque) callconv(.c) c_int,
            data: ?*anyopaque,
        ) c_int {
            return @field(c, n("pcre2_callout_enumerate"))(code, callback, data);
        }

        // ---- Matching -----------------------------------------------------

        /// `pcre2_match`: the interpreted matcher. A return of zero is
        /// upstream's truncated answer and is not a match.
        pub inline fn match(
            code: ?*const Types.Code,
            subject: SPtr,
            length: usize,
            startoffset: usize,
            options: u32,
            match_data: ?*Types.MatchData,
            match_context: ?*Types.MatchContext,
        ) c_int {
            return @field(c, n("pcre2_match"))(
                code,
                subject,
                length,
                startoffset,
                options,
                match_data,
                match_context,
            );
        }

        /// `pcre2_dfa_match`: the non-backtracking matcher. `match_data` receives
        /// the matched ranges in its own offset vector, which is where they land
        /// (`src/pcre2_dfa_match.c:4062-4063`). `match_vector` is the caller's
        /// scratch buffer and `ovecsize` is how many `c_int` entries it has.
        pub inline fn dfa_match(
            code: ?*const Types.Code,
            subject: SPtr,
            length: usize,
            startoffset: usize,
            options: u32,
            match_data: ?*Types.MatchData,
            match_context: ?*Types.MatchContext,
            match_vector: [*c]c_int,
            ovecsize: usize,
        ) c_int {
            return @field(c, n("pcre2_dfa_match"))(
                code,
                subject,
                length,
                startoffset,
                options,
                match_data,
                match_context,
                match_vector,
                ovecsize,
            );
        }

        /// `pcre2_next_match`: the parameters for the next match attempt after
        /// this one, for a caller iterating over every match in a subject. The
        /// two out-parameters are a single start offset and a single options
        /// word -- `PCRE2_SIZE *` and `uint32_t *`
        /// (`src/pcre2.h.generic:775`) -- not an offset vector and a pair count;
        /// `ovector` is a local inside that function
        /// (`src/pcre2_match_next.c:102`), never a parameter.
        pub inline fn next_match(
            match_data: ?*Types.MatchData,
            pstart_offset: [*c]usize,
            poptions: [*c]u32,
        ) c_int {
            return @field(c, n("pcre2_next_match"))(match_data, pstart_offset, poptions);
        }

        // ---- Match data ---------------------------------------------------

        /// `pcre2_match_data_create`: a block whose offset vector holds
        /// `ovecsize` pairs, group 0 included.
        pub inline fn match_data_create(
            ovecsize: u32,
            context: ?*Types.GeneralContext,
        ) ?*Types.MatchData {
            return @field(c, n("pcre2_match_data_create"))(ovecsize, context);
        }

        /// `pcre2_match_data_create_from_pattern`: a block sized for one
        /// pattern's groups.
        pub inline fn match_data_create_from_pattern(
            code: ?*const Types.Code,
            context: ?*Types.GeneralContext,
        ) ?*Types.MatchData {
            return @field(c, n("pcre2_match_data_create_from_pattern"))(code, context);
        }

        /// `pcre2_match_data_free`.
        pub inline fn match_data_free(match_data: ?*Types.MatchData) void {
            @field(c, n("pcre2_match_data_free"))(match_data);
        }

        pub inline fn get_mark(match_data: ?*Types.MatchData) SPtr {
            return @field(c, n("pcre2_get_mark"))(match_data);
        }

        pub inline fn get_startchar(match_data: ?*Types.MatchData) usize {
            return @field(c, n("pcre2_get_startchar"))(match_data);
        }

        pub inline fn get_ovector_count(match_data: ?*Types.MatchData) u32 {
            return @field(c, n("pcre2_get_ovector_count"))(match_data);
        }

        pub inline fn get_ovector_pointer(match_data: ?*Types.MatchData) [*c]usize {
            return @field(c, n("pcre2_get_ovector_pointer"))(match_data);
        }

        pub inline fn get_match_data_size(match_data: ?*Types.MatchData) usize {
            return @field(c, n("pcre2_get_match_data_size"))(match_data);
        }

        pub inline fn get_match_data_heapframes_size(match_data: ?*Types.MatchData) usize {
            return @field(c, n("pcre2_get_match_data_heapframes_size"))(match_data);
        }

        // ---- Substrings ---------------------------------------------------

        /// `pcre2_substring_number_from_name`: a group number for a NUL-
        /// terminated name, or a negative error.
        pub inline fn substring_number_from_name(code: ?*const Types.Code, name: SPtr) c_int {
            return @field(c, n("pcre2_substring_number_from_name"))(code, name);
        }

        /// `pcre2_substring_nametable_scan`: find a name in a pattern's name
        /// table without compiling a match. The three out-parameters are
        /// matched pairs, and any one of them may be null.
        pub inline fn substring_nametable_scan(
            code: ?*const Types.Code,
            name: SPtr,
            first: [*c]SPtr,
            last: [*c]SPtr,
        ) c_int {
            return @field(c, n("pcre2_substring_nametable_scan"))(code, name, first, last);
        }

        /// `pcre2_substring_copy_byname`: copies the group into the caller's own
        /// `output`, which `length` carries the room of on the way in and comes
        /// back holding the number of code units written on the way out. The
        /// terminating null is part of the room PCRE2 requires and is not
        /// counted in the length it reports, and it is
        /// `PCRE2_ERROR_NOMEMORY`, -48, when the room is not there
        /// (`src/pcre2.h.generic:781-783`, `src/pcre2_substring.c:117-130`).
        /// Nothing here is allocated by PCRE2 and nothing is released.
        pub inline fn substring_copy_byname(
            match_data: ?*Types.MatchData,
            name: SPtr,
            output: [*c]code_unit,
            length: [*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_copy_byname"))(match_data, name, output, length);
        }

        /// `pcre2_substring_copy_bynumber`: the same, for a group number. The
        /// `PCRE2_UCHAR *` in that position is the caller's buffer and not a
        /// pointer to one, which is what separates this from
        /// `substring_get_bynumber` below
        /// (`src/pcre2.h.generic:784-786`).
        pub inline fn substring_copy_bynumber(
            match_data: ?*Types.MatchData,
            number: u32,
            output: [*c]code_unit,
            length: [*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_copy_bynumber"))(match_data, number, output, length);
        }

        /// `pcre2_substring_get_byname`: a copy PCRE2 allocated from
        /// `match_data`'s own record of the subject, so it does not need
        /// `MatchOptions.copy_matched_subject`; released with
        /// `pcre2_substring_free`, and by nothing else
        /// (`src/pcre2_substring.c:156-179`, `:205-224`).
        pub inline fn substring_get_byname(
            match_data: ?*Types.MatchData,
            name: SPtr,
            output: [*c][*c]code_unit,
            length: [*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_get_byname"))(match_data, name, output, length);
        }

        pub inline fn substring_get_bynumber(
            match_data: ?*Types.MatchData,
            number: u32,
            output: [*c][*c]code_unit,
            length: [*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_get_bynumber"))(match_data, number, output, length);
        }

        pub inline fn substring_length_byname(
            match_data: ?*Types.MatchData,
            name: SPtr,
            length: [*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_length_byname"))(match_data, name, length);
        }

        pub inline fn substring_length_bynumber(
            match_data: ?*Types.MatchData,
            number: u32,
            length: [*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_length_bynumber"))(match_data, number, length);
        }

        /// `pcre2_substring_list_get`: every capture of the attempt that filled
        /// `match_data`, in group order, as one NUL-separated list PCRE2
        /// allocated.
        ///
        /// The two out-parameters are one slot each and not one per group:
        /// `output` comes back holding PCRE2's own array of `count + 1`
        /// `PCRE2_UCHAR *`, the last of which is the null terminator, and
        /// `length` comes back holding the array of `count` `PCRE2_SIZE` beside
        /// the strings in the same block (`src/pcre2_substring.c:395-419`,
        /// `:421-436`). The whole block is released by
        /// `pcre2_substring_list_free` and by nothing else.
        pub inline fn substring_list_get(
            match_data: ?*Types.MatchData,
            output: [*c][*c][*c]code_unit,
            length: [*c][*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_list_get"))(match_data, output, length);
        }

        /// `pcre2_substring_list_free`: releases the block `substring_list_get`
        /// allocated, from the array of pointers it wrote through `output`
        /// rather than from the strings themselves
        /// (`src/pcre2_substring.c:451-459`).
        pub inline fn substring_list_free(list: [*c][*c]code_unit) void {
            @field(c, n("pcre2_substring_list_free"))(list);
        }

        /// `pcre2_substring_free`: releases one block
        /// `substring_get_byname` or `substring_get_bynumber` allocated. The
        /// block carries a hidden allocator header, so this and not a Zig
        /// allocator is what may free it (`src/pcre2_substring.c:237-245`).
        pub inline fn substring_free(buffer: [*c]code_unit) void {
            @field(c, n("pcre2_substring_free"))(buffer);
        }

        // ---- Substitution -------------------------------------------------

        /// `pcre2_substitute`: replace matches in `subject`. On success it
        /// answers the **number of substitutions**, not the length of the
        /// result, and writes the result's length without its terminating null
        /// through the second out-parameter (`src/pcre2_substitute.c:1757-1764`).
        /// A length answer is the other thing this call produces, and it comes
        /// with `PCRE2_ERROR_NOMEMORY`, -48, when the overflow option is set
        /// (`:1746-1755`).
        ///
        /// The block it is given is the caller's and it is written into: the
        /// matcher runs there (`:984`), and unless `PCRE2_SUBSTITUTE_MATCHED`
        /// made upstream copy the block first (`:898-917`), `rc` is left holding
        /// the substitution count on the way out (`:1766-1769`) -- a field every
        /// native substring entry point reads as a pair count
        /// (`src/pcre2_substring.c:317`, `:390`).
        pub inline fn substitute(
            code: ?*const Types.Code,
            subject: SPtr,
            length: usize,
            startoffset: usize,
            options: u32,
            match_data: ?*Types.MatchData,
            match_context: ?*Types.MatchContext,
            replacement: SPtr,
            replacement_length: usize,
            output: [*c]code_unit,
            output_length: [*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substitute"))(
                code,
                subject,
                length,
                startoffset,
                options,
                match_data,
                match_context,
                replacement,
                replacement_length,
                output,
                output_length,
            );
        }

        // ---- Serialization ------------------------------------------------

        /// `pcre2_serialize_encode`: a serialized copy of one or more compiled
        /// blocks.
        ///
        /// The second argument is the number of entries in `codes`, which is
        /// what upstream takes in that position (`src/pcre2_serialize.c:72-73`);
        /// there is no options argument. `serialized_bytes` and
        /// `serialized_size` come back with a block the library allocated,
        /// released with `pcre2_serialize_free` and by nothing else.
        pub inline fn serialize_encode(
            codes: [*c]?*const Types.Code,
            number_of_codes: i32,
            serialized_bytes: [*c][*c]u8,
            serialized_size: [*c]usize,
            context: ?*Types.GeneralContext,
        ) i32 {
            return @field(c, n("pcre2_serialize_encode"))(
                codes,
                number_of_codes,
                serialized_bytes,
                serialized_size,
                context,
            );
        }

        /// `pcre2_serialize_decode`: compiled blocks from bytes
        /// `pcre2_serialize_encode` produced. `number_of_codes` is how many the
        /// caller wants, and upstream answers how many it actually decoded: it
        /// caps the request at the count in the stream (`src/pcre2_serialize.c:183-184`)
        /// and returns that number (`:248`). Each decoded block is one the
        /// caller owns and releases with `pcre2_code_free`.
        pub inline fn serialize_decode(
            codes: [*c]?*Types.Code,
            number_of_codes: i32,
            bytes: [*c]const u8,
            context: ?*Types.GeneralContext,
        ) i32 {
            return @field(c, n("pcre2_serialize_decode"))(
                codes,
                number_of_codes,
                bytes,
                context,
            );
        }

        /// `pcre2_serialize_get_number_of_codes`: how many blocks a stream
        /// holds. Its negatives are all refusals of the bytes -- `PCRE2_ERROR_NULL`,
        /// `PCRE2_ERROR_BADMAGIC` and `PCRE2_ERROR_BADMODE`
        /// (`src/pcre2_serialize.c:272-275`) -- and none of them is an
        /// allocation failure, because nothing here allocates.
        pub inline fn serialize_get_number_of_codes(bytes: [*c]const u8) i32 {
            return @field(c, n("pcre2_serialize_get_number_of_codes"))(bytes);
        }

        pub inline fn serialize_free(bytes: [*c]u8) void {
            @field(c, n("pcre2_serialize_free"))(bytes);
        }

        // ---- Pattern conversion (glob to PCRE2) ---------------------------

        /// `pcre2_pattern_convert`: turn a glob into a compiled pattern. The
        /// result is a pattern the caller owns with
        /// `pcre2_converted_pattern_free`, not a compiled block.
        pub inline fn pattern_convert(
            glob: SPtr,
            length: usize,
            options: u32,
            output: [*c][*c]code_unit,
            output_length: [*c]usize,
            context: ?*Types.ConvertContext,
        ) c_int {
            return @field(c, n("pcre2_pattern_convert"))(
                glob,
                length,
                options,
                output,
                output_length,
                context,
            );
        }

        pub inline fn converted_pattern_free(converted: [*c]code_unit) void {
            @field(c, n("pcre2_converted_pattern_free"))(converted);
        }

        // ---- General context and the allocator ---------------------------

        /// `pcre2_general_context_create`: the allocator every other block in
        /// this library can be asked to come from. Two null function pointers
        /// mean upstream's `malloc` and `free`.
        pub inline fn general_context_create(
            allocate: Allocate,
            deallocate: Deallocate,
            data: ?*anyopaque,
        ) ?*Types.GeneralContext {
            return @field(c, n("pcre2_general_context_create"))(allocate, deallocate, data);
        }

        pub inline fn general_context_copy(context: ?*Types.GeneralContext) ?*Types.GeneralContext {
            return @field(c, n("pcre2_general_context_copy"))(context);
        }

        pub inline fn general_context_free(context: ?*Types.GeneralContext) void {
            @field(c, n("pcre2_general_context_free"))(context);
        }

        // ---- Compile context ----------------------------------------------

        pub inline fn compile_context_create(
            context: ?*Types.GeneralContext,
        ) ?*Types.CompileContext {
            return @field(c, n("pcre2_compile_context_create"))(context);
        }

        pub inline fn compile_context_copy(
            context: ?*Types.CompileContext,
        ) ?*Types.CompileContext {
            return @field(c, n("pcre2_compile_context_copy"))(context);
        }

        pub inline fn compile_context_free(context: ?*Types.CompileContext) void {
            @field(c, n("pcre2_compile_context_free"))(context);
        }

        /// `pcre2_set_newline`: the newline convention for both compiling and
        /// matching. One of the `PCRE2_NEWLINE_*` constants.
        pub inline fn set_newline(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_newline"))(context, value);
        }

        /// `pcre2_set_bsr`: what `\R` matches. `1` is `PCRE2_BSR_UNICODE`, any
        /// Unicode newline sequence; `2` is `PCRE2_BSR_ANYCRLF`, any single CR,
        /// LF or CRLF (`src/pcre2.h.generic:220-221`). A fresh context holds
        /// `BSR_DEFAULT`, which is `PCRE2_BSR_UNICODE` unless the library was
        /// built with `BSR_ANYCRLF` (`src/pcre2_internal.h:234-238`).
        pub inline fn set_bsr(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_bsr"))(context, value);
        }

        /// `pcre2_set_parens_nest_limit`: the nesting limit the compiler
        /// enforces on the pattern itself.
        pub inline fn set_parens_nest_limit(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_parens_nest_limit"))(context, value);
        }

        /// `pcre2_set_optimize`: `PCRE2_OPTIMIZE_*`.
        pub inline fn set_optimize(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_optimize"))(context, value);
        }

        /// `pcre2_set_compile_extra_options`: option bits applied to every
        /// pattern this context compiles, whatever `pcre2_compile` is given.
        pub inline fn set_compile_extra_options(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_compile_extra_options"))(context, value);
        }

        /// `pcre2_set_max_varlookbehind`: the longest variable-length lookbehind
        /// the compiler accepts.
        pub inline fn set_max_varlookbehind(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_max_varlookbehind"))(context, value);
        }

        /// `pcre2_set_character_tables`: use these 256 bytes as the character
        /// tables instead of the process locale's.
        pub inline fn set_character_tables(context: ?*Types.CompileContext, tables: [*c]const u8) c_int {
            return @field(c, n("pcre2_set_character_tables"))(context, tables);
        }

        pub inline fn set_max_pattern_length(context: ?*Types.CompileContext, value: usize) c_int {
            return @field(c, n("pcre2_set_max_pattern_length"))(context, value);
        }

        pub inline fn set_max_pattern_compiled_length(context: ?*Types.CompileContext, value: usize) c_int {
            return @field(c, n("pcre2_set_max_pattern_compiled_length"))(context, value);
        }

        pub inline fn set_compile_recursion_guard(
            context: ?*Types.CompileContext,
            callback: RecursionGuard,
            data: ?*anyopaque,
        ) c_int {
            return @field(c, n("pcre2_set_compile_recursion_guard"))(context, callback, data);
        }

        // ---- Convert context ----------------------------------------------

        pub inline fn convert_context_create(
            context: ?*Types.GeneralContext,
        ) ?*Types.ConvertContext {
            return @field(c, n("pcre2_convert_context_create"))(context);
        }

        pub inline fn convert_context_copy(
            context: ?*Types.ConvertContext,
        ) ?*Types.ConvertContext {
            return @field(c, n("pcre2_convert_context_copy"))(context);
        }

        pub inline fn convert_context_free(context: ?*Types.ConvertContext) void {
            @field(c, n("pcre2_convert_context_free"))(context);
        }

        /// `pcre2_set_glob_escape`: the character that escapes the next one in a
        /// glob.
        pub inline fn set_glob_escape(context: ?*Types.ConvertContext, value: u32) c_int {
            return @field(c, n("pcre2_set_glob_escape"))(context, value);
        }

        /// `pcre2_set_glob_separator`: one of `PCRE2_GLOBSEP_*`.
        pub inline fn set_glob_separator(context: ?*Types.ConvertContext, value: u32) c_int {
            return @field(c, n("pcre2_set_glob_separator"))(context, value);
        }

        // ---- Match context -------------------------------------------------

        pub inline fn match_context_create(
            context: ?*Types.GeneralContext,
        ) ?*Types.MatchContext {
            return @field(c, n("pcre2_match_context_create"))(context);
        }

        pub inline fn match_context_copy(
            context: ?*Types.MatchContext,
        ) ?*Types.MatchContext {
            return @field(c, n("pcre2_match_context_copy"))(context);
        }

        pub inline fn match_context_free(context: ?*Types.MatchContext) void {
            @field(c, n("pcre2_match_context_free"))(context);
        }

        pub inline fn set_match_limit(context: ?*Types.MatchContext, value: u32) c_int {
            return @field(c, n("pcre2_set_match_limit"))(context, value);
        }

        pub inline fn set_depth_limit(context: ?*Types.MatchContext, value: u32) c_int {
            return @field(c, n("pcre2_set_depth_limit"))(context, value);
        }

        pub inline fn set_heap_limit(context: ?*Types.MatchContext, value: u32) c_int {
            return @field(c, n("pcre2_set_heap_limit"))(context, value);
        }

        /// `pcre2_set_offset_limit`: the offset from which
        /// `PCRE2_USE_OFFSET_LIMIT` starts enforcing the match limit.
        pub inline fn set_offset_limit(context: ?*Types.MatchContext, value: usize) c_int {
            return @field(c, n("pcre2_set_offset_limit"))(context, value);
        }

        /// `pcre2_set_recursion_limit`: the internal-recursion ceiling.
        /// Deprecated in favour of the depth limit and answers
        /// `PCRE2_ERROR_BADOFFSET`-style refusal for a limit it will not take;
        /// it is here because the header declares it.
        pub inline fn set_recursion_limit(context: ?*Types.MatchContext, value: u32) c_int {
            return @field(c, n("pcre2_set_recursion_limit"))(context, value);
        }

        /// `pcre2_set_recursion_memory_management`: a per-context allocator for
        /// the matcher's internal recursion frames. Upstream keeps this for
        /// compatibility and ignores it; the value is returned.
        pub inline fn set_recursion_memory_management(
            context: ?*Types.MatchContext,
            allocate: Allocate,
            deallocate: Deallocate,
            data: ?*anyopaque,
        ) c_int {
            return @field(c, n("pcre2_set_recursion_memory_management"))(
                context,
                allocate,
                deallocate,
                data,
            );
        }

        pub inline fn set_callout(
            context: ?*Types.MatchContext,
            callback: Callout,
            data: ?*anyopaque,
        ) c_int {
            return @field(c, n("pcre2_set_callout"))(context, callback, data);
        }

        pub inline fn set_substitute_callout(
            context: ?*Types.MatchContext,
            callback: SubstituteCallout,
            data: ?*anyopaque,
        ) c_int {
            return @field(c, n("pcre2_set_substitute_callout"))(context, callback, data);
        }

        pub inline fn set_substitute_case_callout(
            context: ?*Types.MatchContext,
            callback: SubstituteCaseCallout,
            data: ?*anyopaque,
        ) c_int {
            return @field(c, n("pcre2_set_substitute_case_callout"))(context, callback, data);
        }

        // ---- JIT -----------------------------------------------------------

        /// `pcre2_jit_compile`. This fork builds with `SUPPORT_JIT` off, so the
        /// six JIT entry points are upstream's `#ifndef SUPPORT_JIT` fallbacks:
        /// this one answers `PCRE2_ERROR_JIT_BADOPTION`, -45
        /// (`src/pcre2_jit_compile.c:14303-14432`).
        pub inline fn jit_compile(code: ?*Types.Code, options: u32) c_int {
            return @field(c, n("pcre2_jit_compile"))(code, options);
        }

        /// `pcre2_jit_match`. **There is no fallback to `pcre2_match`.** In a
        /// build without SLJIT the whole body is upstream's `#ifndef SUPPORT_JIT`
        /// stub, which discards every argument -- `match_data` included -- and
        /// answers `PCRE2_ERROR_JIT_BADOPTION`, -45
        /// (`src/pcre2_jit_match_inc.h:95-103`). In this configuration that is
        /// every call to it: `deps/sljit` is an empty submodule and
        /// `SUPPORT_JIT` is 0 in the generated `config.h`.
        pub inline fn jit_match(
            code: ?*const Types.Code,
            subject: SPtr,
            length: usize,
            startoffset: usize,
            options: u32,
            match_data: ?*Types.MatchData,
            match_context: ?*Types.MatchContext,
        ) c_int {
            return @field(c, n("pcre2_jit_match"))(
                code,
                subject,
                length,
                startoffset,
                options,
                match_data,
                match_context,
            );
        }

        pub inline fn jit_free_unused_memory(context: ?*Types.GeneralContext) void {
            @field(c, n("pcre2_jit_free_unused_memory"))(context);
        }

        pub inline fn jit_stack_create(
            start: usize,
            maximum: usize,
            context: ?*Types.GeneralContext,
        ) ?*Types.JitStack {
            return @field(c, n("pcre2_jit_stack_create"))(start, maximum, context);
        }

        /// `pcre2_jit_stack_assign`: the stack `pcre2_jit_match` uses for every
        /// attempt made with this context.
        pub inline fn jit_stack_assign(
            context: ?*Types.MatchContext,
            callback: JitCallback,
            data: ?*anyopaque,
        ) void {
            @field(c, n("pcre2_jit_stack_assign"))(context, callback, data);
        }

        pub inline fn jit_stack_free(stack: ?*Types.JitStack) void {
            @field(c, n("pcre2_jit_stack_free"))(stack);
        }

        // ---- Character tables ---------------------------------------------

        /// `pcre2_maketables`: 256 bytes built from the current locale, or null
        /// when the allocation failed (`src/pcre2_maketables.c:94`). The buffer
        /// belongs to the library and is released with `pcre2_maketables_free`,
        /// from the same general context. A C `const uint8_t *` translates to a
        /// non-optional many-pointer, so the null answer upstream documents has
        /// to be recovered here or the caller cannot tell an allocation
        /// failure from a table.
        pub inline fn maketables(context: ?*Types.GeneralContext) ?[*c]const u8 {
            const tables: ?[*c]const u8 = @field(c, n("pcre2_maketables"))(context);
            return tables;
        }

        pub inline fn maketables_free(
            context: ?*Types.GeneralContext,
            tables: [*c]const u8,
        ) void {
            @field(c, n("pcre2_maketables_free"))(context, tables);
        }
    };
}
