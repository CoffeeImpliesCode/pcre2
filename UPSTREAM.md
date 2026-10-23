# Upstream

| Field | Value |
|---|---|
| Project | PCRE2, a C library of Perl-compatible regular-expression functions |
| Repository | `https://github.com/PCRE2Project/pcre2.git` |
| Pinned ref | `pcre2-10.49` |
| Pinned commit | `6f9d7c1373262c541324a16a358785b33ef116cf` |
| Library version | `10.49`; `PCRE2_DATE` `2026-09-28` |
| Library licence | `BSD-3-Clause WITH PCRE2-exception` |
| Test-data grant | Public domain |
| Source acquisition | Full clone; upstream Git history retained |
| Source archive SHA-256 | `e2353f82162d1860ebfbce03c227f539285ab8503e4d57617370b824c4fbde11` |
| Integrity inventory | 59 records in `UPSTREAM.sha256`: 58 upstream-owned files and this fork's fixture module |

## Source scope

This Zig 0.17.0 package builds PCRE2 from upstream's `src/` tree and translates upstream's public header. The upstream-owned `src/`, `doc/`, and `testdata/` trees are carried unchanged, except that `testdata/foundation-fixtures.zig` is fork-authored. `LICENCE.md`, `COPYING`, `AUTHORS.md`, `SECURITY.md`, `ChangeLog`, `NEWS`, `SUPPORT-LIFECYCLE.md`, `HACKING`, `INSTALL`, `README`, and the upstream build templates in `.paths` are also upstream files. No upstream source, header, test, licence, or fixture bytes are modified.

The upstream `README.md` is preserved unchanged as `README.upstream.md`; `README.md` is fork-authored and is covered by `FORK-LICENSE.md`. `.gitignore` is the only upstream file edited: the fork appends re-inclusions and removes or narrows none of upstream's entries. Fork-authored files and their grant are listed in `NOTICE.md` and `FORK-LICENSE.md`.

The source was obtained as a full clone of the canonical repository. The archive digest above identifies the deterministic `git archive` stream at the pinned commit. `UPSTREAM.sha256` records the package's selected source, header, licence, and fixture bytes; it is not a signature or a Git object id.

## Files omitted from the fetched package

These upstream paths remain in the clone but are excluded from `build.zig.zon`'s `.paths`: autotools files (`configure.ac`, `configure`, `aclocal.m4`, `m4/`, `Makefile.am`, `Makefile.in`, `depcomp`, `install-sh`, `ltmain.sh`, `missing`, `ar-lib`, `compile`, `config.guess`, `config.sub`, `test-driver`, `maint/`); CMake and Bazel files (`CMakeLists.txt`, `cmake/`, `BUILD.bazel`, `MODULE.bazel`); `vms/`, `patches/`, `RunGrepTest`, `RunTest.bat`, `RunGrepTest.bat`, `perltest.sh`, `NON-AUTOTOOLS-BUILD`, `.editorconfig`, `.gitattributes`, `.gitmodules`, and `deps/`.

`src/pcre2grep.c` is not built because it requires zlib and libbz2. `deps/sljit/` is empty; the lazy `sljit` dependency and `-Dsupport_jit` option are absent, and bundled builds set `SUPPORT_JIT` to zero.

## Upstream licence records

Upstream's attribution and per-path licence scope are in `LICENCE.md`; see `NOTICE.md` for the compact path table and file-specific attribution exceptions. `UPSTREAM.sha256` is the integrity record for the 59 listed files.
