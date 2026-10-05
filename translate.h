/* SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
 * Copyright (c) 2026 the contributors to this fork.
 *
 * The SPDX line above names the grant for this file; see FORK-LICENSE.md.
 * translate.h - the header the bundled translation is made from.
 *
 * `zig translate-c` reads exactly one header and exposes every declaration it
 * can see to Zig as the module `c`, which `zig/root.zig` imports as
 * `pub const c`. PCRE2's public API is one header for the width-neutral core
 * plus, for the POSIX wrapper, a second one; this file names only the first,
 * because the facade published here is the `pcre2_8*` API and the
 * `-fsys=pcre2-8` mode translates the *installed* `<pcre2.h>` and has to arrive
 * at the same surface. `src/pcre2posix.c` is still built and installed as the
 * separate upstream artifact `pcre2-posix` with its own `pcre2posix.h`; that
 * wrapper is upstream's POSIX emulation, not the PCRE2 API, and nothing here
 * binds it.
 *
 * Which front end reads this file is the target's, and `aggregateRoute` in
 * build.zig says why, in full. Where the translator's own preprocessor can
 * read the target's C library it reads this file as it stands; where it
 * cannot - twelve of the fifty-three targets the published matrix builds,
 * named one by one in `preprocessedAggregate` - build.zig runs the target's
 * own C preprocessor over this file first, `zig cc -E -dD` with the same
 * `-target`, the same `-D` values and the same include path as the C core,
 * and translates what that produced. Either way what the translator reads is
 * this repository's own 10.49 header as the compiler for this target expands
 * it, not a second description of it.
 *
 * Three declarations are configured here rather than in this file. The two
 * macros are configured on whichever line reads this file for the target: on
 * the preprocessing line where there is one, because `-dD` keeps the `#define`
 * lines in the output the translator parses, and on the translation line where
 * there is not, and putting them on both would define each of them twice. The
 * two typedefs are here on every route, because nothing else declares them.
 *
 * 1. PCRE2_CODE_UNIT_WIDTH.
 *
 *    src/pcre2.h.generic:1057-1059 hard-errors with
 *    `#error PCRE2_CODE_UNIT_WIDTH must be defined before including pcre2.h.`
 *    unless the width is defined before the header is read. The value that goes
 *    with a given archive is not a property of the header: it is the value the
 *    library was compiled with, because `PCRE2_SUFFIX(a)` becomes
 *    `PCRE2_GLUE(a, PCRE2_CODE_UNIT_WIDTH)` (src/pcre2.h.generic:1064) and the
 *    name it produces is the symbol the archive defines. build.zig passes the
 *    identical `-DPCRE2_CODE_UNIT_WIDTH=8` on the C core's own compile line and
 *    on the preprocessing line, so the archive and its translation are the same
 *    configuration by construction rather than by two edits that have to be
 *    kept in step.
 *
 *    The guard is `#ifndef` so that an external `-D` of the same macro, from a
 *    consumer's own build, wins instead of colliding.
 *
 * 2. PCRE2_STATIC.
 *
 *    src/pcre2.h.generic:56-59 selects `extern __declspec(dllimport)` for the
 *    whole API when `_WIN32` is defined and `PCRE2_STATIC` is not. Against a
 *    static archive that declaration is wrong and the link fails; against a DLL
 *    it is required. build.zig defines it on that line exactly when it defines
 *    it on the C compile line (`-DPCRE2_STATIC` for the static linkage, nothing
 *    for the dynamic one), so a Windows build cannot end up binding a static
 *    archive through an import declaration.
 *
 * 3. `__int128_t` and `__uint128_t`.
 *
 *    These two names belong to the compiler rather than to a header: Clang
 *    declares them next to the `__int128` primitive it provides, and no header
 *    declares them, so a header that spells one reaches a name the
 *    preprocessed text never defines. That is what happens on
 *    `aarch64-netbsd` and `aarch64_be-netbsd`, where a NetBSD header in the
 *    chain `src/pcre2.h.generic:87-89` opens spells `__ALIGNBYTES` through
 *    `__int128_t` - `generic-netbsd/sys/param.h:290` is
 *    `#define ALIGNBYTES __ALIGNBYTES`, and that value is the target's
 *    `machine/param.h`. `-dD` keeps the spelling and the translated Zig comes
 *    out naming an identifier nothing in it declares:
 *    `pub const __ALIGNBYTES = __helpers.sizeof(__int128_t) - @as(c_int, 1);`
 *    (`local://foundation-cross-test-corrected-pcre2-aarch64-netbsd.log:6-8`,
 *    and the same one error on `aarch64_be-netbsd`). `x86_64-netbsd` builds
 *    today without any of this, and every 32-bit target leaves the guard below
 *    false, so the declaration is written exactly where the compiler reports
 *    that the target has the type.
 *
 *    Restating the two typedefs here is what carries the declaration into the
 *    file the translator reads. Nothing about the types is invented: `__int128`
 *    is the target's own primitive, and the guard is the compiler's own
 *    statement that this target has it, because Clang defines
 *    `__SIZEOF_INT128__` exactly when `TI.hasInt128Type()` holds for the target
 *    (`clang/lib/Frontend/InitPreprocessor.cpp:1173-1174` in upstream LLVM). A
 *    target without the extension declares neither name, and C permits a
 *    typedef to be restated for the type it already denotes, so a target
 *    whose headers declare these themselves ends on the same declaration.
 *
 * Nothing here adds or removes an upstream declaration: the file is a macro
 * prelude, one pair of typedefs the compiler already provides, and one
 * include. Every macro value is upstream's own and every type is the
 * compiler's own.
 */

#ifndef FOUNDATION_PCRE2_TRANSLATE_H
#define FOUNDATION_PCRE2_TRANSLATE_H

/* Matches the PCRE2_CODE_UNIT_WIDTH build.zig puts on the C core's compile
 * line and on the line that pre-processes this file. 8 is the width the facade
 * publishes; see the -Dcode-unit-width help text for the other two. */
#ifndef PCRE2_CODE_UNIT_WIDTH
#define PCRE2_CODE_UNIT_WIDTH 8
#endif

/* The compiler's own typedefs for its 128-bit integer extension. No header
 * declares them, so a C library header that spells one reaches a name the
 * translator would otherwise never see declared; restating them here is what
 * puts the declaration into the file `zig translate-c` reads. The guard is the
 * compiler's own capability macro, so a target without __int128 declares
 * neither. See item 3 of the comment above. */
#if defined(__SIZEOF_INT128__)
typedef __int128 __int128_t;
typedef unsigned __int128 __uint128_t;
#endif

/* Quoted form on purpose: this is the repository's own header, and it is found
 * on the include path build.zig puts on whichever line reads this file for
 * the target - the preprocessing line, or the translation line on the route
 * where Aro reads it for itself - which carries the addWriteFiles copy of
 * src/pcre2.h.generic that the C core was compiled with. Reading the copy and
 * not the .generic keeps the translated declarations and the compiled
 * archive from being two revisions. The `-fsys=pcre2-8` mode does not use
 * this file at all: build.zig generates a wrapper that includes <pcre2.h> by
 * angle brackets, so the translated header is the one installed next to the
 * library that gets linked. */
#include "pcre2.h"

/* The POSIX wrapper's own header, for the 8-bit width only.
 *
 * `src/pcre2posix.h` is upstream's second public header, and its declarations
 * belong to a second artifact: `pcre2_regcomp`, `pcre2_regerror`, `pcre2_regexec`
 * and `pcre2_regfree` plus `regex_t` and `regmatch_t` are what
 * `src/pcre2posix.c` defines and what `libpcre2-posix` exports. A translation
 * that read only `pcre2.h` could never see them, so `zig/posix.zig` had no
 * declaration to find and `pcre2.Posix` stayed unavailable however the facade was
 * built. Naming it here rather than as a second translate-c input keeps both
 * headers in one `c` namespace from one translation step, which is what lets that
 * file answer `@hasDecl` on the real declarations rather than on a hand-written
 * list.
 *
 * The guard is the width, and it is the same width the wrapper exists for: only
 * the 8-bit library is built with a POSIX wrapper, because `regexec` takes a
 * `char *` subject and `regmatch_t::rm_so` counts bytes, so a 16- or 32-bit
 * wrapper would reinterpret every subject byte as a wide code unit. A 16- or
 * 32-bit translation therefore names no wrapper symbols, which is right: this
 * build defines none.
 *
 * `PCRE2POSIX_SHARED` is not defined here for the same reason it is not defined
 * on the translation line in build.zig: `-dD` would dump it here and build.zig
 * would define it again. `src/pcre2posix.h:128-136` reads it only under `_WIN32`,
 * to choose `extern __declspec(dllimport)` over a plain `extern`, so a Windows
 * translation has to carry whichever one matches the library the facade will
 * bind - and on a non-Windows target the macro is never read. */
#if PCRE2_CODE_UNIT_WIDTH == 8
#include "pcre2posix.h"
#endif

/* ---------------------------------------------------------------------------
 * The width as a Zig declaration, and the width-suffixed spellings.
 * ------------------------------------------------------------------------ */

/* `pcre2.h` never publishes `PCRE2_CODE_UNIT_WIDTH` as anything a translator
 * can read back. `zig/widthed.zig` resolves it, through the typedef below, to
 * pick the width the facade speaks, and on the preprocessing route the name
 * itself also reaches the translator because `zig cc -E -dD` keeps the
 * `#define` line beside the text it expanded
 * (`local://foundation-cross-test-pcre2-x86-windows-translate-preprocessed.log:1579`:
 * `pub const PCRE2_CODE_UNIT_WIDTH = @as(c_int, 8);`). On the Aro route there is
 * no such observation, so this file does not depend on one.
 *
 * `runtime/library.zig` resolved it as well, and does not any more. The
 * descriptor now requires every symbol this translation routed, all three
 * widths included, so it settles nothing per width and has no width to read.
 * What still reads the width is the typed facade, and the typedef below is
 * what it reads it from.
 *
 * An array type whose size is the macro is the route-independent spelling: Aro
 * always emits an array type as a real declaration, and `@sizeOf` on it is the
 * width. Nothing declares this name in C, no C source includes this file, and no
 * C compiler ever sees it - it is read only by `zig translate-c`. */
typedef char pcre2_translate_width[PCRE2_CODE_UNIT_WIDTH];

/* The root-level aliases, spelled out.
 *
 * `src/pcre2.h.generic:1044-1054` pastes the width onto each name with the
 * token-pasting operator `##`:
 *
 *     #define pcre2_compile  PCRE2_SUFFIX(pcre2_compile_)
 *
 * A preprocessor resolves that to `pcre2_compile_8` and a C compiler sees a
 * function. A translator does not evaluate `##`, so it records the alias as
 * `pcre2_compile = pcre2_compile_` and then fails to resolve the right-hand
 * side, arriving at
 *
 *     pub const pcre2_compile = @compileError(
 *         "unable to translate macro: undefined identifier `pcre2_compile_`");
 *
 * for every one of the 97 aliases at `src/pcre2.h.generic:1044-1054` and
 * `:1276-1300` (`local://foundation-cross-test-pcre2-x86-windows-translate-preprocessed.log:2816-2900`).
 *
 * Each is therefore undefined and redefined here as the literal name for the
 * width this build selected, which is what the preprocessor would have
 * produced. One block covers all three widths and the `#if` picks the one, so
 * this file stays width-independent and `build.zig` still passes the identical
 * `-DPCRE2_CODE_UNIT_WIDTH` to this line and to the C compile line.
 *
 * The two names that only exist for backwards compatibility
 * (`pcre2_set_recursion_limit`, `pcre2_set_recursion_memory_management`,
 * `src/pcre2.h.generic:1055-1056`) are in this list with the rest, because
 * upstream declares them here too.
 */

/* clang-format off */
#undef pcre2_code
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_code pcre2_code_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_code pcre2_code_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_code pcre2_code_32
#endif
#undef pcre2_jit_callback
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_jit_callback pcre2_jit_callback_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_jit_callback pcre2_jit_callback_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_jit_callback pcre2_jit_callback_32
#endif
#undef pcre2_jit_stack
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_jit_stack pcre2_jit_stack_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_jit_stack pcre2_jit_stack_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_jit_stack pcre2_jit_stack_32
#endif
#undef pcre2_real_code
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_real_code pcre2_real_code_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_real_code pcre2_real_code_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_real_code pcre2_real_code_32
#endif
#undef pcre2_real_general_context
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_real_general_context pcre2_real_general_context_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_real_general_context pcre2_real_general_context_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_real_general_context pcre2_real_general_context_32
#endif
#undef pcre2_real_compile_context
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_real_compile_context pcre2_real_compile_context_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_real_compile_context pcre2_real_compile_context_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_real_compile_context pcre2_real_compile_context_32
#endif
#undef pcre2_real_convert_context
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_real_convert_context pcre2_real_convert_context_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_real_convert_context pcre2_real_convert_context_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_real_convert_context pcre2_real_convert_context_32
#endif
#undef pcre2_real_match_context
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_real_match_context pcre2_real_match_context_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_real_match_context pcre2_real_match_context_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_real_match_context pcre2_real_match_context_32
#endif
#undef pcre2_real_jit_stack
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_real_jit_stack pcre2_real_jit_stack_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_real_jit_stack pcre2_real_jit_stack_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_real_jit_stack pcre2_real_jit_stack_32
#endif
#undef pcre2_real_match_data
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_real_match_data pcre2_real_match_data_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_real_match_data pcre2_real_match_data_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_real_match_data pcre2_real_match_data_32
#endif
#undef pcre2_callout_block
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_callout_block pcre2_callout_block_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_callout_block pcre2_callout_block_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_callout_block pcre2_callout_block_32
#endif
#undef pcre2_callout_enumerate_block
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_callout_enumerate_block pcre2_callout_enumerate_block_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_callout_enumerate_block pcre2_callout_enumerate_block_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_callout_enumerate_block pcre2_callout_enumerate_block_32
#endif
#undef pcre2_substitute_callout_block
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substitute_callout_block pcre2_substitute_callout_block_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substitute_callout_block pcre2_substitute_callout_block_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substitute_callout_block pcre2_substitute_callout_block_32
#endif
#undef pcre2_general_context
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_general_context pcre2_general_context_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_general_context pcre2_general_context_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_general_context pcre2_general_context_32
#endif
#undef pcre2_compile_context
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_compile_context pcre2_compile_context_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_compile_context pcre2_compile_context_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_compile_context pcre2_compile_context_32
#endif
#undef pcre2_convert_context
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_convert_context pcre2_convert_context_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_convert_context pcre2_convert_context_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_convert_context pcre2_convert_context_32
#endif
#undef pcre2_match_context
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_match_context pcre2_match_context_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_match_context pcre2_match_context_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_match_context pcre2_match_context_32
#endif
#undef pcre2_match_data
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_match_data pcre2_match_data_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_match_data pcre2_match_data_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_match_data pcre2_match_data_32
#endif
#undef pcre2_callout_enumerate
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_callout_enumerate pcre2_callout_enumerate_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_callout_enumerate pcre2_callout_enumerate_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_callout_enumerate pcre2_callout_enumerate_32
#endif
#undef pcre2_code_copy
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_code_copy pcre2_code_copy_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_code_copy pcre2_code_copy_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_code_copy pcre2_code_copy_32
#endif
#undef pcre2_code_copy_with_tables
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_code_copy_with_tables pcre2_code_copy_with_tables_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_code_copy_with_tables pcre2_code_copy_with_tables_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_code_copy_with_tables pcre2_code_copy_with_tables_32
#endif
#undef pcre2_code_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_code_free pcre2_code_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_code_free pcre2_code_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_code_free pcre2_code_free_32
#endif
#undef pcre2_compile
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_compile pcre2_compile_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_compile pcre2_compile_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_compile pcre2_compile_32
#endif
#undef pcre2_compile_context_copy
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_compile_context_copy pcre2_compile_context_copy_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_compile_context_copy pcre2_compile_context_copy_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_compile_context_copy pcre2_compile_context_copy_32
#endif
#undef pcre2_compile_context_create
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_compile_context_create pcre2_compile_context_create_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_compile_context_create pcre2_compile_context_create_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_compile_context_create pcre2_compile_context_create_32
#endif
#undef pcre2_compile_context_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_compile_context_free pcre2_compile_context_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_compile_context_free pcre2_compile_context_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_compile_context_free pcre2_compile_context_free_32
#endif
#undef pcre2_config
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_config pcre2_config_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_config pcre2_config_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_config pcre2_config_32
#endif
#undef pcre2_convert_context_copy
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_convert_context_copy pcre2_convert_context_copy_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_convert_context_copy pcre2_convert_context_copy_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_convert_context_copy pcre2_convert_context_copy_32
#endif
#undef pcre2_convert_context_create
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_convert_context_create pcre2_convert_context_create_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_convert_context_create pcre2_convert_context_create_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_convert_context_create pcre2_convert_context_create_32
#endif
#undef pcre2_convert_context_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_convert_context_free pcre2_convert_context_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_convert_context_free pcre2_convert_context_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_convert_context_free pcre2_convert_context_free_32
#endif
#undef pcre2_converted_pattern_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_converted_pattern_free pcre2_converted_pattern_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_converted_pattern_free pcre2_converted_pattern_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_converted_pattern_free pcre2_converted_pattern_free_32
#endif
#undef pcre2_dfa_match
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_dfa_match pcre2_dfa_match_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_dfa_match pcre2_dfa_match_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_dfa_match pcre2_dfa_match_32
#endif
#undef pcre2_general_context_copy
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_general_context_copy pcre2_general_context_copy_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_general_context_copy pcre2_general_context_copy_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_general_context_copy pcre2_general_context_copy_32
#endif
#undef pcre2_general_context_create
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_general_context_create pcre2_general_context_create_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_general_context_create pcre2_general_context_create_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_general_context_create pcre2_general_context_create_32
#endif
#undef pcre2_general_context_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_general_context_free pcre2_general_context_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_general_context_free pcre2_general_context_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_general_context_free pcre2_general_context_free_32
#endif
#undef pcre2_get_error_message
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_get_error_message pcre2_get_error_message_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_get_error_message pcre2_get_error_message_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_get_error_message pcre2_get_error_message_32
#endif
#undef pcre2_get_mark
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_get_mark pcre2_get_mark_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_get_mark pcre2_get_mark_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_get_mark pcre2_get_mark_32
#endif
#undef pcre2_get_match_data_heapframes_size
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_get_match_data_heapframes_size pcre2_get_match_data_heapframes_size_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_get_match_data_heapframes_size pcre2_get_match_data_heapframes_size_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_get_match_data_heapframes_size pcre2_get_match_data_heapframes_size_32
#endif
#undef pcre2_get_match_data_size
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_get_match_data_size pcre2_get_match_data_size_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_get_match_data_size pcre2_get_match_data_size_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_get_match_data_size pcre2_get_match_data_size_32
#endif
#undef pcre2_get_ovector_pointer
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_get_ovector_pointer pcre2_get_ovector_pointer_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_get_ovector_pointer pcre2_get_ovector_pointer_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_get_ovector_pointer pcre2_get_ovector_pointer_32
#endif
#undef pcre2_get_ovector_count
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_get_ovector_count pcre2_get_ovector_count_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_get_ovector_count pcre2_get_ovector_count_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_get_ovector_count pcre2_get_ovector_count_32
#endif
#undef pcre2_get_startchar
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_get_startchar pcre2_get_startchar_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_get_startchar pcre2_get_startchar_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_get_startchar pcre2_get_startchar_32
#endif
#undef pcre2_jit_compile
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_jit_compile pcre2_jit_compile_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_jit_compile pcre2_jit_compile_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_jit_compile pcre2_jit_compile_32
#endif
#undef pcre2_jit_match
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_jit_match pcre2_jit_match_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_jit_match pcre2_jit_match_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_jit_match pcre2_jit_match_32
#endif
#undef pcre2_jit_free_unused_memory
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_jit_free_unused_memory pcre2_jit_free_unused_memory_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_jit_free_unused_memory pcre2_jit_free_unused_memory_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_jit_free_unused_memory pcre2_jit_free_unused_memory_32
#endif
#undef pcre2_jit_stack_assign
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_jit_stack_assign pcre2_jit_stack_assign_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_jit_stack_assign pcre2_jit_stack_assign_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_jit_stack_assign pcre2_jit_stack_assign_32
#endif
#undef pcre2_jit_stack_create
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_jit_stack_create pcre2_jit_stack_create_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_jit_stack_create pcre2_jit_stack_create_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_jit_stack_create pcre2_jit_stack_create_32
#endif
#undef pcre2_jit_stack_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_jit_stack_free pcre2_jit_stack_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_jit_stack_free pcre2_jit_stack_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_jit_stack_free pcre2_jit_stack_free_32
#endif
#undef pcre2_maketables
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_maketables pcre2_maketables_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_maketables pcre2_maketables_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_maketables pcre2_maketables_32
#endif
#undef pcre2_maketables_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_maketables_free pcre2_maketables_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_maketables_free pcre2_maketables_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_maketables_free pcre2_maketables_free_32
#endif
#undef pcre2_match
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_match pcre2_match_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_match pcre2_match_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_match pcre2_match_32
#endif
#undef pcre2_match_context_copy
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_match_context_copy pcre2_match_context_copy_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_match_context_copy pcre2_match_context_copy_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_match_context_copy pcre2_match_context_copy_32
#endif
#undef pcre2_match_context_create
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_match_context_create pcre2_match_context_create_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_match_context_create pcre2_match_context_create_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_match_context_create pcre2_match_context_create_32
#endif
#undef pcre2_match_context_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_match_context_free pcre2_match_context_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_match_context_free pcre2_match_context_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_match_context_free pcre2_match_context_free_32
#endif
#undef pcre2_match_data_create
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_match_data_create pcre2_match_data_create_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_match_data_create pcre2_match_data_create_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_match_data_create pcre2_match_data_create_32
#endif
#undef pcre2_match_data_create_from_pattern
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_match_data_create_from_pattern pcre2_match_data_create_from_pattern_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_match_data_create_from_pattern pcre2_match_data_create_from_pattern_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_match_data_create_from_pattern pcre2_match_data_create_from_pattern_32
#endif
#undef pcre2_match_data_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_match_data_free pcre2_match_data_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_match_data_free pcre2_match_data_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_match_data_free pcre2_match_data_free_32
#endif
#undef pcre2_next_match
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_next_match pcre2_next_match_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_next_match pcre2_next_match_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_next_match pcre2_next_match_32
#endif
#undef pcre2_pattern_convert
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_pattern_convert pcre2_pattern_convert_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_pattern_convert pcre2_pattern_convert_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_pattern_convert pcre2_pattern_convert_32
#endif
#undef pcre2_pattern_info
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_pattern_info pcre2_pattern_info_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_pattern_info pcre2_pattern_info_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_pattern_info pcre2_pattern_info_32
#endif
#undef pcre2_serialize_decode
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_serialize_decode pcre2_serialize_decode_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_serialize_decode pcre2_serialize_decode_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_serialize_decode pcre2_serialize_decode_32
#endif
#undef pcre2_serialize_encode
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_serialize_encode pcre2_serialize_encode_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_serialize_encode pcre2_serialize_encode_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_serialize_encode pcre2_serialize_encode_32
#endif
#undef pcre2_serialize_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_serialize_free pcre2_serialize_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_serialize_free pcre2_serialize_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_serialize_free pcre2_serialize_free_32
#endif
#undef pcre2_serialize_get_number_of_codes
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_serialize_get_number_of_codes pcre2_serialize_get_number_of_codes_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_serialize_get_number_of_codes pcre2_serialize_get_number_of_codes_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_serialize_get_number_of_codes pcre2_serialize_get_number_of_codes_32
#endif
#undef pcre2_set_bsr
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_bsr pcre2_set_bsr_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_bsr pcre2_set_bsr_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_bsr pcre2_set_bsr_32
#endif
#undef pcre2_set_callout
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_callout pcre2_set_callout_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_callout pcre2_set_callout_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_callout pcre2_set_callout_32
#endif
#undef pcre2_set_character_tables
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_character_tables pcre2_set_character_tables_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_character_tables pcre2_set_character_tables_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_character_tables pcre2_set_character_tables_32
#endif
#undef pcre2_set_compile_extra_options
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_compile_extra_options pcre2_set_compile_extra_options_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_compile_extra_options pcre2_set_compile_extra_options_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_compile_extra_options pcre2_set_compile_extra_options_32
#endif
#undef pcre2_set_compile_recursion_guard
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_compile_recursion_guard pcre2_set_compile_recursion_guard_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_compile_recursion_guard pcre2_set_compile_recursion_guard_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_compile_recursion_guard pcre2_set_compile_recursion_guard_32
#endif
#undef pcre2_set_depth_limit
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_depth_limit pcre2_set_depth_limit_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_depth_limit pcre2_set_depth_limit_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_depth_limit pcre2_set_depth_limit_32
#endif
#undef pcre2_set_glob_escape
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_glob_escape pcre2_set_glob_escape_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_glob_escape pcre2_set_glob_escape_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_glob_escape pcre2_set_glob_escape_32
#endif
#undef pcre2_set_glob_separator
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_glob_separator pcre2_set_glob_separator_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_glob_separator pcre2_set_glob_separator_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_glob_separator pcre2_set_glob_separator_32
#endif
#undef pcre2_set_heap_limit
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_heap_limit pcre2_set_heap_limit_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_heap_limit pcre2_set_heap_limit_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_heap_limit pcre2_set_heap_limit_32
#endif
#undef pcre2_set_match_limit
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_match_limit pcre2_set_match_limit_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_match_limit pcre2_set_match_limit_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_match_limit pcre2_set_match_limit_32
#endif
#undef pcre2_set_max_varlookbehind
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_max_varlookbehind pcre2_set_max_varlookbehind_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_max_varlookbehind pcre2_set_max_varlookbehind_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_max_varlookbehind pcre2_set_max_varlookbehind_32
#endif
#undef pcre2_set_max_pattern_length
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_max_pattern_length pcre2_set_max_pattern_length_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_max_pattern_length pcre2_set_max_pattern_length_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_max_pattern_length pcre2_set_max_pattern_length_32
#endif
#undef pcre2_set_max_pattern_compiled_length
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_max_pattern_compiled_length pcre2_set_max_pattern_compiled_length_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_max_pattern_compiled_length pcre2_set_max_pattern_compiled_length_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_max_pattern_compiled_length pcre2_set_max_pattern_compiled_length_32
#endif
#undef pcre2_set_newline
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_newline pcre2_set_newline_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_newline pcre2_set_newline_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_newline pcre2_set_newline_32
#endif
#undef pcre2_set_parens_nest_limit
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_parens_nest_limit pcre2_set_parens_nest_limit_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_parens_nest_limit pcre2_set_parens_nest_limit_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_parens_nest_limit pcre2_set_parens_nest_limit_32
#endif
#undef pcre2_set_offset_limit
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_offset_limit pcre2_set_offset_limit_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_offset_limit pcre2_set_offset_limit_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_offset_limit pcre2_set_offset_limit_32
#endif
#undef pcre2_set_optimize
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_optimize pcre2_set_optimize_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_optimize pcre2_set_optimize_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_optimize pcre2_set_optimize_32
#endif
#undef pcre2_set_substitute_callout
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_substitute_callout pcre2_set_substitute_callout_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_substitute_callout pcre2_set_substitute_callout_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_substitute_callout pcre2_set_substitute_callout_32
#endif
#undef pcre2_set_substitute_case_callout
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_substitute_case_callout pcre2_set_substitute_case_callout_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_substitute_case_callout pcre2_set_substitute_case_callout_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_substitute_case_callout pcre2_set_substitute_case_callout_32
#endif
#undef pcre2_substitute
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substitute pcre2_substitute_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substitute pcre2_substitute_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substitute pcre2_substitute_32
#endif
#undef pcre2_substring_copy_byname
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_copy_byname pcre2_substring_copy_byname_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_copy_byname pcre2_substring_copy_byname_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_copy_byname pcre2_substring_copy_byname_32
#endif
#undef pcre2_substring_copy_bynumber
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_copy_bynumber pcre2_substring_copy_bynumber_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_copy_bynumber pcre2_substring_copy_bynumber_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_copy_bynumber pcre2_substring_copy_bynumber_32
#endif
#undef pcre2_substring_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_free pcre2_substring_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_free pcre2_substring_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_free pcre2_substring_free_32
#endif
#undef pcre2_substring_get_byname
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_get_byname pcre2_substring_get_byname_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_get_byname pcre2_substring_get_byname_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_get_byname pcre2_substring_get_byname_32
#endif
#undef pcre2_substring_get_bynumber
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_get_bynumber pcre2_substring_get_bynumber_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_get_bynumber pcre2_substring_get_bynumber_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_get_bynumber pcre2_substring_get_bynumber_32
#endif
#undef pcre2_substring_length_byname
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_length_byname pcre2_substring_length_byname_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_length_byname pcre2_substring_length_byname_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_length_byname pcre2_substring_length_byname_32
#endif
#undef pcre2_substring_length_bynumber
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_length_bynumber pcre2_substring_length_bynumber_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_length_bynumber pcre2_substring_length_bynumber_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_length_bynumber pcre2_substring_length_bynumber_32
#endif
#undef pcre2_substring_list_get
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_list_get pcre2_substring_list_get_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_list_get pcre2_substring_list_get_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_list_get pcre2_substring_list_get_32
#endif
#undef pcre2_substring_list_free
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_list_free pcre2_substring_list_free_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_list_free pcre2_substring_list_free_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_list_free pcre2_substring_list_free_32
#endif
#undef pcre2_substring_nametable_scan
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_nametable_scan pcre2_substring_nametable_scan_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_nametable_scan pcre2_substring_nametable_scan_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_nametable_scan pcre2_substring_nametable_scan_32
#endif
#undef pcre2_substring_number_from_name
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_substring_number_from_name pcre2_substring_number_from_name_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_substring_number_from_name pcre2_substring_number_from_name_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_substring_number_from_name pcre2_substring_number_from_name_32
#endif
#undef pcre2_set_recursion_limit
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_recursion_limit pcre2_set_recursion_limit_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_recursion_limit pcre2_set_recursion_limit_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_recursion_limit pcre2_set_recursion_limit_32
#endif
#undef pcre2_set_recursion_memory_management
#if PCRE2_CODE_UNIT_WIDTH == 8
#define pcre2_set_recursion_memory_management pcre2_set_recursion_memory_management_8
#endif
#if PCRE2_CODE_UNIT_WIDTH == 16
#define pcre2_set_recursion_memory_management pcre2_set_recursion_memory_management_16
#endif
#if PCRE2_CODE_UNIT_WIDTH == 32
#define pcre2_set_recursion_memory_management pcre2_set_recursion_memory_management_32
#endif

/* clang-format on */

#endif /* FOUNDATION_PCRE2_TRANSLATE_H */
