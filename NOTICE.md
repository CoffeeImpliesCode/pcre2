# NOTICE

PCRE2 fork. Attribution, the licence split, and every byte this fork adds or
edits.

## Upstream work

PCRE2 is the work of **Philip Hazel** and contributors, with the original API
code at the University of Cambridge. Upstream states the whole thing itself,
per work, in `LICENCE.md`, and this repository ships that file unmodified.

Upstream repository: `https://github.com/PCRE2Project/pcre2.git`. This fork
carries tag `pcre2-10.49`, commit
`6f9d7c1373262c541324a16a358785b33ef116cf`.

| Work | Author and copyright | Where upstream states it |
|---|---|---|
| the basic library functions | Written by Philip Hazel. Original API code Copyright (c) 1997-2012 University of Cambridge; new API code Copyright (c) 2016-2024 University of Cambridge; Copyright (c) 1997-2007 University of Cambridge and Copyright (c) 2007-2024 Philip Hazel for the whole library | `LICENCE.md:28-37`, and the same two copyright lines at the head of every `src/*.c` and internal header |
| PCRE2 just-in-time compilation support | This module by Zoltan Herczeg. Copyright (c) 2010-2024 Zoltan Herczeg | `LICENCE.md:39-46`; per file at the head of `src/pcre2_jit_compile.c`, `src/pcre2_jit_char_inc.h` and `src/pcre2_jit_simd_inc.h` |
| stack-less just-in-time compiler (`deps/sljit`) | Zoltan Herczeg. Copyright (c) 2009-2024 Zoltan Herczeg | `LICENCE.md:48-57`; the submodule directory carries its own `LICENSE` file upstream |
| all other contributions | copyright retained by each original contributor or their employer — "As PCRE2 has never required a Contributor Licensing Agreement, or other copyright assignment agreement" | `LICENCE.md:59-64` |

The per-file headers are upstream's bytes and are not harmonised here. Two year
ranges appear in them and they are not the same range: the per-file headers say
`1997-2012` (original API) and `2016-2024` (new API), while `LICENCE.md:35-37`
summarises the same work as `1997-2007 University of Cambridge` and
`2007-2024 Philip Hazel`. Both statements are upstream's, in upstream's own
files, and neither is edited here.

## The grants, and which one applies to which path

Upstream's licence file states its own SPDX identifier on line 4:
`BSD-3-Clause WITH PCRE2-exception`. It is a **BSD three-clause licence with one
stated exemption**, and that is the whole of it. The grant is **per kind of
content**, not one grant over one tree:

| Path | Grant | Why |
|---|---|---|
| `src/`, `doc/`, and the build and packaging files | **BSD-3-Clause WITH PCRE2-exception** | "Releases 10.00 and above of PCRE2 are distributed under the terms of the 'BSD' licence… The documentation for PCRE2, supplied in the 'doc' directory, is distributed under the same terms as the software itself" (`LICENCE.md:10-13`) |
| **`testdata/`** | **not copyrighted; in the public domain** | "The data in the testdata directory is not copyrighted and is in the public domain" (`LICENCE.md:14`). This is not a BSD grant and nothing here restates it as one |
| the just-in-time compiler (`src/pcre2_jit_compile.c` and its `_inc.h` files, `deps/sljit`) | **2-clause BSD** | "the just-in-time compiler… is separately licensed under the '2-clause BSD' licence" (`LICENCE.md:16-20`), and "The code in the `deps/sljit` directory has its own LICENSE file" (`LICENCE.md:57`) |
| `.gitignore` | BSD-3-Clause WITH PCRE2-exception, as upstream's | upstream's file; this fork appends to it and does not remove or narrow any of upstream's entries — see the change table below |

* Everything this fork did **not** write stays under upstream's own per-path
  grant. This fork narrows nothing and re-grants nothing.
* The fork-authored Zig build graph, manifest, aggregate header, facade, tests,
  smoke program, consumer, fixture module, `cross-test` harness profile, CI
  workflow and documentation have no stated licence; their status is
  **unassigned**. The earlier offer under BSD-3-Clause WITH PCRE2-exception was
  unsupported and is withdrawn. No grant over these additions may be inferred
  from the upstream terms.
* `deps/sljit` is an **empty directory** in this checkout: the git submodule
  named in `.gitmodules:1-3` was never populated, nothing in this package
  compiles or links it, and no sljit licence text is shipped here because there
  is no sljit code to ship. The 2-clause BSD grant is recorded because
  `LICENCE.md` records it and `src/pcre2_jit_compile.c` is present in the tree
  under it.

## Per-file exceptions

Two files inside the hashed source set carry **no per-file copyright header**.
They are named here so a per-file attribution audit does not have to rediscover
them, and the grant covers them anyway because it covers the package:

| File | What it is | Why it has no header |
|---|---|---|
| `src/pcre2_chartables.c.dist` | the character tables, compiled as `pcre2_chartables.c` | its first lines are a generation banner: "This file was automatically written by the `pcre2_dftables` auxiliary program" (`src/pcre2_chartables.c.dist:5-7`). The generator it was written by is `src/pcre2_dftables.c:8-10` — Written by Philip Hazel, Original API code Copyright (c) 1997-2012 University of Cambridge, New API code Copyright (c) 2016-2020 University of Cambridge — so the work is covered, but the per-file line was not written into the output |
| `src/config-cmake.h.in` | the CMake `config.h` template, substituted per target by `addConfigHeader` | its whole content is `#cmakedefine` lines; the first line is `/* config.h for CMake builds */` (`src/config-cmake.h.in:1`) and the file carries no author, no date and no grant of its own |

**45 of the 47 files from `src/` in `UPSTREAM.sha256` carry that per-file
header** — every core unit, `src/pcre2.h.generic`, the 12 internal headers and
`src/pcre2posix.h`. The two exceptions are the two rows above and nothing else.
`src/pcre2test.c` is a variant of the same grant with the words "Original
code" and "Rewritten code" in place of "Original API code" and "New API
code" (`src/pcre2test.c:9-11`); that is upstream's wording and is not
normalised.

## What the licence requires of a downstream

This is a BSD licence, not Apache-2.0, and the obligations are the BSD ones.
Stating them here rather than importing a different licence's vocabulary:

* **Condition 1 (source redistribution).** "Redistributions of source code must
  retain the above copyright notices, this list of conditions and the following
  disclaimer" (`LICENCE.md:73-74`). This repository satisfies it by shipping
  `LICENCE.md` and `COPYING` unmodified and by editing no upstream byte.
* **Condition 2 (binary redistribution).** "Redistributions in binary form must
  reproduce the above copyright notices, this list of conditions and the
  following disclaimer in the documentation and/or other materials provided with
  the distribution" (`LICENCE.md:76-78`). This is the one obligation that
  survives into a built artifact, and it is why this file, `LICENCE.md` and
  `COPYING` travel with the source **and** must travel with anything built from
  it.
* **Condition 3 (no endorsement).** "Neither the name of the University of
  Cambridge nor the names of any contributors may be used to endorse or promote
  products derived from this software without specific prior written permission"
  (`LICENCE.md:80-82`).
* **The PCRE2 exception** (`LICENCE.md:97-104`) narrows condition 2 one level
  down a chain: if binary package A includes PCRE2 it must respect the
  condition, but if package B includes package A, the condition is not imposed
  on package B "unless it uses PCRE2 independently". This is upstream's own
  wording and is reproduced by reference, not restated as permission.

**There is no Apache-2.0 obligation here, and this file does not create one.**
In particular: no `NOTICE`-file requirement, no "state that files were changed"
requirement, and **no patent-grant and no patent-grant termination clause**,
because the shipped licence grants no patent licence. This file exists because
this fork wants the attribution and the change statement to be complete and
greppable in one place — that is a choice, and it is recorded here as a choice.

`UPSTREAM.md` records that upstream signs its source releases and names the
signing keys (`SECURITY.md:13-15`). **No signature was checked while writing
any file in this set**, and no git command was run. The commit id and the
`git archive` digest in `UPSTREAM.md` are provenance anchors recorded by the
driver, not a verification this fork performed.

## What this fork changed

**No upstream source file, header, test, licence text or fixture byte is
modified.** `UPSTREAM.sha256` records the SHA-256 of 59 files the package
compiles, installs, reads as an oracle or publishes terms for, plus this fork's
own fixture module, and `sha256sum -c UPSTREAM.sha256` is the check. That
command **has been run here and passed**: exit 0, 59 records, every line `OK`
(`local://foundation-expansion-pcre2-immutable-source-integrity-168.log`), and
`.github/workflows/verify.yml` runs the same command as the first step of its
native job.

One upstream file is edited, and only by appending:

| File | Change |
|---|---|
| `.gitignore` | upstream's own list is kept verbatim and unedited — `build/`, `build-*/`, `pages/`, the object and coverage patterns, the autotools and CMake outputs, the `m4/libtool*` set, the `src/` generated-file list, `/bazel-*`, `*.bazel.lock`, `zig-pkg/`, `zig-out/`, `zig-cache/`, `.zig-cache/`, `.vscode/`, `.devcontainer/`, `.personal/` (`.gitignore:1-128`). The fork appends one comment block and **seven** re-inclusion lines, `!translate.h`, `!cross-test.profile.sh`, `!/zig/`, `!/tests.zig`, `!/smoke.zig`, `!/consumer/`, `!/testdata/` (`.gitignore:130-156`). No upstream entry is removed or narrowed. Because the file is therefore not byte-identical to upstream's, it is deliberately absent from `UPSTREAM.sha256` |

Everything else this fork adds is new, in new files and new regions:

| File | What it is |
|---|---|
| `build.zig` | Zig 0.16 build graph. Extends upstream's own Zig graph rather than replacing it: the `pcre2.h` copy, the `config.h` generation, the explicit 31-unit compile list, and the `linkage` / `sanitize_c` / `code-unit-width` options all still do that work. Adds the `pcre2` module, the `test`, `smoke` and `check` steps, the six-target compile-only check, the real `-fsys=pcre2-8` system option, and the private `AggregateRoute` / `aggregateRoute` / `preprocessedAggregate` pair that chooses, per target, whether the bundled aggregate is read by Aro alone or by the target's own `zig cc -E -dD -fno-blocks` first. Removes the `sljit` dependency and `-Dsupport_jit`, which cannot work without a populated submodule or a network fetch |
| `build.zig.zon` | package manifest, dependency-free, `.paths` = what a dependent receives. `.version` is checked against the pin at configure time |
| `cross-test.profile.sh` | fork-authored harness configuration, not documentation and not a build input: ordinary Bash variable definitions that `cross-test` sources when it runs this package's `test` step over the published 53-platform matrix. It defines no hooks, no matrix and no host path, and nothing in `build.zig` reads it. Listed in `.paths` so a fetched copy carries it |
| `translate.h` | the only new C file, and the aggregate `zig translate-c` is pointed at: a macro prelude (`PCRE2_CODE_UNIT_WIDTH`, `PCRE2_STATIC` — both configured by `build.zig`, not written here), one `#include "pcre2.h"`, and the compiler's own `__int128_t` / `__uint128_t` restated under `#if defined(__SIZEOF_INT128__)`. It copies no prototype, restates no PCRE2 declaration and adds no feature; the two typedefs are the compiler's, guarded by the compiler's own statement that the target has the `__int128` extension |
| `zig/root.zig` | the Zig facade: `Regex`, `MatchData`, `MatchContext`, `version`, the option structs, the outcome unions, the error set, and `pub const c` for the complete translated header |
| `tests.zig` | 10 behavioural tests: the 15-case fixture table replay, the bounds the facade owns, the name-table order and padding contract, the version-buffer contract, the ownership transitions, and the capture-lifetime cases — including `an attempt that did not match leaves nothing readable, whatever the last one found`, which is the permanent regression for the root-match validity rule |
| `testdata/foundation-fixtures.zig` | **fork-authored**, 15 known answers. Every entry names the upstream `testdata/` file and line it was read out of, or states that it was hand-derived from the C and shows the derivation. Upstream ships no such file |
| `smoke.zig` | the deterministic example behind `zig build smoke`; every expected byte offset is worked out by hand and a mismatch exits non-zero |
| `consumer/` | a separate package that depends on this one by relative path and runs a structured-log reader through the published module |
| `.github/workflows/verify.yml` | this fork's own verification workflow: the integrity check, the native build, an installed-header C gate that compiles, links and runs a C program against the **installed** `pcre2.h`, `pcre2-posix` and both installed libraries, Debug and ReleaseSafe tests, smoke, one `check` job per cross target, the `-fsys=pcre2-8` job, and the consumer package. The C gate asks the library about captures, names, both substring ownership rules, a Greek UTF-8 property, a non-Greek refusal and the POSIX wrapper's own `REG_NOMATCH`; it declares no name PCRE2 does not define, sizes the substring buffer with `sizeof` and checks `pcre2_get_ovector_count` before reading three offset pairs, and the only version it reports is the `pkg-config --modversion` of the package the system job installed. Upstream's eight workflows are left untouched and are not retargeted at this repository. **The workflow itself has never been executed here**, so it is a description and not a result |
| `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md` | provenance, integrity and fork documentation |

## Credits upstream records, which are not grants

Upstream's `AUTHORS.md` points at `LICENCE.md` for copyright details and names
the maintainers and contributors; this fork drops none of it. `NEWS` records
that **10.49 is a security-only release for GHSA-r9hj-j2rw-4q3m**, an
out-of-bounds write reachable only through `pcre2_jit_stack_create()` and
`pcre2_jit_stack_assign()`, and states at `NEWS:19` that it is not a regression
and affects 10.48 and earlier. This fork builds with JIT off and publishes no
JIT stack API, so that path is not in the archive this package produces — which
is a statement about *this* configuration, not a claim about the advisory in
general, and a `-fsys=pcre2-8` consumer must read it for the release its
installed library is.

## Status

Every claim above is read out of a file in this tree, so it is
`SOURCE-CONFIRMED` by construction. The gate results are a separate matter and
are listed once, in [`README.zig.md`](README.zig.md) § "Verification status".
The short form: against this tree's own 10.49 library the integrity record, the
Debug and ReleaseSafe suites with smoke and install, and the consumer package
have **passed**; all six cross-target `check` compiles are **green** in the
corrected baseline of 2026-10-02, where the three GNU-libc cells had been red;
and the published 53-platform matrix reports **20 cells executed at `10/10`
tests, 0 failures and 33 compile-only cells**. `-fsys=pcre2-8` has been run
against an installed **10.45** and returned `9 pass, 1 fail` on one fixture's
compile-error offset; that run and the installed-C program are the 2026-10-01
receipts, and this wave changed only the bundled translation, so they were not
repeated and nothing new is claimed about an installed library. **This
repository's own CI has never been executed here**, and the current
filtered-package result and identity are recorded by the driver outside this
tree — in the root `FORKS.json` under `cross_test_wave.materialized_packages.pcre2`
and in `local://foundation-cross-test-package-regression.json` — because this
documentation is part of what the package ships.
