// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//! Typed bindings for PCRE2's generic entry points at one code-unit width.
//! Opaque types come from the translation; this layer only forwards calls.

/// The translated PCRE2 declarations or their runtime dispatch.
const c = @import("c");

/// Typed bindings for one code-unit width.
pub fn Raw(comptime code_unit: type) type {
    return struct {
        const bits: []const u8 = switch (code_unit) {
            u8 => "8",
            u16 => "16",
            u32 => "32",
            else => @compileError(
                "pcre2: PCRE2_CODE_UNIT_WIDTH names 8, 16 or 32, and this " ++
                    "facade is written for those three and nothing else.",
            ),
        };

        inline fn n(comptime base: []const u8) []const u8 {
            return base ++ "_" ++ bits;
        }

        /// Opaque types and callbacks from the selected width's translated header.
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

        /// `PCRE2_SIZE`, used for code-unit offsets and lengths.
        pub const Size = c.PCRE2_SIZE;

        /// Nullable C pointer to code units (`PCRE2_SPTR<N>`).
        pub const SPtr = [*c]const code_unit;

        /// One code unit (`PCRE2_UCHAR<N>`).
        pub const UChar = code_unit;

        /// Callout invoked at each pattern callout.
        pub const Callout = ?*const fn ([*c]Types.CalloutBlock, ?*anyopaque) callconv(.c) c_int;

        /// Callout invoked for each substitution.
        pub const SubstituteCallout = ?*const fn ([*c]Types.SubstituteCalloutBlock, ?*anyopaque) callconv(.c) c_int;

        /// Supplies replacement text; the free sentinel transfers `buffer` ownership to PCRE2.
        pub const SubstituteCaseCallout = ?*const fn (
            SPtr,
            usize,
            [*c]code_unit,
            usize,
            c_int,
            ?*anyopaque,
        ) callconv(.c) usize;

        /// Guards compiler recursion; non-zero aborts with `PCRE2_ERROR_RECURSELOOP`.
        pub const RecursionGuard = ?*const fn (u32, ?*anyopaque) callconv(.c) c_int;

        /// Supplies the JIT machine stack; null selects PCRE2's internal stack.
        pub const JitCallback = ?*const fn (?*anyopaque) callconv(.c) ?*Types.JitStack;

        /// Non-null callback for each callout; a non-zero result stops enumeration.
        pub const CalloutEnumerate = *const fn (
            [*c]Types.CalloutEnumerateBlock,
            ?*anyopaque,
        ) callconv(.c) c_int;

        /// Allocator callbacks for a general context; null uses `malloc` and `free`.
        /// Frees memory allocated by the paired `Allocate` callback.
        pub const Allocate = ?*const fn (usize, ?*anyopaque) callconv(.c) ?*anyopaque;
        pub const Deallocate = ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void;

        /// Queries `PCRE2_CONFIG_*`; null string output reports required size including NUL.
        pub inline fn config(which: u32, where: ?*anyopaque) c_int {
            return @field(c, n("pcre2_config"))(which, where);
        }

        /// Writes a NUL-terminated error message and returns its code-unit length.
        /// Returns `PCRE2_ERROR_NOMEMORY` when the buffer is too small.
        pub inline fn get_error_message(code: c_int, buffer: [*c]code_unit, len: usize) c_int {
            return @field(c, n("pcre2_get_error_message"))(code, buffer, len);
        }

        /// Compiles a pattern whose explicit `length` is in code units.
        /// The generated translation does not expose `PCRE2_ZERO_TERMINATED`.
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

        /// Releases a compiled pattern.
        pub inline fn code_free(code: ?*Types.Code) void {
            @field(c, n("pcre2_code_free"))(code);
        }

        /// Copies a compiled pattern; the caller releases it with `code_free`.
        pub inline fn code_copy(code: ?*const Types.Code) ?*Types.Code {
            return @field(c, n("pcre2_code_copy"))(code);
        }

        /// Copies a compiled pattern and its character tables.
        /// The caller releases the copy with `code_free`.
        pub inline fn code_copy_with_tables(code: ?*const Types.Code) ?*Types.Code {
            return @field(c, n("pcre2_code_copy_with_tables"))(code);
        }

        /// Queries `PCRE2_INFO_*`; `where` must match the selected value type.
        pub inline fn pattern_info(code: ?*const Types.Code, what: u32, where: ?*anyopaque) c_int {
            return @field(c, n("pcre2_pattern_info"))(code, what, where);
        }

        /// Enumerates callouts; a non-zero callback result stops the walk.
        pub inline fn callout_enumerate(
            code: ?*const Types.Code,
            callback: ?*const fn ([*c]Types.CalloutEnumerateBlock, ?*anyopaque) callconv(.c) c_int,
            data: ?*anyopaque,
        ) c_int {
            return @field(c, n("pcre2_callout_enumerate"))(code, callback, data);
        }

        /// Runs the interpreter; return zero means a match with truncated captures.
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

        /// Runs the non-backtracking matcher; results go to `match_data`'s offset vector.
        /// `match_vector` is caller scratch measured in `c_int` entries.
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

        /// Supplies a start offset and options for the next match attempt.
        /// These out-parameters are scalar values, not an offset vector.
        pub inline fn next_match(
            match_data: ?*Types.MatchData,
            pstart_offset: [*c]usize,
            poptions: [*c]u32,
        ) c_int {
            return @field(c, n("pcre2_next_match"))(match_data, pstart_offset, poptions);
        }

        /// Allocates match data with `ovecsize` capture pairs, including group 0.
        pub inline fn match_data_create(
            ovecsize: u32,
            context: ?*Types.GeneralContext,
        ) ?*Types.MatchData {
            return @field(c, n("pcre2_match_data_create"))(ovecsize, context);
        }

        /// Allocates match data sized for `code`'s capture groups.
        pub inline fn match_data_create_from_pattern(
            code: ?*const Types.Code,
            context: ?*Types.GeneralContext,
        ) ?*Types.MatchData {
            return @field(c, n("pcre2_match_data_create_from_pattern"))(code, context);
        }

        /// Frees match data.
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

        /// Returns a named group's number or a negative error.
        pub inline fn substring_number_from_name(code: ?*const Types.Code, name: SPtr) c_int {
            return @field(c, n("pcre2_substring_number_from_name"))(code, name);
        }

        /// Finds a name in the pattern's name table; each output may be null.
        pub inline fn substring_nametable_scan(
            code: ?*const Types.Code,
            name: SPtr,
            first: [*c]SPtr,
            last: [*c]SPtr,
        ) c_int {
            return @field(c, n("pcre2_substring_nametable_scan"))(code, name, first, last);
        }

        /// Copies a named capture to caller-owned storage, including its NUL terminator.
        /// Returns `PCRE2_ERROR_NOMEMORY` if the output buffer is too small.
        pub inline fn substring_copy_byname(
            match_data: ?*Types.MatchData,
            name: SPtr,
            output: [*c]code_unit,
            length: [*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_copy_byname"))(match_data, name, output, length);
        }

        /// Copies a numbered capture to caller-owned storage, including its NUL terminator.
        pub inline fn substring_copy_bynumber(
            match_data: ?*Types.MatchData,
            number: u32,
            output: [*c]code_unit,
            length: [*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_copy_bynumber"))(match_data, number, output, length);
        }

        /// Allocates a named capture copy; release it with `substring_free`.
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

        /// Allocates a NUL-separated list of captured strings and their lengths.
        /// Release the block with `substring_list_free`.
        pub inline fn substring_list_get(
            match_data: ?*Types.MatchData,
            output: [*c][*c][*c]code_unit,
            length: [*c][*c]usize,
        ) c_int {
            return @field(c, n("pcre2_substring_list_get"))(match_data, output, length);
        }

        /// Frees the block returned by `substring_list_get`.
        pub inline fn substring_list_free(list: [*c][*c]code_unit) void {
            @field(c, n("pcre2_substring_list_free"))(list);
        }

        /// Frees substring results; do not pass them to a Zig allocator.
        pub inline fn substring_free(buffer: [*c]code_unit) void {
            @field(c, n("pcre2_substring_free"))(buffer);
        }

        /// Replaces matches in the caller's buffer and returns the substitution count.
        /// The output length is written through its out-parameter.
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

        /// Allocates a serialized byte block; release it with `serialize_free`.
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

        /// Decodes up to `number_of_codes`; the caller owns each returned pattern.
        /// Release decoded patterns with `code_free`.
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

        /// Returns a stream's pattern count or a negative error code.
        pub inline fn serialize_get_number_of_codes(bytes: [*c]const u8) i32 {
            return @field(c, n("pcre2_serialize_get_number_of_codes"))(bytes);
        }

        pub inline fn serialize_free(bytes: [*c]u8) void {
            @field(c, n("pcre2_serialize_free"))(bytes);
        }

        /// Converts a glob or POSIX pattern into caller-owned text.
        /// Release it with `converted_pattern_free`.
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

        /// Creates a general context; null callbacks use `malloc` and `free`.
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

        /// Sets the newline convention used by compilation and matching.
        pub inline fn set_newline(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_newline"))(context, value);
        }

        /// Sets whether `\R` matches Unicode newlines or CR, LF, and CRLF.
        pub inline fn set_bsr(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_bsr"))(context, value);
        }

        /// Sets the compiler's parenthesis nesting limit.
        pub inline fn set_parens_nest_limit(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_parens_nest_limit"))(context, value);
        }

        /// Sets `PCRE2_OPTIMIZE_*` options.
        pub inline fn set_optimize(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_optimize"))(context, value);
        }

        /// Adds option bits to every pattern compiled with this context.
        pub inline fn set_compile_extra_options(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_compile_extra_options"))(context, value);
        }

        /// Sets the maximum variable-length lookbehind.
        pub inline fn set_max_varlookbehind(context: ?*Types.CompileContext, value: u32) c_int {
            return @field(c, n("pcre2_set_max_varlookbehind"))(context, value);
        }

        /// Uses these 256 bytes instead of character tables from the process locale.
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

        /// Sets the character that escapes the next character in a glob.
        pub inline fn set_glob_escape(context: ?*Types.ConvertContext, value: u32) c_int {
            return @field(c, n("pcre2_set_glob_escape"))(context, value);
        }

        /// Sets a glob separator with `PCRE2_GLOBSEP_*`.
        pub inline fn set_glob_separator(context: ?*Types.ConvertContext, value: u32) c_int {
            return @field(c, n("pcre2_set_glob_separator"))(context, value);
        }

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

        /// Sets the offset at which `PCRE2_USE_OFFSET_LIMIT` applies.
        pub inline fn set_offset_limit(context: ?*Types.MatchContext, value: usize) c_int {
            return @field(c, n("pcre2_set_offset_limit"))(context, value);
        }

        /// Sets the deprecated recursion limit; PCRE2 may reject unsupported values.
        pub inline fn set_recursion_limit(context: ?*Types.MatchContext, value: u32) c_int {
            return @field(c, n("pcre2_set_recursion_limit"))(context, value);
        }

        /// Sets the recursion-frame allocator; upstream currently ignores this value.
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

        /// Requests JIT compilation; this build returns `PCRE2_ERROR_JIT_BADOPTION`.
        pub inline fn jit_compile(code: ?*Types.Code, options: u32) c_int {
            return @field(c, n("pcre2_jit_compile"))(code, options);
        }

        /// Runs JIT matching or returns `PCRE2_ERROR_JIT_BADOPTION` in this build.
        /// There is no fallback to the interpreted matcher.
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

        /// Assigns the JIT stack callback used by match attempts.
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

        /// Builds locale character tables; release them with `maketables_free`.
        /// Returns null if allocation fails.
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
