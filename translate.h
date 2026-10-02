/*
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

#endif /* FOUNDATION_PCRE2_TRANSLATE_H */