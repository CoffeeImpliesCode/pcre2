# UPSTREAM.md — what this fork is a fork of

## Upstream

| | |
|---|---|
| Project | PCRE2, a C library of Perl-compatible regular-expression functions |
| Canonical repository | `https://github.com/PCRE2Project/pcre2.git` |
| Pinned ref | tag `pcre2-10.49` |
| Pinned commit | `6f9d7c1373262c541324a16a358785b33ef116cf` |
| Version of the C library built here | `10.49`, `PCRE2_DATE` `2026-09-28` |
| Library licence | `BSD-3-Clause WITH PCRE2-exception` |
| Test-data licence | not copyrighted; public domain |
| Copyright | see the table below |

Where each of those comes from, read out of the carried tree:

* The version is `configure.ac:11-14` — `m4_define(pcre2_major, [10])`,
  `m4_define(pcre2_minor, [49])`, `m4_define(pcre2_prerelease, [])`,
  `m4_define(pcre2_date, [2026-09-28])` — substituted into `src/pcre2.h.in:44-47`
  and carried in the tree already substituted, as `src/pcre2.h.generic:44-47`:
  `PCRE2_MAJOR 10`, `PCRE2_MINOR 49`, `PCRE2_PRERELEASE` empty, `PCRE2_DATE
  2026-09-28`. That is the version string `pcre2_config(PCRE2_CONFIG_VERSION, …)`
  formats at run time (`src/pcre2_config.c:236-243`), and it is what the smoke
  run printed. The library's own ABI versions are `configure.ac:17-20`
  (`libpcre2_8_version 16:1:16`, and the same for 16 and 32; `libpcre2_posix_version
  3:9:0`). `build.zig.zon` carries `.version = "10.49.0"`, and `build.zig:250-252`
  `@panic`s if that drifts from `upstream_version`, so a version bump is a
  decision someone has to make rather than a side effect of a merge.
* The licence is `LICENCE.md`, which states its own SPDX identifier on line 4
  (`BSD-3-Clause WITH PCRE2-exception`), the full BSD three-clause text at
  `:67-94`, and the binary-redistribution exemption at `:97-104`. `COPYING` is
  the same terms for the autotools-generated distribution. Both ship unmodified
  and are hashed in `UPSTREAM.sha256`.
* Upstream splits its own terms by kind of content, and this fork keeps the
  split rather than flattening it (`LICENCE.md:12-14`, `:19-20`, `:57`):
  * the library and the `doc/` directory are under the BSD terms;
  * **the data in `testdata/` is not copyrighted and is in the public domain** —
    this is the grant that covers the eight `testdata/` files `UPSTREAM.sha256`
    pins, and it is not a BSD grant;
  * the just-in-time compiler is separately licensed under the 2-clause BSD
    licence, and `deps/sljit` has its own `LICENSE` file.
* The copyright table is `LICENCE.md:23-64`, and it is per work, not per file:

  | Work | Copyright | Where |
  |---|---|---|
  | the basic library functions | Copyright (c) 1997-2007 University of Cambridge; Copyright (c) 2007-2024 Philip Hazel | `LICENCE.md:35-37` |
  | PCRE2 just-in-time compilation support | Copyright (c) 2010-2024 Zoltan Herczeg | `LICENCE.md:45-46` |
  | stack-less just-in-time compiler | Copyright (c) 2009-2024 Zoltan Herczeg | `LICENCE.md:52-55` |
  | all other contributions | copyright retained by each original contributor or their employer — PCRE2 has never required a CLA | `LICENCE.md:59-64` |

  The second and third rows are the JIT. This fork builds with JIT off, so those
  two grants govern source it carries but does not put in the archive; they are
  recorded because `LICENCE.md` records them and a binary-redistribution audit
  reads the licence, not the build graph. `NOTICE.md` restates the same split
  per path.
* Upstream's own description of what this library is: "a set of C functions
  that implement regular expression pattern matching… self-contained and
  portable", BSD-licensed and "permitted in proprietary software"
  (`README.md:8-14`).

**Tag signature: not verified here.** No signing key was consulted while this
file was written and no git command was run at all, so nothing here is an
observation of the clone's own state. Upstream signs its source releases and
names the signing keys in `SECURITY.md:13-15`; the commit id and the archive
digest below are the provenance anchors, not a signature check.

## Archive receipt

The workspace delivery record `local://foundation-expansion-source-archives.json`
holds a SHA-256 receipt for the deterministic `git archive` stream of the
**full tree** at that commit. For this library it reads, verbatim:

```
e2353f82162d1860ebfbce03c227f539285ab8503e4d57617370b824c4fbde11  -
```

The trailing `-` is `sha256sum`'s name for standard input: the digest is of the
archive stream as it was piped past the hasher, not of any file in this
repository. The driver produced it when the fork was imported. It is recorded
here so a later re-fetch can be compared against the same bytes.

The companion record `local://foundation-expansion-sources.json` names the same
repository, ref and commit, records the licence as "BSD-3-Clause WITH
PCRE2-exception", and records the configuration as "8-bit, Unicode,
interpreter+DFA, JIT off". The next section is where that configuration is
checked against the source.

## Import mechanism

A full clone of the canonical repository, so upstream's Git history is present.
The workspace delivery record states that every fork in this wave keeps the
upstream remote named `upstream`, a local `main`, and complete upstream history.
This fork adds no patch series on top of that history.

**One upstream file is edited, and only by appending: `.gitignore`.** Upstream's
own list is kept verbatim and unedited, and the fork appends one block of
comments plus seven re-inclusion lines, including `!cross-test.profile.sh`. Because the file is therefore not
byte-identical to upstream's, it is deliberately absent from `UPSTREAM.sha256`
and the append is recorded in [`NOTICE.md`](NOTICE.md) and `FORK-NOTES.md` §12
instead. Everything else this fork adds is a new file in a new region.

## What this fork is

A Zig package that compiles upstream's own C library from `src/` in this
repository and publishes a Zig facade over the translated `pcre2.h`. Nothing of
the matching engine is reimplemented, re-derived or reconfigured: no table is
regenerated, no upstream source is patched, and nothing is downloaded at build
time. `NOTICE.md` lists every file this fork adds or edits.

### What is compiled, and with which switches

The build is upstream's own Zig 0.16 graph, extended rather than replaced: the
`src/pcre2.h.generic` → `pcre2.h` copy through `addWriteFiles`, the `config.h`
generation from `src/config-cmake.h.in` through `addConfigHeader`, and the
explicit translation-unit list all still do that work (`build.zig:5-9`). The
core is **31 translation units**: the 30 entries of `core_sources`
(`build.zig:93-124`) plus `src/pcre2_chartables.c.dist`, which ships under a
`.dist` name and is copied to `pcre2_chartables.c` and compiled
(`build.zig:494-497`). The list is explicit rather than globbed, so a new
upstream translation unit cannot slip into the archive without a decision here.

That set is the **full** 8-bit core, and it is the configuration the delivery
record names:

| Requirement | How this build satisfies it | Where it is decided |
|---|---|---|
| 8-bit | `PCRE2_CODE_UNIT_WIDTH=8` on the C compile line, on the line that reads the header for the target (the preprocessing line, or the translation line on the `isGnuLibC()` route), and defaulted in `translate.h`; `SUPPORT_PCRE2_8` true, 16 and 32 false | `build.zig:475`, `:557-572`, `:845`, `translate.h:101-103`, `build.zig:897-899` |
| Unicode | `SUPPORT_UNICODE` true, so the interpreter and the DFA matcher run over UCP | `build.zig:902` |
| interpreter | `src/pcre2_match.c`, with `src/pcre2_auto_possess.c`, `pcre2_study.c`, `pcre2_match_next.c`, `pcre2_chkdint.c`, `pcre2_valid_utf.c` | `build.zig:93-124` |
| DFA | `src/pcre2_dfa_match.c` | `build.zig:101` |
| Unicode property machinery | `src/pcre2_ucd.c`, `src/pcre2_extuni.c`, `src/pcre2_script_run.c`, `src/pcre2_xclass.c`, `src/pcre2_ord2utf.c`, and the compiled-in `pcre2_tables.c` | `build.zig:90-91`, `:103`, `:111`, `:113`, `:120`, `:122` |
| JIT deliberately off | `SUPPORT_JIT` false in the generated `config.h` | `build.zig:905` |

`src/pcre2_jit_compile.c` **is** in the compile list and contributes nothing:
with `SUPPORT_JIT` at 0 every definition in it is behind `#if` and the unit is
empty after preprocessing. It stays in the list because it is part of upstream's
source set and must compile whether or not it defines anything
(`build.zig:36-42`).

Two more artifacts are built from the same tree and the same generated
`config.h`, so a dependent that wants them needs no path into the sources:

| Artifact | Sources | Notes |
|---|---|---|
| `pcre2-posix` | `src/pcre2posix.c` | upstream's POSIX `regcomp`/`regexec` emulation; built and installed only for width 8, because `regexec` takes a `char *` subject and `rm_so` counts bytes, so a 16- or 32-bit core would reinterpret every subject byte (`build.zig:306-311`, `:950`) |
| `pcre2test` | `src/pcre2test.c` | upstream's own test driver, as an application: it defines `PCRE2_CODE_UNIT_WIDTH` as 0 itself (`src/pcre2test.c:313`) and links the core and the POSIX wrapper (`build.zig:316`, `:994`) |

`src/pcre2grep.c` is **not** built. It needs zlib and libbz2, neither of which
this package may depend on, and no step in this graph reaches it.

`config.h` is generated **per target** from `src/config-cmake.h.in` and every
value in it is derived from `target.result`, never from the machine running the
build, so a foreign target gets a `config.h` describing the foreign target
(`build.zig:862-925`). The `#cmakedefine` entries the template also declares are
left undefined on purpose: none of them is available in a build that uses Zig's
bundled C compiler and Zig's libc.

The remaining values are upstream's own defaults for a build with no configure
script (`build.zig:913-922`): `PCRE2_LINK_SIZE 2`, `PCRE2_PARENS_NEST_LIMIT 250`,
`PCRE2_HEAP_LIMIT 20000000`, `PCRE2_MAX_VARLOOKBEHIND 255`, `PCRE2_MATCH_LIMIT
10000000`, `PCRE2_MATCH_LIMIT_DEPTH` equal to the match limit,
`PCRE2GREP_BUFSIZE 20480`, `PCRE2GREP_MAX_BUFSIZE 1048576`, `NEWLINE_DEFAULT 2`
(PCRE2's LF convention). `PCRE2_EXPORT` is
`__attribute__((visibility("default")))`, and the core is compiled with
`-fvisibility=hidden` so internals stay internal in a static archive linked into
somebody else's shared library (`build.zig:138-146`, `:911`).

`HAVE_BUILTIN_ASSUME` is left null on purpose: `zig cc` has no
`__builtin_assume` spelling this code can use, while the overflow, unreachable
and uninitialized attributes all exist (`build.zig:887-895`).

### How the header is translated

The published interface is a translation of **upstream's own `pcre2.h`** — the
`addWriteFiles` copy of `src/pcre2.h.generic` made at `build.zig:460-461`, which
is the same copy every C unit of the core compiles against — read through the
fork-authored aggregate `translate.h`. Nothing of PCRE2's is restated by hand:
no prototype is copied into a Zig file, no declaration is written down, and no
feature is published that the header does not declare.

`translate.h` is a macro prelude and one include. `PCRE2_CODE_UNIT_WIDTH` is
configured by `build.zig` on whichever line reads the header for the target, and
defaulted in the file itself, because `src/pcre2.h.generic:1057-1059` hard-errors
without it; `PCRE2_STATIC` is configured on that same line and follows the
linkage the build produced; and `__int128_t` / `__uint128_t` are the
**compiler's own** typedefs, restated under the compiler's own
`#if defined(__SIZEOF_INT128__)` because no header declares them.

Which front end reads that aggregate is decided per target by the private
`aggregateRoute` (`build.zig:635-700`), from `target.result` and never from the
host:

* **A GNU-libc target — Aro alone.** Aro, which is what `zig translate-c` parses
  with, preprocesses `translate.h` for itself and parses the result. It is the
  one C library in the matrix where that is true: the target's own preprocessor
  leaves five glibc `bits/floatn*` `typedef`s in its output, Aro holds those
  five names as builtin type specifiers of its own, and reading that output
  produced eleven translation errors on each of the three GNU-libc `check`
  cells before the route was split.
* **Every other target — the target's own preprocessor, then Aro.**
  `preprocessedAggregate` (`build.zig:825-851`) runs
  `zig cc -E -dD -fno-blocks -x c` over `translate.h` with the same `-target`,
  the same `-I` on that header copy and the same `-D` values as the C core's own
  compile line, and Aro parses what that produced. `-dD` keeps the `#define`
  lines in the text Aro reads, so the header's macros still reach Zig as
  constants; `-fno-blocks` puts the two front ends in one dialect, because
  Clang's driver enables blocks by default for a Darwin target and the Darwin C
  library then declares six `*_b` entry points that take a block pointer, which
  Aro has no syntax for.

Both routes read the same header, on the same include path, with the same two
declaration macros, and each declaration macro is defined exactly once — on the
preprocessing line where there is one, on the translation line where there is
not. `systemAggregate` (`build.zig:702-726`) is the separate third input that
`-fsys=pcre2-8` uses. [`FORK-NOTES.md`](FORK-NOTES.md) § 17-20 records each of
those translation failures, the receipt that observed it, and the boundary it
is bound to.

### What was removed, and why

Upstream's graph declares a lazy `sljit` package dependency and a
`-Dsupport_jit` option, because `pcre2_jit_compile.c` compiles against sljit.
`.gitmodules:1-3` names `deps/sljit` as a git submodule from
`https://github.com/zherczeg/sljit.git`, and **`deps/sljit` is an empty
directory in this checkout**: the submodule was never populated. Upstream's
option therefore resolves the source either from that submodule or from
`b.lazyDependency("sljit", …)`, which is a network fetch. A fork whose contract
is that the primary core compiles from its own tree with no build-time download
can use neither, so the dependency and the option are **gone rather than left to
fail later (`build.zig:32-42`, `build.zig.zon:16-27`). The consequence is the
`SUPPORT_JIT 0` above, which is a deliberate configuration and not a gap.

### Linkage

`-Dlinkage` is accepted by the main graph. Its default is derived from the
target, not from the host: **dynamic on a GNU-libc target, static on every
other** (`build.zig:223`). The same value drives the `PCRE2_STATIC` declaration
macro on the C compile line (`build.zig:475-484`) and on whichever line reads
the header for the target (`build.zig:540-558`, `:557-572`, `:846`), so the
declaration decoration and the archive that was produced are one fact.
`src/pcre2.h.generic:56-63` reads `PCRE2_STATIC` only under `defined(_WIN32)`,
so on an ELF target and on macOS the macro is never read and saying which
linkage was chosen there is a statement about this build graph, not about the
header.

### System-library mode

`-fsys=pcre2-8` is a real `b.systemIntegrationOption` (`build.zig:248`). In that
mode nothing in this tree is compiled: no artifact, no generated `config.h`, no
copied `pcre2.h`. Instead:

* the facade module calls `Module.linkSystemLibrary("pcre2-8", …)` with
  `use_pkg_config = .no` — `libpcre2-8` is the name Debian, Ubuntu, Fedora,
  Homebrew and MSYS2 all install, and no pkg-config query is needed to
  find it: the `.pc` file is named after the library
  (`libpcre2-8.pc`), not the project (`build.zig:601-605`);
* `preferred_link_mode` is named rather than defaulted. It defaults to
  **dynamic**, and `-Dlinkage` names it instead in that mode
  (`build.zig:224-233`). It maps to the linker flag `-search_paths_first` for
  dynamic and `-search_paths_first_static` for static, so the default system
  build's linker line is unchanged and the static case says out loud that a
  static archive is wanted (`build.zig:610-618`);
* the translation reads a **generated aggregate that includes `<pcre2.h>` by
  angle brackets** (`build.zig:702-726`, used at `:530`), so it resolves through the
  own system include search and translates the header that is actually installed
  beside the library that gets linked. No include path of this graph is added in
  that mode. Translating this repository's 10.49 header against an older
  installed library would bind an ABI that may not be the one on disk;
* `PCRE2_STATIC` follows the same one value, so the decoration describes the kind
  of library that was asked for (`build.zig:540-558`);
* the mode refuses a foreign `-Dtarget` and a non-8-bit width rather than
  producing something meaningless (`build.zig:256-261`).

Which kind of library a given machine actually has installed is that machine's
arrangement, not a fact this graph can read, so the macro above describes the
kind that was **asked for**. The mode **has** now been run in this workspace,
against an installed **10.45**: the Debug suite came back `9 pass, 1 fail (10
total)` on one fixture's compile-error **offset** alone, while the smoke and the
consumer package both passed and both printed `linked against 10.45 2025-02-05`.
System-mode ReleaseSafe was not run. The fixtures the tests replay are pinned to
10.49 by construction, so that disagreement is exactly the possibility this mode
exists to expose; `verify.yml`'s `system` job reports the installed version for
that reason, and the rule is that such a difference is read against that version
and never fixed by loosening a fixture. The receipts, the named failing case and
what is and is not known about its cause are in
[`README.zig.md`](README.zig.md) § "Verification status", which is the one place
this package's gate states are written down.

## What is upstream's and is shipped unmodified

Everything named in `build.zig.zon` `.paths` that this fork did not write:
`src/` (upstream's whole C tree, including the 31 units compiled, the width-neutral
public header, the CMake config template, the POSIX wrapper, the test driver and
the character-table source), `doc/` (upstream's manual, under the library's own
terms), `LICENCE.md`, `COPYING`, `AUTHORS.md`, `SECURITY.md`, `HACKING`,
`INSTALL`, `README.md`, and `testdata/` in full. No upstream source, header,
test, licence or fixture byte is edited.

## What is carried but is not part of the package

The autotools inputs (`configure.ac`, `configure`, `aclocal.m4`, `m4/`,
`Makefile.am`, `Makefile.in`, `depcomp`, `install-sh`, `ltmain.sh`, `missing`,
`ar-lib`, `compile`, `config.guess`, `config.sub`, `test-driver`, `maint/`),
`CMakeLists.txt`, `cmake/`, `BUILD.bazel`, `MODULE.bazel`, `pcre2-config.in`,
`libpcre2-*.pc.in`, `libpcre2-*.sym.in`, `vms/`, `patches/`, `RunTest`,
`RunGrepTest` and their `.bat` forms, `perltest.sh`, `NON-AUTOTOOLS-BUILD`,
`ChangeLog`, `NEWS`, `SUPPORT-LIFECYCLE.md`, `.editorconfig`,
`.gitattributes`, `.gitmodules`, `deps/` and `.github/workflows/{build,dev,codeql,
clang-analyzer,pages,scorecards,sync,cifuzz}.yml` all stay in this repository
for provenance and audit. None of them is in `.paths`, none is referenced by the
Zig build, and none is hashed by `UPSTREAM.sha256`; a dependent that fetches
this package will not receive them.

`NEWS` and `ChangeLog` are worth keeping for one specific fact: **`NEWS:4-20`
records 10.49 as a security-only release for GHSA-r9hj-j2rw-4q3m**, an
out-of-bounds write reachable only through the `pcre2_jit_stack_create()` and
`pcre2_jit_stack_assign()` APIs, and states at `NEWS:19` that it is not a
regression and affects 10.48 and earlier. This fork builds with JIT off and
exposes no JIT stack API through the typed facade, so the advisory's reachable
path is not compiled into the archive this package produces — but that is a
statement about *this* fork's configuration, not a claim about the general
advisory, and a consumer that links a system PCRE2 in `-fsys` mode must read it
for the release that library is.

Upstream's workflows are left exactly as they arrived and are not retargeted at
this fork's infrastructure. This fork's own workflow is
`.github/workflows/verify.yml`, which is a new file.

## Integrity

`UPSTREAM.sha256` holds **59** records: the SHA-256 of every upstream-owned byte
this package compiles, installs, reads as an oracle, or publishes terms for, plus
this fork's own fixture module. Check it with:

```
sha256sum -c UPSTREAM.sha256
```

The path set is exactly:

| Group | Count | What it is |
|---|---|---|
| `src/*.c` — the 30 core units | 30 | the explicit list in `build.zig:90-121` |
| `src/pcre2_chartables.c.dist` | 1 | the generated character tables, compiled under the name `pcre2_chartables.c` |
| `src/pcre2posix.c`, `src/pcre2test.c` | 2 | the two artifacts this graph also builds |
| `src/pcre2.h.generic`, `src/config-cmake.h.in` | 2 | the public header that is copied to `pcre2.h` and installed, and the `config.h` template |
| the internal headers the core includes | 12 | `pcre2_internal.h`, `pcre2_compile.h`, `pcre2_intmodedep.h`, `pcre2_ucp.h`, `pcre2_util.h`, the four `pcre2_jit_*_inc.h`, `pcre2_printint_inc.h`, `pcre2_ucptables_inc.h`, `pcre2posix.h` |
| `LICENCE.md`, `COPYING`, `AUTHORS.md` | 3 | the licence texts and the authorship record |
| `testdata/testinput2`, `testoutput2`, `testinput5`, `testoutput5`, `testinput6`, `testoutput6`, `testinput15`, `testoutput15` | 8 | the upstream `pcre2test` input and expected-output pairs the fixtures cite by file and line |
| `testdata/foundation-fixtures.zig` | 1 | **this fork's own** fixture module — see below |

The last record is the only one that is not upstream's, and it is here on
purpose: the module holds every expected answer the tests compare against, so a
silent edit to it would move the oracle rather than break a build. Hashing it
means such an edit fails the integrity check loudly. The provenance it records
was spot-checked against the oracle files while this record was written — for
example `testdata/testoutput2:7310-7323` really does hold the name table and the
three `\g` lines for `/(?<abc>x)(?'xyz'y)/I`, and
`testdata/testoutput15:128-139` really does hold the "No match", `-47` and `-53`
answers for `(a+)*zz`.

Deliberately absent from the record, each for a stated reason:

* `.gitignore` — upstream's list is kept verbatim and this fork appends to it,
  so the file is not byte-identical to upstream's.
* `build.zig`, `build.zig.zon`, `translate.h`, `zig/`, `tests.zig`, `smoke.zig`,
  `consumer/`, `cross-test.profile.sh`, `.github/workflows/verify.yml`, `UPSTREAM.md`, `NOTICE.md`,
  `CHANGELOG.md`, `FORK-NOTES.md`, `README.zig.md` — this fork's own files,
  listed in [`NOTICE.md`](NOTICE.md).
* `UPSTREAM.sha256` itself — a record cannot contain its own digest.
* the rest of `testdata/` — upstream ships it whole and the package ships it
  whole, but only the eight files above are cited line by line by the fixture
  module. The rest travel for provenance and for upstream's own `RunTest`;
  nothing in this package reads them.
* the rest of `src/`: `config.h.generic`, `config.h.in`, `pcre2.h.in`,
  `libpcre2-*.sym.in`, the two EBCDIC character-table variants, `pcre2demo.c`,
  `pcre2grep.c`, `pcre2posix_test.c`, `pcre2test_inc.h`, `pcre2_fuzzsupport.c`
  and `pcre2_jit_test.c` — none of them is compiled by this graph, read by the
  facade, or used as a test oracle. They are listed here so that the record's
  scope is a decision rather than an accident.

**How the digests were produced.** Each file was read as raw bytes with Bun's
`Bun.file(path).arrayBuffer()` and hashed with `crypto.createHash("sha256")`
from `node:crypto`, in an `eval` cell, on 2026-10-01. No shell hashing command
and no git command was used to produce them. No receipt in this package's set
reports the hashing tool's version, so this states the method and claims no
version of it.

**What the record establishes.** If it validates, the bytes a build compiles,
the header it translates, the licence a redistributor must reproduce and the
oracle bytes the tests compare against are the bytes this record pins, and any
later edit to one of those 59 files fails the check loudly.

**What it does not establish.** It is not a signature, not a Git object id, and
not a re-derivation from commit
`6f9d7c1373262c541324a16a358785b33ef116cf`: it is a hash of this working tree.
That the tree equals that commit rests on the import and on the archive digest
above, both of which the driver recorded, not on anything computed while writing
this file. Replaying the check against upstream is the driver's job and needs a
re-fetch:

```
git -C <clone> archive --format=tar 6f9d7c1373262c541324a16a358785b33ef116cf | sha256sum
```

The output must read
`e2353f82162d1860ebfbce03c227f539285ab8503e4d57617370b824c4fbde11  -`,
and `sha256sum -c UPSTREAM.sha256` must then report 59 records and no failures.

**Status: `observed pass`, exit 0.** `sha256sum -c UPSTREAM.sha256` reported 59
records with every line `OK` in this workspace on 2026-10-01
(`local://foundation-expansion-pcre2-immutable-source-integrity-168.log`), and
`.github/workflows/verify.yml` runs the same command as the first step of its
native job, so the record is checked by this repository's CI as well. Every other
gate state is listed once, in [`README.zig.md`](README.zig.md) §
"Verification status".

## Synchronising with a new upstream release

1. `git fetch upstream`, check out the new tag, and read `configure.ac:11-14`
   (or the substituted `src/pcre2.h.generic:44-47`) for the new `pcre2_major`,
   `pcre2_minor`, `pcre2_prerelease` and `pcre2_date`. Those macros, not the tag
   spelling, are the version.
2. Re-read the JIT submodule: if `deps/sljit` is now populated, the removal in
   `build.zig.zon` and the `SUPPORT_JIT 0` in `build.zig` are decisions to
   re-take deliberately, and `src/pcre2_jit_compile.c` stops being an empty unit.
   Do not reintroduce the lazy dependency without a decision about the
   no-download contract.
3. Re-read the compile list. A new translation unit must be added to
   `core_sources` by hand, and a removed one must be removed by hand, because
   the list is explicit on purpose.
4. Replace the upstream files in place. Do not hand-patch upstream source to
   make a build problem go away.
5. Re-read `LICENCE.md`, and re-read the per-file terms the new release adds,
   before changing any entry in `NOTICE.md`.
6. Re-derive the fixture provenance: the `testdata/testoutput*` line numbers
   every case cites move when upstream re-orders or extends its test files. Each
   case in `testdata/foundation-fixtures.zig` names its own file and line, so a
   pin bump is a search through that file, not a guess.
7. Regenerate `UPSTREAM.sha256` over the same path set with the same method and
   update the count in its header comment and in this file.
8. Bump `.version` in `build.zig.zon` to the new `major.minor.0`, update the pin
   in this file and in `README.zig.md`, and add one numbered `CHANGELOG.md`
   entry.

## See also

* [`NOTICE.md`](NOTICE.md) — attribution, the licence and data split, every file
  this fork adds or edits, and the per-file exceptions.
* [`README.zig.md`](README.zig.md) — how to build, import and call the package.
* [`CHANGELOG.md`](CHANGELOG.md) — numbered fork-only divergences.
* [`FORK-NOTES.md`](FORK-NOTES.md) — the problems met while doing this, and
  what was decided.
* [`UPSTREAM.sha256`](UPSTREAM.sha256) — the integrity record itself.
