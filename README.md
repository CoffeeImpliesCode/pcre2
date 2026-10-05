<!--
SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
Copyright (c) 2026 the contributors to this fork.
-->

# pcre2 — PCRE2 10.49, from upstream's own C, for Zig and for C

A fork of PCRE2, pinned to tag `pcre2-10.49`, commit
`6f9d7c1373262c541324a16a358785b33ef116cf` of
`https://github.com/PCRE2Project/pcre2.git`. It compiles **upstream's own C
sources**, byte for byte, from the `src/` directory in this tree, and publishes
them two ways: a **Zig package** (`zig/root.zig`, a typed facade over a
translation of upstream's `pcre2.h`, with the whole raw C behind it) and a
**native delivery** (the `pcre2-8` library, the installed `pcre2.h`, the
`pcre2-posix` wrapper, and upstream's `pcre2test`).

What is built is upstream's **full Unicode core with JIT off**, compiled from
the **same explicit source list three times**, once per code-unit width: 31
translation units each — the interpreter, the DFA matcher, the Unicode property
machinery and the compiled-in UCP tables. The three closures go into **one
artifact**, with one name, one soname and one version, because one file is what
a link line can name and what a runtime `load` can open. `-Dcode-unit-width`
chooses which width that artifact is *called* and which one the typed facade
speaks; it does not choose what the artifact contains. Nothing of the engine is
reimplemented or reconfigured, nothing is downloaded at build time, and no
upstream C source, header, test, licence text or fixture byte is modified.

| | |
|---|---|
| Library licence | **BSD-3-Clause WITH PCRE2-exception** (`LICENCE.md:4`) |
| `testdata/` | **not copyrighted; public domain** (`LICENCE.md:14`) |
| JIT sources | present, under upstream's **2-clause BSD** grant, **disabled in this build** |
| Fork-authored files | the same BSD terms, granted in [`FORK-LICENSE.md`](FORK-LICENSE.md) |
| Zig / development environment | 0.16.0 / [`devenv.nix`](devenv.nix) |

**Upstream's own README is preserved byte for byte as
[`README.upstream.md`](README.upstream.md)** — its overview, quickstart, API
summary and platform list are upstream's words. This file is the fork's entry
point: deviations, then the matrix, then consumption. The Zig interface has its
own document, [`README.zig.md`](README.zig.md).

## Current native-source deviations

One upstream file is edited, by appending; one moved, unchanged.

| Upstream file | What this fork did |
|---|---|
| `.gitignore` | upstream's list is kept **verbatim** (`.gitignore:1-128`); the fork appends a comment block and **seven** re-inclusions — `!translate.h`, `!cross-test.profile.sh`, `!/zig/`, `!/tests.zig`, `!/smoke.zig`, `!/consumer/`, `!/testdata/` (`:130-158`). No upstream entry is removed or narrowed. The negations exist because an upstream rule broadening is how a fork's own file goes missing, and a negation cannot re-include a file whose parent directory is excluded |
| `README.md` → `README.upstream.md` | **relocated, not rewritten.** `sha256sum` printed `579446220c54f9b406a6c7b9b2bf155abf699c6e0b6211c7189f3aa1b174246d` for both files immediately before the move, and that is the digest the driver's extraction record names for this commit and this preserved path |

**No other upstream byte is touched.** `UPSTREAM.sha256` pins **59** files — the
compiled `src/*.c` units, the public header, the `config.h` template, the twelve
internal headers, the POSIX wrapper and `pcre2test.c`, `LICENCE.md`, `COPYING`,
`AUTHORS.md`, eight `testdata/` oracle files **and this fork's own fixture
module** — and `sha256sum -c UPSTREAM.sha256` is the check.

**58 of those 59 records are upstream's; the 59th is not, on purpose.**
`UPSTREAM.sha256:27-31` says so in its own header and gives the reason: the
fixture module holds every expected answer the tests compare against, so a
silent edit to it would move the oracle rather than break a build, and hashing
it makes such an edit fail loudly. That is a **change detector for this fork's
own file**, not a claim about upstream. **No upstream byte is at issue**, and
the distinction matters when reading a red line: see the integrity row in the
matrix below.

Present but not compiled: **`src/pcre2grep.c`**, which needs zlib and libbz2,
and **`src/pcre2_jit_test.c`**, upstream's JIT test program, which
`Makefile.am` builds only under `SUPPORT_JIT`. The **JIT** itself is disabled
(`SUPPORT_JIT` 0) but is **not absent**: all six public entry points are
defined and linked, and each answers by refusing —
`PCRE2_ERROR_JIT_BADOPTION` / `_UNSUPPORTED`, `NULL` for
`pcre2_jit_stack_create`. "JIT is off" and "the JIT symbols are missing" are
different claims, and only the first is true
([`README.zig.md`](README.zig.md) § "Build modes").

## Current native-build deviations

The build **extends upstream's own Zig 0.16 graph**; no CMake, autotools,
`configure` or Bazel is used, and those inputs stay in the tree for provenance.

| Deviation | Why |
|---|---|
| **`sljit` dependency and `-Dsupport_jit` removed** | the option resolves the JIT's source from the `deps/sljit` submodule — an **empty directory** here — or from a network `lazyDependency`. Neither is available to a package that compiles its core from its own tree, so the knob is gone rather than left to fail later |
| **`config.h` generated per target** | from upstream's `src/config-cmake.h.in`, every value derived from `target.result` and never from the build machine, so a foreign target gets a `config.h` that describes it |
| **`translate.h`, read by two front ends** | `zig translate-c` parses with Aro, which cannot read every target's C library. The aggregate is read by **Aro alone** on a GNU-libc target and by the target's own `zig cc -E -dD -fno-blocks` first everywhere else. Both routes read the same header with the same two declaration macros ([`FORK-NOTES.md`](FORK-NOTES.md) § 17-20) |
| **`pcre2-posix` at width 8 only** | `regexec` takes a `char *` subject and `rm_so` counts bytes, so a 16- or 32-bit wrapper would reinterpret every subject byte |
| **One artifact, all three widths** | upstream ships `libpcre2-8`, `libpcre2-16` and `libpcre2-32` as three files and `pcre2.h` declares all three widths in one header, so a header consumer sees declarations its `-l` name cannot resolve. The primary artifact is the union of the three genuine width closures — the same source list compiled three times, no byte edited and none omitted — under the one name, soname and version upstream gives the selected width. Upstream's own internal names are width-suffixed for exactly this coexistence (`src/pcre2_internal.h:2196-2200`), so nothing collides |
| **`-Druntime=true`, orthogonal to `-Dlinkage`** | it swaps the translated header for a generated dispatch whose table `pcre2.load` fills through the platform loader. It changes how a call is reached, never what is compiled: the same artifact is built and installed and nothing is linked. All four combinations of linkage and runtime exist, and none of them substitutes one for another |
| **`pcre2posix.c` is in the core as well as in the wrapper** | at width 8 the four POSIX names are exported from the primary's own generated version script, so one provider carries the width library and the wrapper. Upstream's separate `pcre2-posix` artifact is still built, installed and unchanged. Inside the primary those calls are local, so on COFF the object is compiled with `PCRE2_EXP_DECL=extern`: `pcre2posix.c` includes `pcre2.h` but not `pcre2_internal.h` (`src/pcre2_tables.c:50-52` skips it under `PCRE2_PCRE2POSIX`), so without the override the wrapper would import the core entry points from the very DLL that defines them. In the separate artifact the same calls are genuinely imported and stay `dllimport`, which is what upstream's CMake does |
| **upstream's delivered closure restored** | the four upstream programs, `pcre2-config`, the pkg-config metadata, the manual pages and `doc/` are installed again, and libtool sonames and version scripts make a shared build a real `libpcre2-8.so.0` |
| **`pcre2test` as an application** | it defines `PCRE2_CODE_UNIT_WIDTH` itself and links every library the graph built |
| **`-fvisibility=hidden`, `PCRE2_EXPORT` default visibility** | internals stay internal even in a static archive a user links into their own shared library |
| **Default linkage: dynamic on a GNU-libc target, static elsewhere** | derived from the `target.result` of the target **being built**, not from the host, so every `zig build check` cell resolves it from its own target and `wasm32-wasi` is a static archive; the same value drives the `PCRE2_STATIC` macro, so the decoration and the archive are one fact. `-Dlinkage=static\|dynamic` overrides it for every cell unchanged, and a cell whose OS has no dynamic linker is **refused by name** — never built as static instead, never left out of the matrix |
| **Nix packaging** | `package.nix` (one injected derivation used by both entry points), `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc`: no sibling import, no host path, no download, and a dev shell that holds tools rather than the SDK |
| **Fork licence grant** | [`FORK-LICENSE.md`](FORK-LICENSE.md) records the owner's grant for fork-authored files; upstream's terms, the data terms and both per-file exceptions are unchanged |

**History.** [`CHANGELOG.md`](CHANGELOG.md); this wave is
§ [Foundation contract migration — 2026-10-04](CHANGELOG.md#foundation-contract-migration--2026-10-04).
[`UPSTREAM.md`](UPSTREAM.md) states the pin, what is compiled with which
switches, what was removed, and the sync procedure.

## Current build/run/test matrix

**Observed** means a gate ran and its receipt is named; **pending** means the
change landed and no gate has looked at it. Every receipt describes the tree
**as of its own date** — the 2026-10-02 rows predate the 2026-10-03 API
alignment and this wave, so they are evidence about the same package and not
about the current bytes. This document records no result of its own; the driver
owns every verification field, and the one current table is
[`README.zig.md`](README.zig.md) § "Verification status".

**One applied fix postdates every receipt in this table.** The translated-header
generation now resolves its host/target selection and establishes the selected
platform configuration **before** it calls `createModule`, rather than reading
them afterwards. The seam is `build.zig:1381-1388` — the runtime branch takes
`graph.createModule(b, translate_c, …)` and the linked branch
`translate_c.createModule()` — reached through `runtime/graph.zig:294`
(`createModule`) and `runtime/graph.zig:365-379` (`generateDispatch`, where the
generator's host target is chosen). An earlier staged arrangement of those steps
was itself wrong and has been replaced by the correct one. **No receipt re-runs
pcre2 after this fix**, so every count below predates it and nothing here is
re-gated by it. No native byte, header, test, fixture, licence or upstream file
changed with it.

| Configuration | Command | State |
|---|---|---|
| Bundled 8-bit, **linked**, host `x86_64-linux-gnu` | `zig build smoke test` | **observed** 2026-10-04: `Build Summary: 21/21 steps succeeded; 24/24 tests passed`, `smoke success`; the smoke prints three captures at hand-worked offsets and two lines about the failed attempt. Receipt `local://foundation-contract-pcre2-real-UTF8-bytes-and-unset-optional-capture-full-gate.log` |
| public consumer package, out of tree, linked | `cd consumer && zig build run -Druntime=false -Dlinkage=<static\|dynamic>` | **observed 2026-10-04, and the two linkages disagree.** Static printed `linked against 10.49 2026-09-28` with `Build Summary: 17/17 steps succeeded` (`local://foundation-resumed-pcre2-standalone-linked-static.json`). Shared **exited 0** with the same step count, the same captures and the same hand-worked offsets, while the loader answered from `/lib64/libpcre2-8.so.0` — `no version information available`, and the program printed `linked against 10.45 2025-02-05` (`local://foundation-resumed-pcre2-standalone-linked-dynamic.json`). **Cause:** the published `pcre2` module carried the install tree's `$ORIGIN/../lib`, which resolves nothing out of a build cache, so the loader fell through to the host's own library under the same soname. **Correction landed, pending** — the published module now carries the build-cache entry, and nothing installed is built from it. Detail in [`README.zig.md`](README.zig.md) § "Verification status" |
| the same, static linkage | `zig build install -Dlinkage=static --prefix <p>`, `… test smoke` | **pending**; no static run of the current tree has a receipt |
| `-Dlinkage=dynamic` / `-Dlinkage=static` × Debug, ReleaseSafe, ReleaseFast, ReleaseSmall | `zig build install -Dlinkage=… -Doptimize=… --prefix <p>` | **pending** for the current tree |
| 16-bit / 32-bit, tests and smoke | `zig build smoke test -Dcode-unit-width=16\|32` | **observed 2026-10-04: `24/24 tests passed`, `Build Summary: 21/21 steps succeeded`, `smoke success`** at each width. Nothing in this graph refuses a width: `zig/root.zig` resolves `Surface` from the compiled width and `tests.zig` widens or decodes its fixtures into that width's code units. Both runs print the same four captures at the same code-unit offsets as the 8-bit run. Receipts `local://foundation-contract-pcre2-real-native-width-16-UTF-validity-category-full-gate.log` and `…-32-…`. The earlier 23/24 runs of the same two commands are superseded: the missing `.invalid_utf` classification for UTF-16 `-24…-26` and UTF-32 `-27…-28` was a defect in this facade's own return mapping, not a fixture problem |
| 16-bit / 32-bit install | `zig build install -Dcode-unit-width=16\|32 --prefix <p>` | **pending**. The runs above compiled the library at each width and executed the test binary; neither command is this one. The only thing a non-8 width changes about the delivery is that the primary is *named* `libpcre2-16`/`libpcre2-32`, and the POSIX wrapper, `pcre2grep`, `pcre2posix_test` and `libpcre2-posix.pc` are absent there |
| runtime route, **all four** linkage × runtime combinations | `zig build -Druntime=true …` plus a program that calls `pcre2.load`, at each of the four linkages | **pending**, and the claim behind it has narrowed. The driver's own-loaded 8-cell wave `20261004T232823091897Z-23133` did execute this graph's runtime-loaded route — on **eight** cells, against **this repository's own source-built provider** (`independence: own`); see the row below. What still has no receipt is the **four linkages** and any **foreign** provider, and neither is covered by those eight cells |
| System mode | `zig build test -fsys=pcre2-8` | **observed** 2026-10-01 against an installed **10.45**: `9 pass, 1 fail`, the failure being a compile-error **offset** that differs between two releases. Not repeated since, and the tree has changed since |
| integrity | `sha256sum -c UPSTREAM.sha256` | **red, one line, and not an upstream byte.** The 2026-10-01 run reported 59 records all `OK`; the driver's current sweep reports **58 `OK` and one failing record**, `testdata/foundation-fixtures.zig` — the fork's own fixture module, which this wave edited after the digest was taken (record written 2026-10-02, file modified 2026-10-04). **All 58 upstream records verify**, so this is not a native-byte finding. The fix the owner should request is to **re-derive that one digest** — never to re-pin an upstream record, never to drop the failing line, and never to suppress the check. This row is **not** a claim that the native-byte criterion is met |
| six-target compile-only check | `zig build check -Dtarget=<triple>` ×6 | **observed**, baseline epoch `20261005T014547Z-797a73f2`, receipt `baseline-pcre2-check`: a whole-graph `check` at exit 0, `failed: false`, and **`runtime_pass_claimed: false` under every exit code**. The cohort is **compile-only**: a green baseline row proves that this graph compiles for those six targets and nothing about what any of them would do at run time. The 2026-10-02 six-of-six run is the same command on an earlier tree and stays history |
| full 53-platform matrix | `cross-test` | **observed**, cohort epoch `20261004T221720228710Z-45046`, per-SDK receipt `pcre2-53-target-8.json`, run at `jobs 8 / build-jobs 8`: **53 targets — 20 runtime PASS, 33 `build_only`, 0 fail**, driver exit 0, `source_unchanged: true`, `jobs_honoured: true`. **`build_only` is compiled-but-not-run and is never a runtime pass**, so this row is not "53 targets passed" and nothing here claims the suite is green on all 53. The 2026-10-02 sweeps reported the same 20/33 split on an earlier tree and are kept, dated, in [`README.zig.md`](README.zig.md) § "Verification status" |
| native 8-cell delivery wave | `cross-test` over the workspace's eight-cell native set | **observed**, epoch `20261004T233628757747Z-69351`: **8 pass**, no failure recorded. **Boundary:** eight cells, not the published 53, and the wave predates the applied ordering fix above |
| own-loaded 8-cell wave — the runtime-loaded route, provider reached through the platform loader | the same eight cells on the runtime-loaded route | **observed**, epoch `20261004T232823091897Z-23133`: **8 pass**. This is the only evidence that this tree's runtime-loaded route executes at all, and it ran against **this repository's own source-built provider**, not a foreign one. **Boundary:** eight cells — not the published 53 and not the four linkages — and the wave predates the applied ordering fix above |
| independent external provider | an external PCRE2 provider exercised in place of this tree's own build | **none accepted — a boundary, not coverage.** The external-route wave `20261004T232439Z` (`pcre2-index.json`) records **no route carrying `counts_as_external_coverage: true`**. The only successful route is the own source-built provider above; every external candidate is an expected *refusal* — a library that does not export the surface this header declares. That is the ABI boundary this package documents rather than a defect: an installed `libpcre2-8` answers for width 8 only, so a provider for this build has to be one file exporting all three widths |
| translated-header generation: platform configuration established before module creation | `runtime/graph.zig` `generateDispatch` / `createModule`, reached from `build.zig:1381-1388` | **applied; not yet re-gated.** An earlier positive-system **case** reported **28 undefined-symbol diagnostics from the compiler — one case, 28 diagnostics, not 28 separate cells**; a red result, not an all-PASS one. The ordering described in the paragraph above is now correct in the source. **No receipt re-runs pcre2 after it**: that case is not written as PASS here, and no count in this table is evidence for the fix |
| upstream's own test driver | `zig build upstream-test` (pcre2test over `testdata/`), and the `upstream-suite` CI job | **described, never executed here** |
| installed-C program | `.github/workflows/verify.yml`, `installed-bin` and `metadata` jobs | **described, never executed here** |
| `nix build .#default` / `.#static` / `.#shared` | the SDK's policy, and its two variants | **pending** |
| `devenv shell`, `devenv build outputs.static` | the canonical environment; entering it does not build the SDK | **pending** |
| `nix develop` | the same tool list through the flake | **pending**; devenv is canonical |

**The three green width rows are the most recent evidence, not a description of
the present bytes.** They ran before a further round of API changes landed in
`zig/**`: the new `error.SerializationRefused` and the reshaped `OutOfMemory`,
the non-optional `enumerateCallouts` callback, `substitute` invalidating the
captures it leaves behind, and the corrected character-tables ownership. None of
them changes what those rows measured; all four change what a **new** run would
exercise. Until a fresh per-width run exists, the honest summary is **the last
green at all three widths, and sources that moved afterwards.**

**No wholly-static-executable claim is made anywhere.** The `static` output is
a static library artifact plus its header, tool and metadata; a consumer's C
runtime is its own. No Nix output or devenv shell for this package has been
evaluated or built yet, by this role or by the driver.

## Consumption

### From Zig

```zig
// build.zig.zon
.dependencies = .{ .pcre2 = .{ .path = "../pcre2" } },
```

```zig
// build.zig
const dep = b.dependency("pcre2", .{ .target = target, .optimize = optimize });
exe_mod.addImport("pcre2", dep.module("pcre2"));
```

The module carries the compiled artifact and the generated `pcre2.h` include
path, so nothing else is linked and no path reaches into this repository. In a
shared build it also carries the loader entry that resolves **this** build's
`libpcre2-8.so.0`: `Module.linkLibrary` records the directory the shared object
was emitted into, and every compilation importing the module — a dependent's own
executable among them — gets an `-rpath` for it. A dependent's program is built
out of a build cache, where no `lib/` sits beside it, so that is the entry it
needs; the install tree's `$ORIGIN/../lib` is carried only by the programs this
package installs, which is what lets `bin/pcre2test` still find its library
after the tree is moved. The two cannot be one binary, so they are not: nothing
installed here is built from this module.

The typed surface is `pcre2.Regex`, `pcre2.MatchData`, `pcre2.DfaWorkspace`,
`pcre2.Posix` and the rest of `pcre2.Surface`, which is the selected width's
whole facade; the complete translated C is `pcre2.c`. `DfaWorkspace` is the
caller's scratch buffer and **holds no result**: the matched ranges land in the
`MatchData` block's offset vector and are read through `MatchData.ovector()`, so
there is no pair field on the workspace and there never was one. **Every width
the header declares has a symbol in this artifact** — `pcre2.c.pcre2_match_8`,
`pcre2_match_16` and `pcre2_match_32` all resolve in a width-8 build, because
the primary is the union of the three upstream width closures. That is a fact
about *this* artifact; against a single-width installed `libpcre2-8` the 16-
and 32-bit declarations remain unresolved and calling one is a link failure.
`-Druntime=true` replaces the translated header with a generated dispatch over
the same declaration list, and `pcre2.load` is what makes it usable.

**Full interface, examples and ownership rules: [`README.zig.md`](README.zig.md).**

### From C, against an installed prefix

<p>/include/pcre2.h            the copy of src/pcre2.h.generic the core compiles against
<p>/include/pcre2posix.h       the POSIX wrapper's header (width 8 only)
<p>/lib/libpcre2-8.a|.so       the core — all three widths — as an archive or a shared library
<p>/lib/libpcre2-posix.a|.so   the POSIX wrapper (width 8 only)
<p>/bin/pcre2test              upstream's own test driver
<p>/bin/pcre2grep              upstream's grep (needs zlib and libbz2)
<p>/bin/pcre2-config           upstream's configuration script
<p>/bin/pcre2posix_test        upstream's POSIX wrapper test program
<p>/lib/pkgconfig/libpcre2-8.pc, libpcre2-posix.pc   link metadata
<p>/share/man/man1, man3       the manual pages
<p>/share/doc/pcre2            upstream's docs and licence material, and this fork's

A shared build installs `libpcre2-8.so.0.16.1` with `DT_SONAME libpcre2-8.so.0`
and `libpcre2-posix.so.3.0.9` with `DT_SONAME libpcre2-posix.so.3`, both with
`.so.N` and `.so` symlinks; a static build replaces each with `.a` and drops the
version script and the soname. **No wholly-static-executable claim is made
anywhere**: the `static` output is a static library artifact plus its headers,
tools, metadata and docs; a consumer's C runtime is its own.

```c
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <stdio.h>
#include <string.h>

int main(void) {
  char version[256];                     /* upstream's own demo uses 256, src/pcre2demo.c:152 */
  pcre2_config(PCRE2_CONFIG_VERSION, version);

  int error_number; PCRE2_SIZE error_offset;
  pcre2_code *re = pcre2_compile("(a)(b)?c", PCRE2_ZERO_TERMINATED, 0,
                                 &error_number, &error_offset, NULL);
  if (re == NULL) {
    fprintf(stderr, "compile error %d at offset %zu\n", error_number,
            (size_t)error_offset);
    return 1;
  }

  const char *subject = "xxabc";
  pcre2_match_data *md = pcre2_match_data_create_from_pattern(re, NULL);
  int rc = pcre2_match(re, subject, strlen(subject), 0, 0, md, NULL);
  if (rc > 0) {
    PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);   /* valid once rc > 0 */
    for (int i = 0; i < rc; i++)
      printf("group %d: %.*s\n", i, (int)(ov[2 * i + 1] - ov[2 * i]),
             subject + ov[2 * i]);
  }

  pcre2_match_data_free(md);
  pcre2_code_free(re);
  return rc < 0 ? 1 : 0;
}
```

```sh
zig cc -o demo demo.c -I<p>/include -L<p>/lib -lpcre2-8 && ./demo
# or, against a Nix output where the pkg-config metadata is installed:
zig cc -o demo demo.c $(pkg-config --cflags --libs libpcre2-8)
```

Eight rules, each read out of the sources:

* **The code-unit width is part of the header contract.** `PCRE2_CODE_UNIT_WIDTH`
  must be defined before `<pcre2.h>` (`src/pcre2.h.generic:1057-1059`), and
  `PCRE2_SUFFIX` pastes the width into every exported name (`:1064`). An 8-bit
  declaration is not a 16-bit call.
* **The header declares all three widths; this artifact carries all three.**
  `src/pcre2.h.generic:1021-1031` runs the per-width block three times whatever
  `PCRE2_CODE_UNIT_WIDTH` says, so `pcre2_match_16` and `pcre2_match_32` are
  declared next to `pcre2_match_8`. Upstream's three files would leave two
  thirds of those declarations unresolved, which is why the primary artifact
  here is their union. Against an installed single-width `libpcre2-8` — what
  `-fsys=pcre2-8` binds, and observed on this host as `pcre2_compile_16: MISSING`,
  `pcre2_compile_32: MISSING` — those two are link failures again, and a runtime
  provider for this build has to be a file that exports all three
  (`local://foundation-contract-pcre2-full-header-width-provider-probe-before.log:1-4`).
* **`PCRE2_STATIC` matters on Windows**, where the header otherwise declares
  the whole API `extern __declspec(dllimport)` (`src/pcre2.h.generic:56-63`). On
  ELF and macOS it is not read, so which linkage a prefix carries is a fact
  about the artifact. A consumer **must** define it to link a Windows static
  archive, and a translation unit that calls the core from *inside* the shared
  library must instead define `PCRE2_EXP_DECL=extern`, because `dllimport` there
  would be an import from the DLL the callee lives in. The build graph does
  each in the place that needs it.
* **`pcre2-posix` is 8-bit by construction**, not by preference. Its
  `regexec` takes a `char *` subject and `rm_so` counts bytes
  (`src/pcre2posix.h:104-119`), so the wrapper, `pcre2grep` and
  `pcre2posix_test` are absent from a width-16 or width-32 prefix — and
  `libpcre2-posix.pc` names `libpcre2-8` in its `Requires.private`, which is the
  same reason a second time: at width 16 the primary is called `libpcre2-16`
  and that `-l` name does not resolve.
* **A DFA result is in the match block, never in the workspace.**
  `pcre2_dfa_match_N` hands its matcher the `pcre2_match_data`'s own offset
  vector as the output (`src/pcre2_dfa_match.c:4062-4063`), and upstream's own
  substring helpers read a DFA result out of that block
  (`src/pcre2_substring.c:334-341`). The `wscount`-sized buffer is the matcher's
  working storage and the only place a `PCRE2_DFA_RESTART`'s state can live
  (`src/pcre2_dfa_match.c:605-606`, `:3486-3489`); upstream refuses anything
  below 20 with `PCRE2_ERROR_DFA_WSSIZE`, -43 (`:3437`). So the vector must be
  sized for **every simultaneous match**, not one pair per parenthesis
  (`doc/pcre2_dfa_match.3:33-35`); the pairs are matched substrings and not
  capture groups, because this matcher has none (`doc/pcre2.txt:4340-4343`);
  they come out **longest first** (`:4352-4360`); and a return of **zero** means
  more were found than fitted, so the vector holds the longest ones and the
  answer is truncated rather than empty and rather than a failure
  (`:4359-4360`).
* **The name table's group number is `IMM2_SIZE` code units, not two bytes.**
  `src/pcre2_intmodedep.h:212-221` makes it **two** in the 8-bit library, where
  `GET2` is a big-endian pair, and **one** in the 16- and 32-bit libraries.
  Upstream reaches the name by adding `IMM2_SIZE` to a code-unit pointer
  (`src/pcre2_compile_cgroup.c:142-144`, `:167-175`;
  `src/pcre2_substring.c:498-518`), so reading a 16- or 32-bit table as bytes
  lands inside a code unit and names a different group every time. Every entry
  is sized to the **longest** name in the pattern plus `IMM2_SIZE` plus one
  (`src/pcre2_compile.c:5713-5716`) and NUL-padded out to that size, so a name
  ends at its own NUL and not at the end of the entry.
* **A group that did not take part is a value, not an absence.** In the width
  surface it is `PCRE2_UNSET` in the offset vector (`src/pcre2.h.generic:539`),
  which is `SIZE_MAX`; in the POSIX wrapper it is the literal `-1` written into
  **both** ends of the `regmatch_t` **and into every slot past the ones the
  match filled** (`src/pcre2posix.c:403-408`). `-1` is not `PCRE2_UNSET`
  narrowed, so a POSIX capture is never compared against `pcre2.unset`, and a
  `regmatch_t` array shorter than the pattern's capture count is a smaller
  answer rather than an overrun. `REG_BADPAT` is the POSIX wrapper's **default**,
  not the answer for every bad pattern: it looks the compile-error index up in
  two tables and falls back for anything not listed
  (`src/pcre2posix.c:312-319`), so `a(b` is `REG_EPAREN`, because `missing )`
  maps there (`:146`). Match the code; do not infer the kind of wrong from it.
* **The allocator enters at one place, and Native memory comes back where it
  was made.** 10.49's public header declares no `pcre2_set_malloc`-style
  setter; a custom allocator goes to
  `pcre2_general_context_create(malloc_fn, free_fn, memory_data)`
  (`src/pcre2.h.generic:643`; defaults wired in `src/pcre2_context.c:110-123`,
  `:81-97`) and reaches the compile, match and convert contexts through that
  general context. Everything PCRE2 returns is a **pointer and a length** — a
  copied substring, the array a substring list allocates, a converted pattern —
  and is released with the matching `*_free` from the **same library
  instance**, never with the caller's own `free` and never by indexing into the
  block. That matters most when the library is a separately loaded image rather
  than an archive in your own binary, where the free has to happen where the
  allocation happened.

`pcre2test` reads its input files relative to the current directory, so
upstream's `testdata/` travels with the source tree; `UPSTREAM.md` names the
eight files this fork's fixtures cite by line.

### Through the Nix packages

```sh
nix build .#static --print-out-paths   # or .#shared, .#default
```

`.#default` passes no `-Dlinkage`, so the SDK's own policy applies. The build
graph owns what each output contains: the primary artifact, the headers, the
POSIX wrapper, the four upstream programs, pkg-config metadata for that width
and for the wrapper (`Requires.private` on the core), the manual pages and
upstream's `doc/`, and the licence material, because the BSD
binary-redistribution condition is the obligation that survives into a built
artifact. Packaging installs none of it, so there is one writer per path.
`runtime` is an argument of the same derivation, so `.#default`, `.#static`,
`.#shared` and their runtime forms are four configurations of one build, and
none of them substitutes for another. The 16- and 32-bit widths are the same
derivation with `codeUnitWidth = 16` or `32`; neither is a named flake output.
**No output of this flake has been built yet** — see the matrix above.

### The development environment

```sh
devenv shell          # or: direnv allow, then cd
```

Tools only — the pinned Zig 0.16.0, a C toolchain, `pkg-config`, GNU make,
`gdb` and `git`. The SDK is never in the shell: its variants are lazy
`outputs`, so `devenv build outputs.static` builds the same `package.nix` the
flake exposes without making shell entry depend on it. Cache locations follow
`HOST_SCRATCH_ROOT` only where the caller has not already chosen one.
`nix develop` reaches the same tool list through the flake; devenv is canonical.

The seven entries — `sdk.build`, `sdk.test`, `sdk.test-release-safe`,
`sdk.smoke`, `sdk.check`, `sdk.integrity` and `sdk.consumer`, all **scripts**
and all spelled with the dotted names devenv gives scripts — each begin by
changing to this repository, rendered `builtins.toString ./.` and quoted with
`lib.escapeShellArg`. They need to: `devenv shell -- <name>` runs an entry in
the caller's directory, and the canonical-environment contract runs it with
`--from path:<sdk>` from a scratch project beside this SDK, which holds
`.devenv/` and `devenv.lock` and no `build.zig` and no `UPSTREAM.sha256`.
`sdk.consumer` names `<sdk>/consumer` directly. Every entry that reaches `zig
build` carries the workspace's gate recipe — `-j8`, an explicit external
`--cache-dir` and `--summary all` — named **before** `"$@"`, and `"$@"` still
comes last. Each of those flags is read last-wins, so a caller's own `-j`,
`--cache-dir`, `--summary` or `-D…` still wins over what the file names.

`sdk.build` is the one entry that delivers an install prefix, and it writes it
to `--prefix "$ZIG_LOCAL_CACHE_DIR/pcre2-install"` rather than to the `zig-out`
`zig build` would default to beside the build root — a delivery tree inside a
source repository, on a volume mount. That cache is `ZIG_LOCAL_CACHE_DIR`,
resolved by the caller's own value first, then the one
`enterShell` exports from `HOST_SCRATCH_ROOT`, then `XDG_CACHE_HOME`, then
`TMPDIR`; with none of them named the entry stops and says which variable is
missing, because no committed file names a host path and a caller's own choice
still stands. `ZIG_GLOBAL_CACHE_DIR` follows the same rule. That preamble runs
inside every entry that reaches `zig build`, not only in `enterShell`, and each
of those commands passes the settled directory with an explicit `--cache-dir`,
so Zig never falls back to the `.zig-cache` it would write beside `build.zig` —
inside this checkout for the five SDK-root entries, and a second one inside
`<sdk>/consumer` for `sdk.consumer`. `sdk.test`, `sdk.test-release-safe`,
`sdk.smoke` and `sdk.check` run steps that install nothing, and `sdk.consumer`
installs no file (`consumer/build.zig:145-149`), so none of them names a prefix.
A plain `zig build` run by hand still writes `zig-out/`, which stays in
`.gitignore` and out of the package paths.

### Against an installed PCRE2 instead

`zig build test -fsys=pcre2-8` links an installed `libpcre2-8` and translates
the header installed beside it, by angle brackets, so the declarations cannot
come from a different release than the library. It refuses a foreign `-Dtarget`
and any width but 8. It has been run here against an installed **10.45**, older
than this tree, and the fixtures are pinned to 10.49 by construction — so a
difference is read against the version the machine reports and never fixed by
loosening a fixture. That run, its one failing case and what is known about its
cause are in [`README.zig.md`](README.zig.md) § "Verification status".

**The one limit of this mode is stated rather than worked around.** An installed
PCRE2 is a single-width library, and this tree's `<pcre2.h>` declares all three.
A **linked** `-fsys` build is unaffected, because the typed facade only calls
the width its translation was configured for. A `-fsys=pcre2-8 -Druntime=true`
build is not: `load` names one file, that file has to answer for every width
the header declares, and a standard external `libpcre2-8` cannot. The graph
requires the whole declared surface rather than narrowing the requirement to
make a real library loadable.

## See also

| File | What it holds |
|---|---|
| [`README.zig.md`](README.zig.md) | the Zig interface, the external ABI boundaries, and the one current gate table |
| [`README.upstream.md`](README.upstream.md) | upstream's README, byte for byte |
| [`UPSTREAM.md`](UPSTREAM.md) | the pin, what is compiled with which switches, what was removed, the sync procedure |
| [`NOTICE.md`](NOTICE.md) | attribution, the per-path licence split, every file this fork adds or edits |
| [`FORK-LICENSE.md`](FORK-LICENSE.md) | the grant for fork-authored files and the authorization behind it |
| [`UPSTREAM.sha256`](UPSTREAM.sha256) | 59 replayable digests — 58 upstream files and this fork's own fixture module, with the split stated in the file's own header |
| [`CHANGELOG.md`](CHANGELOG.md) | numbered fork-only divergences |
| [`FORK-NOTES.md`](FORK-NOTES.md) | the problems met, in a shape a later wave can reuse |