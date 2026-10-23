# NOTICE

## Upstream attribution

PCRE2 is the work of **Philip Hazel** and contributors, with the original API code at the University of Cambridge. Upstream's attribution and licence terms are in `LICENCE.md`.

| Work | Attribution | Upstream record |
|---|---|---|
| Basic library functions | Written by Philip Hazel. Original API code Copyright (c) 1997-2012 University of Cambridge; new API code Copyright (c) 2016-2024 University of Cambridge; Copyright (c) 1997-2007 University of Cambridge and Copyright (c) 2007-2024 Philip Hazel for the whole library | `LICENCE.md` and per-file headers |
| PCRE2 JIT support | Zoltan Herczeg; Copyright (c) 2010-2024 Zoltan Herczeg | `LICENCE.md`; `src/pcre2_jit_compile.c`, `src/pcre2_jit_char_inc.h`, `src/pcre2_jit_simd_inc.h` |
| SLJIT | Zoltan Herczeg; Copyright (c) 2009-2024 Zoltan Herczeg | `LICENCE.md`; `deps/sljit/LICENSE` upstream |
| Other contributions | Copyright retained by each original contributor or their employer; PCRE2 has never required a Contributor Licensing Agreement | `LICENCE.md` |

Upstream's per-file headers give original API years `1997-2012` and new API years `2016-2024`; `LICENCE.md` gives `1997-2007` for the University of Cambridge and `2007-2024` for Philip Hazel. Both statements are retained as upstream wrote them.

## Licence scope

| Path | Licence or grant | Scope |
|---|---|---|
| `src/` except `src/pcre2_jit_compile.c` and its `_inc.h` files, and `doc/` | `BSD-3-Clause WITH PCRE2-exception` | Upstream library source and documentation. Upstream states: "Releases 10.00 and above of PCRE2 are distributed under the terms of the 'BSD' licence… The documentation for PCRE2, supplied in the 'doc' directory, is distributed under the same terms as the software itself" (`LICENCE.md`). |
| `src/pcre2_jit_compile.c`, its `_inc.h` files, and `deps/sljit/` | 2-clause BSD | Upstream states: "the just-in-time compiler… is separately licensed under the '2-clause BSD' licence" and "The code in the `deps/sljit` directory has its own LICENSE file" (`LICENCE.md`). `deps/sljit/` is empty in this checkout; no SLJIT code is shipped. |
| `testdata/`, except `testdata/foundation-fixtures.zig` | Public domain; not copyrighted | Upstream states: "The data in the testdata directory is not copyrighted and is in the public domain" (`LICENCE.md`). |
| Fork-authored files listed below | `BSD-3-Clause WITH PCRE2-exception` | Granted separately in `FORK-LICENSE.md`; copyright is held by the contributors to this fork. |
| `.gitignore` | Upstream's `BSD-3-Clause WITH PCRE2-exception` | This upstream file is appended to by the fork; no upstream entry is removed or narrowed. |
| `README.upstream.md` | Upstream terms | Upstream's `README.md`, preserved unchanged under this name. `README.md` is fork-authored and covered by `FORK-LICENSE.md`. |

Fork-authored paths covered by `FORK-LICENSE.md`: `build.zig`, `build.zig.zon`, `translate.h`, `zig/`, `runtime/`, `tests.zig`, `smoke.zig`, `consumer/`, `cross-test.profile.sh`, `testdata/foundation-fixtures.zig`, `package.nix`, `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, `.envrc`, `README.md`, `README.zig.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md`, `FORK-NOTES.md`, and `CHANGELOG.md`. All upstream files not listed as fork-authored remain under upstream's per-path terms; the fork grants no rights in them.

## Per-file attribution exceptions

| Upstream file | Attribution detail |
|---|---|
| `src/pcre2_chartables.c.dist` | Its generation banner names `src/pcre2_dftables.c`; the generated output has no per-file copyright header. |
| `src/config-cmake.h.in` | Contains `#cmakedefine` lines and has no author, date, or grant in the file; it remains an upstream `src/` file. |
| `src/pcre2test.c` | Uses upstream's "Original code" and "Rewritten code" wording rather than "Original API code" and "New API code"; it is not normalised. |

Of the 47 `src/` files in `UPSTREAM.sha256`, 45 carry the per-file header. The first two rows above are the exceptions; `src/pcre2test.c` carries its variant header.

## Redistribution terms

`LICENCE.md` contains the full upstream licence and PCRE2 exception. Its quoted conditions are:

- "Redistributions of source code must retain the above copyright notices, this list of conditions and the following disclaimer"
- "Redistributions in binary form must reproduce the above copyright notices, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution"
- "Neither the name of the University of Cambridge nor the names of any contributors may be used to endorse or promote products derived from this software without specific prior written permission"

The PCRE2 exception in `LICENCE.md` states:
> The second condition in the BSD licence (covering binary redistributions) does
> not apply all the way down a chain of software. If binary package A includes
> PCRE2, it must respect the condition, but if package B is software that
> includes package A, the condition is not imposed on package B unless it uses
> PCRE2 independently.
