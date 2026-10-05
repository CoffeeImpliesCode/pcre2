# CHANGELOG — fork-only divergences

Upstream's history lives in its own repository. This file records **only** what
this fork changed relative to `PCRE2Project/pcre2` at tag `pcre2-10.49`,
commit `6f9d7c1373262c541324a16a358785b33ef116cf`, and it is written so a
re-sync can replay it. Numbers are stable identifiers; never renumber them.

Statuses are the workspace's: **observed** means a driver ran the gate and the
output is in the named receipt; **pending** means the change has landed and no
gate has looked at it yet; **not run** means no receipt exists at all. No entry
below claims a gate result that was not produced.

`README.zig.md` § "Verification status" is the **one** current gate table. It
carries every receipt — the Debug and ReleaseSafe suites with smoke and install,
the consumer package, the six cross-target `check` compiles, the full
53-platform `cross-test` matrix, the integrity check, the installed-C gate, and
the `-fsys=pcre2-8` runs against an installed 10.45 — and, for the current
filtered-package proof, a pointer to the driver-owned ledger rather than a
result of its own. This file records the divergences and points there instead of
keeping a second list.

---

## 1. Added the Zig 0.16 package

`build.zig`, `build.zig.zon`, `translate.h`, `zig/root.zig`, `tests.zig`,
`smoke.zig`, `consumer/`, `.github/workflows/verify.yml`, `UPSTREAM.md`,
`UPSTREAM.sha256`, `NOTICE.md`, `README.zig.md`, `FORK-NOTES.md` and this file
are new. New module: `pcre2`. New artifacts: the `pcre2-8` library — dynamic
by default on a GNU-libc target, static otherwise — plus the installed
`pcre2.h`, `pcre2-posix` plus `pcre2posix.h`, and `pcre2test`.
`build.zig.zon` declares no dependencies and nothing is downloaded. No upstream
source, header, test, licence or fixture byte is touched.

**Status.** `observed`. The smoke run passed
(`local://foundation-expansion-pcre2-api-smoke-proof-110.log`, exit 0), and the
install gate that had never produced a result now does
(`local://foundation-expansion-pcre2-capture-install-160.log`, exit 0,
`Build Summary: 14/14 steps succeeded`). The earlier red install receipt
(`…-current-install-61.log`, exit 1) was a configure-time error before any step
ran, so it said nothing about the install itself; the current receipts for every
gate are in `README.zig.md` § "Verification status".

## 2. Extended upstream's own Zig graph instead of replacing it

Upstream ships a Zig 0.16 build graph in 10.49. This fork keeps it: the
`src/pcre2.h.generic` → `pcre2.h` copy through `addWriteFiles`, the `config.h`
generation from `src/config-cmake.h.in` through `addConfigHeader`, the explicit
translation-unit list, and the `linkage` / `sanitize_c` / `code-unit-width`
options (`build.zig:5-9`). What it adds is the `pcre2` module registered as a
package module, the `test` / `smoke` / `check` steps, the six-target
compile-only check, and the system option in entry 5.

**Status.** All six `check` targets compile without execution. Current
baseline receipts report 9/9 steps on the three GNU-libc Linux cells and
10/10 on macOS, Windows and WASI, whose extra step is real-target header
preprocessing. The earlier uniform 9/9 counts are history; see `README.zig.md`.

## 3. Compiled the full Unicode core at all three widths — 31 translation units each, explicitly

The core is the 30 entries of `core_sources` (`build.zig:90-121`) plus
`src/pcre2_chartables.c.dist`, which ships under a `.dist` name and is copied
to `pcre2_chartables.c` and compiled (`build.zig:486-494`). That is the
interpreter (`pcre2_match.c`), the DFA matcher (`pcre2_dfa_match.c`) and the
complete Unicode property machinery — not a subset chosen for convenience. The
list is explicit rather than globbed so a new upstream unit cannot enter the
archive without a decision here.

**The same list is compiled three times, once per code-unit width, and the
three closures go into one artifact** with one name, one soname and one
version. `-Dcode-unit-width` selects which width that artifact is *called* and
which width the typed facade speaks; it does not select what the artifact
contains, so `pcre2_match_8`, `_16` and `_32` all resolve in a width-8 build.
Upstream's internal names are width-suffixed for exactly this coexistence
(`src/pcre2_internal.h:2196-2200`), so nothing collides. This was recorded as
"the full 8-bit core" when the artifact carried one closure; the design, the
unit list and the number of translation units per closure are unchanged.

`src/pcre2posix.c` and `src/pcre2test.c` are built as two more artifacts from
the same tree and the same generated `config.h`, so a dependent needs no path
into the sources. `src/pcre2grep.c` is not built: it needs zlib and libbz2.

**Status.** `observed` for the native archive — every receipt above and below
shows `compile lib pcre2-8 Debug native` succeeding, including the passing
smoke run.

## 4. Removed the `sljit` dependency and `-Dsupport_jit`, and turned JIT off

Upstream declares a lazy `sljit` package dependency and a `-Dsupport_jit`
option. `.gitmodules:1-3` names `deps/sljit` as a submodule from
`https://github.com/zherczeg/sljit.git`, and **`deps/sljit` is an empty
directory in this checkout**. Upstream's option therefore resolves the source
either from that submodule or from `b.lazyDependency("sljit", …)`, which is a
network fetch. A fork whose contract is that the primary core compiles from its
own tree with no build-time download can use neither, so both are **gone rather
than left to fail later** (`build.zig:27-39`, `build.zig.zon:16-27`).

`SUPPORT_JIT` is therefore 0 in the generated `config.h` (`build.zig:670-671`).
`src/pcre2_jit_compile.c` stays in the compile list and contributes nothing:
with `SUPPORT_JIT` at 0 every definition in it is behind `#if`.

**Status.** `source-confirmed`. The consequence is observable: the passing smoke
run's own header says "About JIT: this fork builds with `SUPPORT_JIT` off, so
every number printed here is the interpreted answer."

## 5. Added a real `-fsys=pcre2-8` system-library mode

A `b.systemIntegrationOption`, not a flag. In that mode nothing in this tree is
compiled; the module links an installed `libpcre2-8` with `use_pkg_config = .no`
and translates the **installed** `<pcre2.h>` by angle brackets through the
target's own system include search (`build.zig:568-590`, `:603-617`). Translating
this repository's 10.49 header against an older installed library would bind an
ABI that may not be the one on disk, so the header and the library are one fact.

**Status.** `source-confirmed`, and `observed` against an installed **10.45**:
the Debug suite returned `9 pass, 1 fail (10 total)` on one fixture's
compile-error offset, while `smoke` and `consumer` both exited 0 and both
printed `linked against 10.45 2025-02-05`. System-mode ReleaseSafe was not run.
The receipts, the named failing case and what is known about its cause are in
entry 20 and in `README.zig.md` § "Verification status".

## 6. Added the Zig facade over the translated header

`zig/root.zig` publishes `Regex`, `MatchData`, `MatchContext`, `version`, the
option structs, the outcome unions, the error set, and `pub const c` — the
complete translation of `src/pcre2.h.generic`, including the 16- and 32-bit
declarations.

The typed surface is **width-parameterised**: `Surface` resolves to the typed
surface of the compiled width, and the short names below are that width's own.
It wraps `pcre2_match_N`, the DFA matcher, `pcre2_substitute_N`, the substring
helpers, `pcre2_get_mark_N`, the callout and enumeration entry points, the
convert context, serialization, the JIT entry points and the POSIX wrapper.
`pub const c` remains the escape hatch for everything it does not.

**Allocation: none, and no allocator crosses the boundary.** PCRE2 allocates
`pcre2_code`, `pcre2_match_data` and `pcre2_match_context` with `malloc` and
frees them itself; the facade passes no Zig allocator, creates no general
context and installs no global hook, so the Zig test framework cannot supply a
leak oracle for those blocks and the ownership test checks the transition
instead of pretending to observe a free.

**Status.** `observed`. The full suite is green in both modes — Debug and
ReleaseSafe, `10/10 tests passed` each — so the smoke path, the Debug suite that
was `7 pass, 2 fail` in receipt 117, and every repair below it have been run.

## 7. Transcribed upstream's published answers into a fixture module

`testdata/foundation-fixtures.zig` is **fork-authored** and holds 15 known
answers. Thirteen are read out of this repository's own `testdata/`, which is
upstream's `pcre2test` input and expected output for 10.49, and each names the
file and line it came from; two are hand-derived from `src/pcre2_valid_utf.c`
and `src/pcre2_match.c` and show the derivation in full, because no checked-in
test output exercises a malformed subject.

This is the primary fixture, and it is not a same-code round trip: the expected
captures and rejections were transcribed from a file this fork did not write and
does not execute, and the line citations were spot-checked against those files
while the integrity record was written. The round trip through this fork's own
C is not the oracle and is not treated as one.

`src/pcre2_chartables.c.dist` and the hand-built limit subjects are the two
places where a mistyped transcription could pass unnoticed, so both are built
by construction with a `comptime` length check that fails to compile if the
length is wrong.

**Status.** `observed`. The table replays inside a green suite: `10/10 tests
passed` in both Debug and ReleaseSafe, against this tree's own 10.49 library.

## 8. Added the deterministic smoke program

`smoke.zig` matches one anchored pattern with three named groups against one
literal subject, compares every capture with a byte offset worked out by hand,
then matches a second subject that must not match and asserts that **no capture
is readable afterwards**. Each comparison is an ordinary comparison returning an
error, so the process exits non-zero; a debug assertion would be compiled out of
a release build, which is not a check.

**Status.** `observed pass`, first in
`local://foundation-expansion-pcre2-api-smoke-proof-110.log` and again, on the
current sources, in `local://foundation-expansion-pcre2-capture-smoke-159.log`
— including its last two lines, where no capture from the failed attempt is
readable.

## 9. Added the consumer package

`consumer/` is a separate package that depends on this one by relative path and
resolves `dep.module("pcre2")`. It parses `level[id] message` lines, where the
bracketed id is optional and sometimes does not take part, and assembles the
result into a caller-owned buffer with no allocation.

**Status.** `observed pass`. The one red receipt,
`local://foundation-expansion-pcre2-current-consumer-64.log`, is exit 1 with a
configure-time error in this package's `build.zig`, so it said nothing about
the consumer's own sources; `…-capture-consumer-161.log` runs them and exits 0.

## 10. Wrote this fork's own CI and left upstream's alone

`.github/workflows/verify.yml` is new and names only this repository: a native
build, an installed-header C gate that compiles, links and runs against the
*installed* `pcre2.h` and `pcre2-posix`, Debug and ReleaseSafe tests, smoke, one
`check` job per cross target, the `-fsys=pcre2-8` job, and the consumer package.
Upstream's eight workflows are carried untouched, still describing how upstream
tests PCRE2 with autotools and CMake, and are not retargeted at this fork's
infrastructure.

**Status.** **Not run.** No execution of this repository's CI has produced
anything, and the workflow's own C gate program has been compiled and run
outside it — see entry 19 — but the workflow as a workflow has never executed
here.

## 11. Appended ignore re-inclusions, the only upstream-file edit

`.gitignore` keeps every upstream entry verbatim and unedited
(`.gitignore:1-128`) and gains one comment block plus `!translate.h`,
`!cross-test.profile.sh`, `!/zig/`, `!/tests.zig`, `!/smoke.zig`,
`!/consumer/`, `!/testdata/` — seven current negations (`.gitignore:150-156`).
The profile line was added in entry 23; the initial block had six.
The negations are there because the file is upstream's,
is shared with every other PCRE2 checkout, and the ordinary way a fork's own
file goes missing from a package is an upstream rule broadening to cover it. No
upstream entry is removed or narrowed. Because the file is not byte-identical
to upstream's, it is deliberately absent from `UPSTREAM.sha256`.

**Status.** `source-confirmed` from the file. Nothing hashes or checks this file,
deliberately, since its append is what makes it differ from upstream's; that is
why the append is written out in `NOTICE.md` and here instead.

## 12. Added the provenance, integrity and documentation set

`UPSTREAM.md` (pin, what is compiled and with which switches, what was removed
and why, system mode, the archive receipt, the integrity record's scope, the
sync procedure), `UPSTREAM.sha256` (59 records, `sha256sum -c` replayable),
`NOTICE.md` (per-path licence and data grants, per-file exceptions, the BSD
obligations that apply, every file this fork adds or edits), `README.zig.md`
(build, import, use, every exposed operation, the lifetime and status contracts,
the six target commands, the observed and unrun gates), `FORK-NOTES.md` (the
lessons) and this file.

**Status.** `source-confirmed` for the record, and `observed`: all 59 digests
were computed from the tree by raw-byte read and re-derived from the written
file before this file was written, and `sha256sum -c UPSTREAM.sha256` then
reported 59 records with every line `OK` (exit 0).

**Superseded in part by entry 38.** That `OK` result was true of the tree this
entry measured. The record for `testdata/foundation-fixtures.zig` no longer
matches, because that file — the fork's own, pinned deliberately — was edited
later; the 58 upstream records still verify. The fix is to re-derive that one
digest, and it is the owner's to make.

---

## The repair wave

Entries 13 to 18 are corrections. Each was found by a red gate or by a
reviewer's `source-confirmed` finding, and each is this fork's mistake rather
than a defect in PCRE2.

## 13. Fixed the direction of the invalid-UTF range

`-3...-23` is a range whose start is above its end, which Zig rejects at
compile time:

```
zig/root.zig:563:15: error: range start value is greater than the end value
           -3...-23, -36 => .{ .invalid_utf = .{ .code = rc, .text = diagnostic(rc) } },
           ~~^~~~~~
```

`local://foundation-expansion-pcre2-repaired-debug-27.log`, exit 1. The
underlying values are upstream's: `PCRE2_ERROR_UTF8_ERR1` through
`PCRE2_ERROR_UTF8_ERR21` are -3 through -23, and `PCRE2_ERROR_BADUTFOFFSET` is
-36, so the arm is `-23...-3, -36`.

**Status.** `observed` for both the failure and the repair: the suite is green
in Debug and ReleaseSafe, so the reversed range no longer compiles out.

## 14. Made the test's group-index conversion bounded

`groupRange` takes a `u32`; the fixture loop's index is a `usize`, and the
compiler said so:

```
tests.zig:389:50: error: expected type 'u32', found 'usize'
       const range = (try match_data.groupRange(i)) orelse return error.FixtureMismatch;
```

Same receipt. The fix is an explicit bounded conversion, not a cast, so the
conversion is checked where it happens and survives an optimized build.

**Status.** `observed` for both the failure and the repair: the bounded
conversion is in the sources the green suites were built from.

## 15. Stopped reporting a capture from an attempt that did not match

**This was a real out-of-bounds read, not a documentation gap.** Reusing one
`MatchData` across `(\d+)-(\w+)` matching `"123-abc"` and then a non-match on the
one-byte subject `"z"` left PCRE2's offset vector holding group 2 at bytes
4..7 — offsets past the end of `"z"`. The facade returned them, and `group()`
indexed the new subject with the old subject's offsets: a bounds panic in Debug
and ReleaseSafe, and a silent read of unrelated memory in ReleaseFast.

Upstream's own contract is the cause and it is documented, not inferred: "After
a failed match attempt, the contents of the ovector are unchanged"
(`doc/html/pcre2api.html:3330-3334`), and `src/pcre2_match.c:1045-1053` writes
`ovector[]` only on the path that matched.

The fix is a chosen contract, not a patch: `MatchData` carries an explicit
validity flag that `Regex.match` **clears for every attempt**, including one
refused before any C runs, and sets only when `pcre2_match_8` returned zero or
more. `groupRange` and `group` answer null whenever the flag is false. A group
number past the block's capture count is still `error.NoSuchGroup`, because that
is a statement about the index and holds whatever the block last did.

The alternative — returning the previous attempt's offsets, or keeping a silent
borrow of the previous subject whose lifetime the caller may already have ended
— is not taken. The raw C escape hatch still gives a caller upstream's own
behaviour, and `Regex.subject` is public so a caller who deliberately wants the
last subject can read it.

**Status.** `observed`. The stale-offset condition is covered by a permanent test
in `tests.zig` — `an attempt that did not match leaves nothing readable,
whatever the last one found` — and demonstrated by `smoke.zig`'s last two lines,
and that test passes in both Debug and ReleaseSafe.

## 16. Replaced a dangling stack borrow in `version` with a caller-owned buffer

`version()` built its answer in a function-local buffer and returned a slice of
it, so the returned pointer outlived the frame. The first repair attempt made it
worse in a different way — it declared `[:0]const u8` and produced a `[]const
u8`:

```
zig/root.zig:819:49: error: expected type '[:0]const u8', found '[]const u8'
           return @as([*:0]const u8, @ptrCast(&buffer))[0..@intCast(written - 1)];
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~
```

`local://foundation-expansion-pcre2-latest-smoke-88.log`, exit 1. The real bug
was the borrow, not the sentinel.

The shipped contract is `pub fn version(buffer: []u8) Error![:0]const u8`:

* the required size is queried first, with
  `pcre2_config_8(PCRE2_CONFIG_VERSION, null)`, which returns `1 + strlen(v)`
  and writes nothing (`src/pcre2_config.c:73-103`, `:241-242`);
* that count **includes the terminating NUL**, so it is compared against
  `buffer.len` as an ordinary comparison **before** the call that writes —
  `pcre2_config_8` takes a `void *` and cannot know the capacity. A short buffer
  is `error.VersionBufferTooSmall` and not one byte of the caller's storage
  changes;
* a non-positive answer is `error.VersionUnavailable`. There is **no
  placeholder string**: reporting `"unknown"` would report a release the archive
  was never built with;
* the answer is `buffer[0..len :0]`, tied to the caller's own storage. No static
  cache, no global, no allocation, no no-argument alias;
* `PCRE2_CONFIG_VERSION` is used symbolically, not as a literal `11`.

Every caller was migrated: `smoke.zig`, `consumer/src/main.zig` and `tests.zig`
each own a 64-byte local buffer, which is past the 24 code units every release
so far has needed (`doc/pcre2.txt:1468-1469`).

**Status.** `observed` for both the compile failure and the repair. The smoke
run prints `pcre2 smoke, linked against 10.49 2026-09-28` from the caller's
buffer, and the version-buffer contract is a permanent test
(`the version answer is the caller's own buffer, and a short one is refused`)
that passes in both Debug and ReleaseSafe.

## 17. Made the system mode's header, linker decoration and library one fact

`-Dlinkage` was reaching the in-tree build's `PCRE2_STATIC` macro but not the
system mode's, so in `-fsys` mode the declaration decoration and the library
the linker was asked for could describe two different things. `linkage` now
also names the kind of *installed* library to bind to, `preferred_link_mode` is
passed explicitly rather than defaulted, and `PCRE2_STATIC` follows the one
value. The default is dynamic in system mode because system mode builds no
artifact of its own and `Module.linkSystemLibrary` prefers dynamic when the
option is absent.

The reviewer's associated claim — that this would fail at link time with a
`0.65` confidence estimate — is **not** encoded as a fact anywhere. It is
`source-confirmed` as a code observation and unobserved as a runtime outcome.

Two documentation corrections came with it: the fork's Zig fixture module was
missing from the `fmt` path list, and the system job now says outright that
three fixture cases pin compile rejections that only 10.49 produces, so a red
system gate is read against the installed version the job printed rather than
fixed by loosening a fixture.

**Status.** `source-confirmed`, and `observed` — see entry 5 for the receipts
and entry 20 for what the run against an installed 10.45 answered.

## 18. Fixed `Regex.nameAt` answering null for a name the pattern does declare

`Regex.nameAt(index)` returned null for valid names. The first Debug gate that
reached the test binary reported it twice:

```
run test 7 pass, 2 fail (9 total)
error: 'tests.test.every known answer in the fixture table holds' failed:
       tests.zig:83:63: const entry = compiled.nameAt(@intCast(i)) orelse return error.FixtureMismatch;
error: 'tests.test.a name the pattern did not declare, and a name too long to declare, are both null' failed:
       tests.zig:294:41: const last = regex.nameAt(1) orelse return error.FixtureMismatch;
```

`local://foundation-expansion-pcre2-api-debug-proof-117.log`, exit 1. The
second failure is the sharper one: the test's own control, `nameAt(2)` past a
two-entry table, is expected to be null and the facade agrees, while `nameAt(1)`
— a name the pattern really declares — is also null.

**Cause.** Not indexing and not the table. `fromRaw` declared the
`PCRE2_INFO_NAMETABLE` out-parameter `var name_table: ?[*c]const u8 = null;`
and passed `&name_table` to `pcre2_pattern_info_8`. **A Zig optional of a C
pointer is not a pointer**: `?[*c]const u8` is 16 bytes, an 8-byte payload
with the tag byte after it, because only `?*T` is given the null-pointer
representation. The C function writes `sizeof(PCRE2_SPTR)` = 8 bytes into the
payload (`src/pcre2_pattern_info.c:229-232`) and never touches the tag, so the
value read back was **null for every compiled block** and `nameAt` took its
`orelse return null` guard on every in-range index. The other three queries
were right — `capture_count` and `name_count` are `u32`, four bytes, written
correctly — so `captureCount()` and `nameCount()` passed first and the failure
presented as a table-indexing problem.

**The change.**

* The out-parameter is a bare C pointer, `var name_table: [*c]const u8 =
  undefined`, and `.name_table = name_table` coerces into the **unchanged**
  field type `Regex.name_table: ?[*c]const u8`. A caller can still see an
  absent table; the C just cannot write a tag.
* The four request numbers are no longer the literals `4`, `17`, `18`, `19`.
  They are the translated header's own `PCRE2_INFO_CAPTURECOUNT`,
  `PCRE2_INFO_NAMECOUNT`, `PCRE2_INFO_NAMEENTRYSIZE` and `PCRE2_INFO_NAMETABLE`
  (`src/pcre2.h.generic:450`, `:463-465`), so the request cannot drift from
  the header the archive behind it was compiled against. This matters in
  `-fsys=pcre2-8` mode, where the translated header is the *installed* one.
  `PatternInfoUnavailable` and the release-not-leaked behaviour are unchanged.
* **No signature changed.** `nameAt`, `nameForNumber`, `numberForName`,
  `nameCount`, `captureCount`, `MatchData`, `MatchContext` and
  `version(buffer)` are all as they were. There is no allocator and no copy:
  the name is still the same window on the compiled block, still valid only
  while the `Regex` lives, still not NUL-terminated within the slice. The
  `MatchData.matched` guard and the null-groups-after-a-failed-attempt
  contract are untouched.
* The contract **wording** was wrong and was corrected. The facade claimed
  PCRE2 "stores names in order of first appearance". Upstream keeps the table
  in **name (alphabetical, `strcmp`) order** — the insert routine's header
  says "maintaining alphabetical order" (`src/pcre2_compile_cgroup.c:106-108`),
  the insertion loop is `src/pcre2_compile_cgroup.c:140-161` with the prefix
  rule at `:142-144`, and `pcre2_substring_number_from_name` binary-searches
  the table (`src/pcre2_substring.c:495-523`). `nameCount`, `nameAt`,
  `nameForNumber` and the `name_table` field were reworded accordingly, and the
  claim that the field is "empty when the pattern has no names" was dropped:
  PCRE2 answers a table address for every compiled block, including one with
  no names.
* `tests.zig` gained one test, `the name table is walked in name order, and an
  entry ends at its own NUL`, using `(?<zebra>1)(?<m>2)(?<alpha>3)(?<al>4)` —
  whose table is `al(4), alpha(3), m(2), zebra(1)` — because every existing
  case used two same-length names written in sorted order and so could not
  tell name order from appearance order, or reach the padding boundary
  (`name_entry_size` is sized by the **longest** name in the pattern,
  `src/pcre2_compile.c:5713-5716`, and each entry is zero-padded out to it,
  `src/pcre2_compile_cgroup.c:167-175`, so a name ends at the entry's own NUL
  and not at the end of the entry).
* **No fixture, expected name, expected count or expected capture in
  `testdata/foundation-fixtures.zig` changed.** `build.zig`, `verify.yml`,
  `smoke.zig` and `consumer/` are untouched.

**Status.** `observed red` at receipt 117, and `observed green` since: the suite
is `10/10 tests passed` in Debug and in ReleaseSafe against the current
sources. Receipt 117's `9 total` is now a historical count — the suite has 10
tests, and the tenth is the one entry 18 added.

## 19. Repaired the installed-C gate in this fork's own CI

The native job of `.github/workflows/verify.yml` writes one C program and
compiles, links and runs it against the artifacts `zig build` installed, so the
gate sees the header a dependent gets and the libraries by name through `-l`.
Three things in that program were wrong; none of them is upstream's C.

* **A call to `preg_match` was removed.** PCRE2 is not PCRE1 and exports no such
  name, so that call could only ever have reached the linker, where it names a
  symbol that is never going to be there. What the gate asks about is now
  declared by the installed headers and nothing else, which is also why `-Werror`
  is worth having on the line: a call to a name `pcre2.h` and `pcre2posix.h` do
  not declare fails at the compile, where the diagnostic names the call.
* **`pcre2_substring_copy_bynumber`'s length argument now starts at
  `sizeof group`, not 0.** The argument is an in/out capacity: it arrives as the
  size of the buffer the caller owns and leaves as the number of characters
  copied, NUL excluded. A caller that passes 0 is not asking "does three bytes
  fit", and the check that followed it would have been satisfied by nothing at
  all.
* **`pcre2_get_ovector_count(md) < 3` is checked before the six numbers are
  read.** Those six are three offset pairs — the whole match and the two groups —
  and the loop's capacity is the vector's, not this pattern's group count, so a
  library reporting fewer pairs would otherwise be read past the end of the
  allocation.

The workflow **prints no version or config value of its own**. The only version
it reports is `pkg-config --modversion libpcre2-8` for the package the system job
installed, which is a statement about what is installed rather than about this
tree; the smoke and consumer programs print the version of the library they are
linked against because that is their first output line and it is the caller's
own buffer either way.

**Status.** `observed` for the program: it was compiled with
`zig cc -std=c11 -Wall -Wextra -Werror -DPCRE2_CODE_UNIT_WIDTH=8` against the
prefix this fork's **own** install step produced and run with `LD_LIBRARY_PATH`
on that same prefix, exit 0 and `pcre2 C gate: match=0 unicode=0 posix=0`
(`local://foundation-expansion-pcre2-installed-C-surface-198.log`). The program
compiled in that run is byte for byte the one this workflow writes — the heredoc
in `verify.yml` and the source file were compared line for line while this entry
was written. **The workflow itself remains unexecuted.**

## 20. Recorded what `-fsys=pcre2-8` answers against an installed 10.45

The system mode was run against the machine's **installed** PCRE2, which reports
`10.45 2025-02-05` — older than the 10.49 this tree is a fork of, which is the
only thing that makes the mode worth running. Smoke and consumer both passed and
both printed that version. The Debug test suite came back `9 pass, 1 fail
(10 total)`.

**The one failing case.** `unmatched_closing_parenthesis_is_rejected_at_its_offset`,
pattern `)`, pinned to error 122 at **offset 1** with the message `unmatched
closing parenthesis`, all three read out of upstream's own `pcre2test` output
for 10.49 (`testdata/testoutput2:395-396`; 122 is `ERR22`,
`src/pcre2_compile.h:53-60`). On 10.45 the **error number and the message
matched** and the offset was **0**. The assertion that failed is
`expectEqual(expected.offset, rejection.offset)` at `tests.zig:69`.

**It is not an ABI or header-mixing fault.** The receipt shows `translate-c
success` and the test binary compiling and linking against the installed library
before it ran at all. A binding fault fails at the compile or the link; this one
reached a single assertion about a single number.

**Nothing was done to make the row look better.** The fixture was not re-pinned,
not loosened, not skipped and not hidden, and no result was invented for it. The
table is transcribed from the 10.49 `testdata/` this fork ships, so a release
that reports a different offset for the same error number is answering a
different question, and the honest record of that is a red row.

**What is known about the cause, and how far.** Upstream's own `ChangeLog`
travels in this tree, and its entry 13 of the **10.47** section
(`ChangeLog:164`, `:220-221`) is *"(#756) Improved error offsets and diagnostics
for syntax errors during pattern compilation"*; 10.46's only entry is a security
fix (`ChangeLog:243-252`). So a compile-error-offset change between 10.45 and
10.49 is documented in this repository's own bytes, and 10.47 is the release
that record names. The **precise** cause — the line of 10.45's `pcre2_compile.c`
that put that offset at 0 — is **not** identified here, because those sources
belong to 10.45 and this repository carries only 10.49's. Nothing stronger is
claimed than the record supports.

**What is not claimed at all.** No assertion is made that any two installed
releases produce identical outputs, or that this fixture would pass against some
other release. The native 10.49 suite is green end to end; the 10.45 run is a
recorded cross-release observation, not a parity proof, and it is reported here
rather than reconciled.

**Status.** `observed`.

---


## 21. Withdrew an unauthorised grant for fork-authored files

`NOTICE.md` no longer offers BSD-3-Clause for fork-authored files. No owner
authorised that grant; their licence remains unassigned. This does not change
the carried upstream BSD-3-Clause WITH PCRE2-exception grant, the separate
licences of retained JIT and data files, or their obligations.

## 22. Proved the filtered source package

The driver fetched the local source from an external approved scratch build
root, replayed all 59 checksum records inside the filtered package, and ran its
copied consumer against 10.49. Receipts are
`local://foundation-expansion-pcre2-external-driver-package-fetch-328.log`,
`local://foundation-expansion-pcre2-materialized-package-integrity-337.log` and
`local://foundation-expansion-pcre2-materialized-package-consumer-344.log`.
This proves source, fixtures and legal records survive `.paths`; it does not
claim publication, registry resolution or execution of the CI workflow.

**This entry is history.** It ran on 2026-10-01, against the tree before
entries 24-26, and its identity is not the package's current one. The current
filtered-package result and identity are driver-owned and are recorded outside
this repository, in the root ledger `FORKS.json` under
`cross_test_wave.materialized_packages.pcre2` and in
`local://foundation-cross-test-package-regression.json`, because they are a
digest over a package that includes these documents.

## 23. Joined the published 53-platform `cross-test` matrix

**Condition.** `zig build check` answers six compile-only questions. The
workspace gate for the eight additions is the published Zig 0.16.0 Tier 1/2
matrix, 53 platforms, run by `~/.local/bin/cross-test`, and a cell of it is a
real `zig build test -Dtarget=TARGET` rather than a compile. Nothing in this
package could be selected by that harness, because a harness that is meant to
discover settings needs a settings file and this package had none.

**Change.** A new `cross-test.profile.sh` at the package root: four ordinary
Bash variable definitions, `CROSS_BUILD_STEP=test`, `CROSS_BUILD_JOBS=2`,
`CROSS_BUILD_TIMEOUT=1800` and `CROSS_TIMEOUT=600`. No `cross_build_command`,
no `cross_artifact`, no `CROSS_MATRIX`, no `TARGETS` and no host path, so the
harness keeps the standard Zig-build mode, keeps the full published matrix and
keeps its own runner policy, and every value stays a default the command line
overrides. `CROSS_LIBC_RUNTIMES` is deliberately absent: it names foreign libc
loaders on the machine running the harness, which is that machine's business.
The file is listed in `build.zig.zon`'s `.paths`, so a fetched package carries
it, `!cross-test.profile.sh` was appended to the fork's block in `.gitignore`
alongside the other re-inclusions, and `NOTICE.md` records it among the
fork-authored files whose licence is unassigned — upstream's
BSD-3-Clause WITH PCRE2-exception does not reach it.

**What this entry did not change — and what running it then forced.** This entry
itself added no `build.zig` line, no native source, no test and no fixture. The
`test` step already attached a real run artifact (`build.zig:341-342`), which is
what lets a cell with a runner execute all ten tests and a cell without one
still compile them; the harness replaces the run step's action with a skip and
leaves the compile dependencies in place (`run_policy.zig:55-57`, `:103-105`),
so an unrun cell is `build_only` and not a pass. The fifteen-case fixture table,
the bounds, the name-table contract, the version-buffer contract, the ownership
transitions and the capture-lifetime cases are the same ten on every cell, and
all of that is unchanged today. Running the matrix is what later forced the
translation route in entries 24-26.

**Accounting, stated so it is not misread later.** A cell that runs reports
`10/10 tests passed`: the default **8-bit** build and the whole suite, which
was ten tests at the time. The width cannot drift — the harness passes
`-Dtarget` and nothing else, and `-Dcode-unit-width` keeps its default of 8.
At the time this entry was written, `test`, `smoke` and `check` also **refused**
16 or 32 outright (`build.zig:326-342`) rather than running an empty step.
**That refusal is gone**: `zig/root.zig` now resolves its surface from the
compiled width and no width is refused — see entries 36 and 37 in this section.
The sentence above describes the graph this entry measured and is kept as the
state it was written against.

**Target-dependent configuration, reviewed at the time and unchanged by this
entry.** `config.h` is generated per target from `target.result`, never from the
machine configuring the build (`build.zig:862-925`). `linkage` defaults to
dynamic only on a GNU-libc target — `isGnuLibC()` is true only for `.linux` and
`.hurd` with a GNU ABI (`std/Target.zig:2139-2143`) — and static everywhere
else, so the MinGW cells build a static archive and `PCRE2_STATIC` follows on
both the C compile line and the translate-c line (`build.zig:475-484`,
`:557-572`). Nothing about `config.h`, the width, the limits or the linkage
rule changed when entries 24-26 added the second front end.
`HAVE_MEMFD_CREATE`, `HAVE_SECURE_GETENV` and `HAVE_SETRLIMIT` are read only by
`pcre2test.c` and `pcre2grep.c`, which `test` does not build. The interpreted
core has no endianness branch: the only `ENDIAN` test under `src/` is in
`pcre2_jit_compile.c`, and `SUPPORT_JIT` is 0. `pcre2.unset` is `~@as(usize, 0)`
and therefore `SIZE_MAX` on a 32-bit cell and on a 64-bit one, which is what
`PCRE2_SIZE` is in each.

**The 10.45 offset is untouched.** Every cell builds this tree's own bundled
10.49; `-fsys=pcre2-8` is never passed. Entry 20's
`unmatched_closing_parenthesis_is_rejected_at_its_offset` difference is a fact
about an installed 10.45 library and is out of scope here. Nothing was
re-pinned, loosened or skipped for it.

**Status: `observed`.** The profile did what it was written to do: the matrix
runs this package's real `test` step over all 53 published targets. The first
full sweep (`20261002-040235-43000-5735`) came back 20 pass / 12 fail / 21
build_only, entries 24-26 are what closed the twelve, and the current sweep
`final-current` (`20261002-071302-33056-11212`) is 20 pass / 0 fail / 33
build_only, exit 0. Counts, cells and receipts are in
`README.zig.md` § "Verification status".

## 24. Gave the bundled translation the front end each target's C library needs

**Condition.** `zig translate-c` parses with Aro, and Aro preprocesses as well
as parses, so `translate.h` was read by Aro alone on every target.
`src/pcre2.h.generic:87-89` includes `<limits.h>`, `<stdlib.h>` and
`<inttypes.h>`, so every translation drags in the target's **real** C library
headers — and Aro's preprocessor cannot read some of them. The first full sweep
of the 53-platform matrix (`20261002-040235-43000-5735`: 20 pass, 12 fail, 21
build_only, exit 1) failed exactly there. The twelve were the nine NetBSD cells,
`mips64-openbsd`, `mips64el-openbsd` and `x86-windows`, and every one was a
`translate-c` failure on a C library header rather than on anything PCRE2
writes: NetBSD defines `__BEGIN_PUBLIC_DECLS`/`__END_PUBLIC_DECLS` with
`_Pragma` and Aro leaves the pragma in the token stream
(`generic-netbsd/sys/endian.h:74`, `unknown type name 'pragma'`,
`local://foundation-cross-test-matrix-pcre2-aarch64-netbsd.log:6-21`);
`generic-openbsd/mips64/endian.h:32-41` will not define `BYTE_ORDER` without
`__MIPSEL__`/`__MIPSEB__`, which Aro's MIPS predefined table lacks; and
`any-windows-any/malloc.h:183-187` derives `_ALLOCA_S_MARKER_SIZE` from
`_ARM_`, `_X86_`, `__ia64__`, `__x86_64` or `__aarch64__`, none of which Aro's
Windows-x86 table defines.

**Change.** `build.zig` grew a private `AggregateRoute` enum and a private
`aggregateRoute` (`build.zig:635-700`), consulted once per target from
`target.result` and never from the host: `.aro` when
`target.result.isGnuLibC()`, `.preprocessed` otherwise. The second route runs
the target's own `zig cc -E -dD -fno-blocks -x c` over `translate.h` first
(`preprocessedAggregate`, `build.zig:825-851`) — the same `-target`, the same
`-I` on the generated `pcre2.h` copy that every C unit of the core itself
compiles against, the same `-DPCRE2_CODE_UNIT_WIDTH` and the same
`-DPCRE2_STATIC` — and Aro parses what that produced. `-dD` is what keeps
`PCRE2_INFO_CAPTURECOUNT`, `PCRE2_CONFIG_VERSION` and the header's other macros
reaching Zig as constants instead of being expanded away. `core_c_flags` is
deliberately not repeated there: it is code generation, and the preprocessor
neither needs it nor acts on it.

**Why GNU libc is not one of the twelve.** It is the one C library where the
*other* front end loses, so the rule is the reverse there. glibc hands a
compiler with no native `_FloatN` type five `typedef`s, Aro holds those five
names as builtin type specifiers of its own, and reading the `-E` output
produced eleven errors. That regression was **observed before** the correction,
on all three GNU-libc `check` cells — `x86_64-linux-gnu`, `aarch64-linux-gnu`
and `riscv64-linux-gnu`, each `Build Summary: 6/10 steps succeeded` and
`translate-c 11 errors` (`local://foundation-cross-test-baseline-pcre2-x86_64-linux-gnu.log:3-35`,
and the same on the other two) — so `aggregateRoute` sends a GNU-libc target to
Aro directly. Each of the twelve is named one by one in `build.zig` with the
header line that fails, and every local substitute is refused: `-D__MIPSEB__`,
`-D_X86_`, a `_Pragma` replacement and `-D__GNUC__=7` all describe a target
that does not exist.

**What was not done.** No prototype was copied into a Zig file, no declaration
was written by hand, no header was edited, no feature was invented, no
diagnostic was suppressed and no native source was touched. On both routes the
header the translator reads is this repository's own 10.49 header, expanded by
the compiler that also compiles the core for that target.

**Status: `observed`.** The `final` (`20261002-062101-65281-7993`) and
`final-current` (`20261002-071302-33056-11212`) sweeps both report **20 pass, 0
fail, 33 build_only, 0 partial**, exit 0, and this package's six cells in the
corrected baseline (`local://foundation-cross-test-final-baseline.json`) are all
`success` where the same three GNU cells had been `failed`.

## 25. Asked the preprocessing front end for the translator's dialect

**Condition.** With entry 24's extra front end in place, six cells were still
red in the next sweep (`20261002-054414-46667-18828`: 20 pass, 6 fail, 27
build_only, exit 1).

**Symptom.** Four of them were the Darwin and MacCatalyst cells. Clang's driver
enables blocks by default for a Darwin target, so `__BLOCKS__` is defined while
it is, the Darwin C library then declares six entry points that take a block
pointer — `atexit_b`, `bsearch_b`, `heapsort_b`, `mergesort_b`, `psort_b` and
`qsort_b` — and Aro, which has no block pointers, stops on every one: 23
`expected ')', found '^'` errors at `any-darwin-any/_stdlib.h:298`
(`local://foundation-cross-test-corrected-pcre2-aarch64-macos.log:6-22`).

**Change.** `-fno-blocks` on the preprocessing line, for **every** target that
reaches that route rather than only the Darwin ones, because the flag describes
the translator rather than the target; on every other target Clang leaves
blocks off by default and it changes nothing. It takes nothing from PCRE2:
`src/pcre2.h.generic` names no block type anywhere, so what leaves the file is
six declarations of the target's C library that the translator could never have
held — which is exactly where they were before this step existed.

**Status: `observed`.** All four cells are `build_only` with build exit 0 in
`final-current`, and their logs show a `translate-c success` sitting directly on
a `preprocess pcre2.h` step
(`local://foundation-cross-test-final-current-pcre2-aarch64-macos.log:16-18`).

## 26. Restated the compiler's own 128-bit typedefs, under the compiler's own guard

**Condition.** The same corrected sweep left the other two red:
`aarch64-netbsd` and `aarch64_be-netbsd`.

**Symptom.** One error each, **after** the translation itself had succeeded. A
NetBSD header in the `src/pcre2.h.generic:87-89` chain spells `__ALIGNBYTES`
through `__int128_t`, `-dD` keeps that spelling, and the translated Zig came out
naming an identifier nothing in it declared:
`pub const __ALIGNBYTES = __helpers.sizeof(__int128_t) - @as(c_int, 1);` —
`use of undeclared identifier '__int128_t'` at `pcre2_preprocessed.zig:1817`
(`local://foundation-cross-test-corrected-pcre2-aarch64-netbsd.log:6-9`).

**Change.** `translate.h` restates the two names the compiler itself provides,
guarded by the compiler's own capability macro:

```c
#if defined(__SIZEOF_INT128__)
typedef __int128 __int128_t;
typedef unsigned __int128 __uint128_t;
#endif
```

These are the compiler's typedefs, declared by Clang next to the `__int128`
primitive it provides; no header declares them, which is why a header that
spells one reaches a name the preprocessed text never defines. The guard is not
this fork's guess at a capability: Clang defines `__SIZEOF_INT128__` exactly
when `TI.hasInt128Type()` holds for the target, so a 32-bit target declares
neither name, and C permits a typedef to be restated for the type it already
denotes. **No PCRE2 declaration, constant or prototype was added or removed**;
the file remains a macro prelude, two compiler typedefs and one include.

**Status: `observed`.** Both cells are `build_only` with build exit 0 in
`final-current`.

## 27. Measured `libc_noise` over every published configuration

`PENDING-VERIFICATION`: no build ran here.

`runtime/graph.zig`'s `libc_noise` is the list of `extern` declarations the C
library provides, which the generator must leave `direct` rather than route to
the provider. The previous list was 400 names derived from one target's
translation plus a reading of the glibc and Darwin headers, and it was missing
the externs the aggregate's own `<stdlib.h>` reaches: 192 of them, among them
`__ctype_get_mb_cur_max` (unguarded), `strtoq`/`strtouq`, `l64a`/`a64l`,
`random`/`srandom`/`initstate`/`setstate` and their `_r` forms, the
`drand48`..`lcong48` family and its `_r` forms, `arc4random`,
`arc4random_buf`, `arc4random_uniform`, `valloc`, `on_exit`, `clearenv`,
`mktemp`, `realpath`, `qecvt`/`qfcvt`/`qgcvt` and their `_r` forms, and
`rpmatch`. A `-Druntime=true` load therefore demanded them from `libpcre2-8`
itself, and the dispatch this fork has generated routes every one of them:
`strtoq`, `__ctype_get_mb_cur_max`, `l64a`, `arc4random`, `realpath`, `rpmatch`,
`valloc`, `on_exit`, `clearenv` and `mktemp` are among the names it carries.
On Linux that often resolved by accident, because `dlsym` on the provider's
handle also searches its dependencies and libc is one; it is wrong for a
provider that does not pull libc in — a fully static object, Windows, a minimal
provider.

The list is now the measured closure. The pinned Zig 0.16.0 `zig translate-c`
was run over this package's aggregate translation unit, `translate.h`, once per
published configuration: the 53-platform Tier 1/2 table plus the six `check`
targets (`build.zig:393-400`), at each of the three code-unit widths and each
of the two linkages — 58 targets times three times two, all 348 translating —
each read through the front end `aggregateRoute` gives it. Every
`pub extern fn|var|const` name that is not PCRE2's own namespace was kept,
giving 592 names: the 400 before, plus the 192 above. The 241 names
`pcre2.h` and `pcre2posix.h` declare are excluded, and
`provider_optional`/`provider_excluded` are unchanged.

The provenance comment's header claim is corrected with it. It asserted a
`<string.h>` closure the aggregate does not have; `src/pcre2.h.generic:87-89`
reaches `<limits.h>`, `<stdlib.h>` and `<inttypes.h>` and nothing else, and
`src/pcre2posix.h:48` adds `<stdlib.h>`. The `<string.h>` and `<wchar.h>`
names still listed are kept because this file is target-independent and a name
no configuration declares matches nothing, which is harmless, but the comment
now says they are not part of the measured closure. No upstream byte is
touched.

## Outstanding integration steps

These are the release owner's, not this file's, and they are listed here so they
are not lost. What is **not** on this list is as deliberate as what is.

* **This package is unpublished.** There is no registry entry, release or tag.
  Entry 22 proves a local filtered-package fetch and consumer run, not registry
  resolution, and it is a superseded round — see the pointer below.
* **`.github/workflows/verify.yml` has never been executed here.** It is the one
  place these gates run unattended; every receipt in this repository is a local
  run. Its C-gate program has been built and run by hand (entry 19), which is
  evidence about the program and not about the workflow.
* **`-fsys=pcre2-8` has no ReleaseSafe receipt.** Debug is the only system-mode
  test run that exists.
* **The current filtered-package proof is the driver's and runs after these
  documents settle.** Its result and identity live in the root ledger
  `FORKS.json` under `cross_test_wave.materialized_packages.pcre2` and in
  `local://foundation-cross-test-package-regression.json`, and deliberately in
  neither this file nor any other: a package identity is a digest over what the
  package ships, and this documentation is part of what it ships. The 2026-10-01
  and delivery-round receipts named in entry 22 are history.
* **Runtime behaviour on 33 of the 53 cells is still unknown here.** They
  compiled and the harness reported `runtime_unavailable` for each, so the
  matrix result is 20 executed cells and 33 compile-only cells, and this file
  claims nothing about a BSD, Darwin, Windows or WASM run.
* **The fixture table stays pinned to 10.49.** Entry 20's offset difference is
  recorded as a difference between two releases, and converting it into a
  re-pinned or loosened fixture is a decision someone may take deliberately —
  it is not an open bug, and this file does not propose it.

## Zig API contract alignment — 2026-10-03

**Condition.** MatchData sized for one pattern can be reused with a larger
pattern. Native return zero reports a truncated vector, not readable captures.

**Fix.** Check the actual block against the regex passed to `match`, using
`OvectorTooSmall` before matching. Invalidate readable capture state before
either refusal; report native zero with the same error. State capacity-first
precedence, read-only cached fields, owner/copy/subject duties, partial-match
information loss, start-offset reset and early-native-error residue. Correct
non-JIT fallback symbol and compile-only install claims. Historical ten-test
receipts stay historical; the current suite has eleven tests.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
tests in all four modes, smoke, package consumer and module example pass.
Separate four-mode consumers check cross-pattern capacities, stale captures,
start-offset refusal, native UTF-boundary rejection, early `BADOPTION` residue,
startchar reset on no-match and linked non-JIT compile returning -45.
Aggregate `check` fails at WASI linking with non-PIC relocations; its build
changes in this alignment are comments only. That failure was the host build's
linkage handed to a target that cannot carry a shared object, and entry 43 below
is what corrects it; the sentence stays here as the observation it was.
No foreign execution or system
provider result is inferred. Native and generated bytes are unchanged.


## Foundation contract migration — 2026-10-04

### 27. Made `README.md` this fork's canonical entry point

`README.md` now follows the canonical order — native-source deviations,
native-build deviations with this section as the dated history link, the
current build/run/test matrix, then consumption, covering the C product and the
Nix outputs rather than a Zig-only shell. Upstream's bytes moved unchanged to
`README.upstream.md`: `sha256sum` printed
`579446220c54f9b406a6c7b9b2bf155abf699c6e0b6211c7189f3aa1b174246d` for both
files immediately before the move, and that is the digest the driver's
extraction record names for this commit. `UPSTREAM.sha256` still does not cover
it, exactly as it did not cover `README.md` before.

### 28. Added the standalone Nix packaging and the canonical dev environment

`package.nix` is one injected, source-only derivation used by both entry
points: no sibling import, no host path, no build-time download, the nixpkgs
`zig_0_16`, one real `zig build install --prefix $out` with `-j
"${NIX_BUILD_CORES:-1}"`, `-Dcpu=baseline`, one optimize selection and both Zig
caches under the Nix-provided `TMPDIR`. `linkage` and `codeUnitWidth` are
arguments, so `flake.nix` exposes `packages.<system>.default`, `.static` and
`.shared` as variants of one derivation, and the 8-, 16- and 32-bit widths are
the same derivation again. `default` passes no `-Dlinkage`, so the SDK's own
policy — dynamic on GNU libc, static elsewhere — applies unforced. The build
graph owns the installed closure — artifacts, headers, tools, data, licence
records and pkg-config metadata — and packaging installs nothing of its own, so
there is one writer per path. `devenv.nix` is canonical: tools only, the SDK
named as lazy `outputs.static` / `outputs.shared` for
`devenv build outputs.static`, and scratch locations read from
`HOST_SCRATCH_ROOT` at shell time and only where the caller has not already
chosen them. `.envrc` uses the documented `use devenv` form; devenv 2.4.1 has
no `--dotfile` flag.

### 29. Granted a licence to the fork-authored files

`FORK-LICENSE.md` records the owner's direct authorization of 2026-10-04 and
the grant: `BSD-3-Clause WITH PCRE2-exception`, the identifier upstream states
for itself at `LICENCE.md:4`, held by the contributors to this fork. It
supersedes entry 21's "unassigned" state for those files and leaves that entry
as history. Upstream's terms are untouched and un-flattened: the library and
`doc/` under the BSD terms, `testdata/` as public domain, the JIT sources under
the 2-clause BSD grant with `deps/sljit` an empty directory and no sljit text
to ship, `.gitignore` under upstream's terms with this fork's appended block
recorded, and both files carrying no per-file header still named.

### 30. Documented the native delivery and the external ABI boundaries

`README.zig.md` gained the installed-prefix layout, the packaging entry points
and an explicit ABI-boundary section: the header and the library as one revision
(and the installed pair in system mode), the code-unit width as part of the
ABI, `PCRE2_STATIC` as the one declaration macro that differs between static and
shared, JIT entry points that exist and refuse rather than being absent, and the
allocator, which in 10.49 enters at `pcre2_general_context_create` and nowhere
else.

**Status: `PENDING-VERIFICATION` for entries 27 to 30.** No build, test,
smoke, cross-target, Nix, devenv or consumer command was run for them; the
role that wrote those files runs no gates. Nothing there claims a pass, and
entry 37 below records which parts of that documentation a later gate has since
looked at.

**Outstanding, not silently dropped.** `build.zig.zon` `.paths` must list
`README.upstream.md`, `FORK-LICENSE.md`, `package.nix`, `flake.nix`,
`devenv.nix`, `devenv.yaml` and `.envrc`, or a fetched copy loses upstream's
README and the licence material; that file belongs to the native-delivery role.
The build graph must also install the pkg-config metadata, the licence records,
the `testdata` oracle and the manual, which packaging deliberately does not
duplicate.

### 31. Repaired the DFA result path and the width-dependent name table

**Condition.** The typed facade wrapped `pcre2_dfa_match_N` and the name table
with 8-bit assumptions that the width-parameterised facade does not have.

**Fix.** Three separate facts, each read out of upstream's own sources:

* **A DFA result is in the match block, never in the workspace.**
  `pcre2_dfa_match_N` hands its matcher the `pcre2_match_data`'s own offset
  vector as the output (`src/pcre2_dfa_match.c:4062-4063`) and upstream's own
  substring helpers read the result back out of that block
  (`src/pcre2_substring.c:334-341`). `DfaWorkspace` is the caller's scratch and
  the only place `PCRE2_DFA_RESTART`'s state can live (`:605-606`,
  `:3486-3489`); it carries **no result and no pair accessor**, and the facade
  reports the count upstream returned rather than copying the pairs out. A
  return of **zero** is `DfaOutcome.truncated`: the vector holds the longest
  matches and is readable but incomplete (`:905-911`,
  `doc/pcre2.txt:4359-4360`), so `MatchData.matched` is true and
  `MatchData.ovector()` answers. A fabricated `DfaWorkspace.pair` would have
  been a value the library never wrote.
* **The pairs are substrings, not groups.** This matcher has no capture groups
  (`doc/pcre2.txt:4340-4343`) and orders them longest first (`:4352-4360`), and
  the vector must be sized for every simultaneous match rather than one pair
  per parenthesis (`doc/pcre2_dfa_match.3:33-35`). `MatchData.create` sizes for
  capture groups, which is the wrong number here; `MatchData.createWithOvector`
  is the right one.
* **The name table's group number is `IMM2_SIZE` code units, and that is two
  only at width 8.** `src/pcre2_intmodedep.h:212-221` defines it as two code
  units in the 8-bit library, where `GET2` is a big-endian pair, and one code
  unit at width 16 and 32. Upstream reaches the name by adding `IMM2_SIZE` to a
  code-unit pointer (`src/pcre2_compile_cgroup.c:142-144`, `:167-175`;
  `src/pcre2_substring.c:498-518`), and names are code units of this width, one
  per name character. Reading a 16- or 32-bit table as bytes lands inside a
  code unit and names a different group every time.

**Status: `OBSERVED`.** All three widths run the DFA and name-table tests;
see the width table in [`README.zig.md`](README.zig.md) § "Verification
status".

### 32. Made the four Native-allocated result blocks say who frees them

**Condition.** Four values hand back a block PCRE2 allocated, each with a
hidden header naming the allocator that produced it, and each with exactly one
correct free: `Owned` (`MatchData.get`), `SubstringList` (`MatchData.list`),
`Converted` (`ConvertContext.convert`) and `Serialized` (`Regex.serialize`).
The documentation had none of them, and `SubstringList` is the sharpest case —
`pcre2_substring_list_free_N` frees the block **from the array of pointers**
(`src/pcre2_substring.c:451-459`), so `bytes` is that array and not the first
string in it.

**Fix.** Documented each block, its one correct free, and the reason no other
release is legal. Two further facts that a caller gets wrong otherwise:
`Converted.slice()` **excludes** the terminating NUL, because
`pcre2_pattern_convert_N` writes the NUL into its own output
(`src/pcre2_convert.c:382`, `:1080`) and then answers `out.output_size - 1`
(`:381`, `:1092`), and `MatchData.copy`'s buffer needs `size + 1` because
PCRE2 writes a terminating NUL after the last code unit
(`src/pcre2_substring.c:117-130`).

**Status: `OBSERVED`** for both the substring-list and copy tests at all three
widths.

### 33. Stated the POSIX wrapper's own unset marker and lifetime

**Condition.** `pcre2.unset` is `PCRE2_UNSET`, which is `SIZE_MAX`. The POSIX
wrapper's marker is a different value and is not a narrowed form of it.

**Fix.** `Posix.unset` is the literal **`-1`**
(`src/pcre2posix.c:403-408`), written into both ends of a `regmatch_t` for
every group `pcre2_match` left unset **and into every slot past the ones the
match filled**, so a `regmatch_t` array shorter than the pattern's capture
count is a smaller answer rather than an overrun. `REG_BADPAT` is the wrapper's
fallback rather than its answer for every bad pattern
(`src/pcre2posix.c:312-319`): `a(b` is `REG_EPAREN`. `REG_NOSUB` is a
**compile-time** bit — the wrapper remembers it in the block and zeroes its own
match count from that record (`:368-372`) — so `matched_without_reporting` is
decided from the compiled flags and not from `exec`'s argument.

The block's lifetime rule is recorded too: `Compiled.raw` is a `regex_t` **by
value**, because `pcre2_regcomp` fills the struct the caller hands it
(`:277-301`) and `pcre2_regfree` is what reads it back, and that one call frees
both the compiled pattern and the match-data block inside it (`:254-259`).

**Status: `OBSERVED`** — the wrapper test runs at width 8 and asserts the
codes, the unset marker and the `REG_EPAREN` mapping.

### 34. Documented that a callout's zero continues and its sign carries the meaning

**Condition.** `pcre2_set_callout_N`'s callback return is read as a **sign**,
not as a boolean.

**Fix.** Zero continues from just after the callout; a **positive** answer is
`MATCH_NOMATCH` for this start position, so the matcher keeps bumping along and
reports `PCRE2_ERROR_NOMATCH` unless a later position matches; a **negative**
answer abandons the whole attempt with that number as the return
(`src/pcre2_match.c:5989-5994`). "Non-zero means keep going" is backwards. The
callback and its `data` are **not copied** into the context — PCRE2 holds the
two pointers — so both outlive every attempt made through it, and a callout and
the three ceilings share one context.

**Status: `OBSERVED`** — the callout test returns zero and asserts the block
reached the matcher was this pattern's own and pointed at this caller's
subject.

### 35. Recorded that JIT refusal is a number and a NULL, never a substitute

**Condition.** `deps/sljit` is an empty submodule and `SUPPORT_JIT` is 0, so
there is no SLJIT in this build. A caller asking whether JIT is available and
finding no symbol would conclude wrongly; a caller that quietly falls back
would be told it had JIT when it had not.

**Fix.** Both refusals are recorded as what they are. `pcre2_jit_compile_N`
answers `PCRE2_ERROR_JIT_BADOPTION`, **-45**, as a **value carrying upstream's
number**, because the same call against a provider that does have JIT would
answer `compiled`. `pcre2_jit_stack_create_N` answers **NULL**, and a failed
allocation arrives the same way (`src/pcre2_jit_misc_inc.h:125-134`), so that
one entry point is named `error.JitUnsupported` for what it saw rather than
`OutOfMemory`. **There is no fallback interpreter wearing JIT's name**: the
interpreter is what runs a match and it is reached through `Regex.match`.

**Status: `OBSERVED`** at all three widths — the JIT test accepts either the
compiled or the refused arm and asserts upstream's number on the refusal.

### 36. Classified a UTF validity failure at every width, not only at width 8

**Condition.** `Regex.match`'s return mapping covered `-3…-23` and `-36` only.
Those are the **8-bit** UTF codes: `PCRE2_ERROR_UTF8_ERR1`…`_ERR21`. At width
16 the codes are `-24…-26` (`PCRE2_ERROR_UTF16_ERR1`…`_ERR3`) and at width 32
`-27…-28` (`PCRE2_ERROR_UTF32_ERR1`…`_ERR2`)
(`src/pcre2.h.generic:355-400`). A validity failure at either of those widths
therefore arrived as `MatchOutcome.failed` — the right number, the wrong tag,
for the same condition.

**Fix.** The mapped range is now `-28…-3` and `-36`. This is a classification
repair in the facade's own return mapping, not a change to any fixture: the
test that failed is still in the suite and still asserts the category and the
state transition, and the tautological fixture arithmetic and the non-empty
diagnostic assertions standing beside it were **removed**, not relaxed.

**Status: `OBSERVED`.** The two wide runs that reported `23 pass, 1 fail (24
total)` — `local://foundation-contract-pcre2-real-code-unit-safe-consumer-width-16-full-gate.log`
and `…-32-…`, failing at `tests.zig:400` — are superseded by
`local://foundation-contract-pcre2-real-native-width-16-UTF-validity-category-full-gate.log`
and `…-32-…`, both `21/21 steps succeeded; 24/24 tests passed`.

### 37. Brought this wave's documentation to the surface the code actually has

**Condition.** The four documents described a compile/match facade and a
seven-member error set. The code has a width-parameterised surface, thirteen
error members, and wraps the DFA matcher, substitution, the substring helpers,
MARK, the callout and enumeration entry points, the convert context,
serialization, JIT and the POSIX wrapper. None of the second group was
documented, the 16- and 32-bit rows claimed the graph refuses those widths
when it does not, and the sample program could not compile at width 16 or 32
because it passed `[]const u8` where a code-unit slice is required.

**Fix.** `README.zig.md` gained a "Beyond the interpreter" table, the six
remaining error members, the ownership rules above, the width facts in the
import, build-mode and ABI sections, and a sample program that widens its
text; `README.md` gained the DFA and name-table rules in its C-consumer list
and three current width rows. `CHANGELOG.md` and `FORK-NOTES.md` record the
decisions.

**Status.** The gate states live in [`README.zig.md`](README.zig.md) §
"Verification status" and are not restated here. What is **observed** there:
three widths, `test` and `smoke`, `24/24 tests passed` and `21/21 steps
succeeded` each. What is **not**: static linkage, the other three optimize
modes, `install` at width 16 or 32, the six-target `check`, the 53-platform
matrix, any Nix output, `devenv`, and the **runtime** route — no
runtime-loaded build of this tree has ever been executed here.

### 38. Recorded that the integrity record's red line is a fork file, and left the fix to the owner

**Condition.** `UPSTREAM.sha256` carries 59 records, and the 59th is not an
upstream file. The manifest's own header says so and gives the reason
(`UPSTREAM.sha256:27-31`): `testdata/foundation-fixtures.zig` is this fork's own
fixture module, it holds every expected answer the tests compare against, and
hashing it makes a silent edit to the oracle fail loudly instead of quietly
moving it.

**Symptom.** This wave edited that module, so the record stopped matching. The
driver's integrity sweep reports **58 `OK` and one failing record**, and the one
is the fork's own. The 2026-10-01 receipt recorded 59 records all `OK`, and this
file's own earlier note claimed the graph change "touched none of" the files the
record covers — true of the 58 upstream records and **false of that 59th**.
Comparing every recorded digest against the file it names confirms the split:
59 records, 58 matching, one not, and no upstream byte among them.

**Fix.** None applied here, and that is deliberate. The correct repair is to
**re-derive that one digest** from the current file. The alternatives are each
worse: re-pinning an upstream record would destroy the gate, deleting the
failing line would hide an oracle edit, and suppressing the check would throw
away the reason the record existed. What this entry does is state the scope
wherever the count appears — `README.md`, `README.zig.md` and this file — so
that the red line is read as a fork-file change detector firing, not as a
native-byte finding.

**Status: `OBSERVED`, and red.** `UPSTREAM.sha256` was written 2026-10-02 and the
fixture module was modified 2026-10-04, which is the whole of the difference.
**This does not complete the native-byte criterion**: all 58 upstream records
verify, and that is a statement about upstream bytes only. The full
filtered-package integrity replay belongs to the driver-owned proof.

### 39. Separated a serialization refusal from an allocation failure

**Condition.** `Regex.serialize`, `Regex.decode` and
`Regex.serializedCodeCount` mapped **every** negative return to
`error.OutOfMemory`.

**Symptom.** Six of the numbers those entry points return are not allocation
failures, and reporting them as one tells a caller to retry or to grow a heap
when the real answer is that the stream is wrong: `PCRE2_ERROR_MIXEDTABLES`,
-30, is two blocks whose character tables are at different **addresses** —
upstream compares the pointers, not the contents
(`src/pcre2_serialize.c:99-102`); `PCRE2_ERROR_BADMAGIC`, -31, and
`PCRE2_ERROR_BADMODE`, -32, are a header that is not this stream's (`:176-181`);
`PCRE2_ERROR_BADSERIALIZEDDATA`, -62, is a header or block that does not
describe what it must, including one whose `name_entry_size` or `name_count`
exceeds the maxima (`:178`, `:209-213`, `:229-235`);
`PCRE2_ERROR_BADDATA`, -29, is a count of zero or less (`:88`, `:272-275`);
and `PCRE2_ERROR_NULL`, -51, is a null block. Retrying any of those is futile.

**Fix.** Only `PCRE2_ERROR_NOMEMORY`, -48, keeps the name `OutOfMemory`, and it
now reaches it from two new sites: `pcre2_serialize_encode_N` and
`pcre2_decode_N` allocate with `memctl->malloc` and check the result themselves
(`:108`, `:192`, `:221`), so that code arrives here exactly as a NULL does.
Everything else is the new `error.SerializationRefused`. The number is not
reported rather than guessed — the condition is what a caller can act on.

**Status.** `SOURCE-CONFIRMED` for the numbers, each read out of
`src/pcre2_serialize.c` at the lines cited.

### 40. Made `enumerateCallouts`'s callback non-optional, because upstream never null-checks it

**Condition.** `Regex.enumerateCallouts`'s callback was typed
`?*const fn (…) callconv(.c) c_int`.

**Symptom.** The optional says a null callback is a legal value. It is not.
`pcre2_callout_enumerate_N` calls the function for every `OP_CALLOUT` and
`OP_CALLOUT_STR` it walks and never tests it for null
(`src/pcre2_pattern_info.c:405`, `:418`), so a null callback on a pattern that
has a callout is a **crash**, not a refusal and not an empty walk. An optional
pointer here is a shape upstream never produces and this file should not imply.

**Fix.** The parameter is a plain `*const fn`, exported as
`pcre2.CalloutEnumerate` (= `pcre2.Surface.CalloutEnumerate` =
`Raw.CalloutEnumerate`). A caller that genuinely wants "tell me whether there
are any" counts with its own state rather than passing null.

**Status.** `SOURCE-CONFIRMED` for the two lines in
`src/pcre2_pattern_info.c`.

### 41. Made `substitute` invalidate the captures it leaves behind

**Condition.** `Regex.substitute` wrote into the caller's `MatchData` and left
it there, and the documentation did not say what was left in it.

**Symptom.** Upstream matches **into the caller's block**
(`src/pcre2_substitute.c:984`), so afterwards the offset vector holds the *last
internal match's* pairs while the block's `rc` field holds the **number of
substitutions made** (`:1762`, `:1768`) — and every native substring entry point
reads that field as a *pair count* (`src/pcre2_substring.c:317`, `:390`). Two
concrete failures follow, both of them reading past what is there: after
matching a short subject and then running a longer global substitution against
the same block, `group()` resolved substitute-subject offsets against the old,
one-code-unit subject, and `list()` walked `rc` = 5 pairs out of a 2-pair
vector.

**Fix.** `substitute` moves the block into the "nothing readable" state —
`matched = false`, `pairs = 0`, `subject` set to the substitution's subject —
**before** the call, whichever way the attempt ends, and reports the
substitution count as `Substitution.written.substitutions` rather than leaving
it in the block. Afterwards `group` and `groupRange` answer null and `list`,
`get`, `copy` and `ovector` answer `SubstringUnavailable`.

`SubstituteOptions.matched` is the deliberate exception: upstream copies the
caller's block into one of its own, matches into that, and frees it
(`src/pcre2_substitute.c:898-917`, `:1767`), so the captures that were in the
block are still the ones in it and they are left alone. That option substitutes
the match **already in the block**, which is also why it is the only
substitution whose result depends on what was there before.

**Status.** `SOURCE-CONFIRMED` for the mechanism, at the lines cited. The
consequence is carried by the ownership rule that a capture is valid until the
next `match`, `dfa` **or `substitute`** on that block — three writers, not one.

### 42. Corrected the character tables' ownership: PCRE2 keeps the pointer

**Condition.** The facade documented `CompileContext.setCharacterTables` and
`GeneralContext.tables` as though PCRE2 copied the 256 bytes into the compiled
block, which made the caller's storage sound releasable afterwards.

**Symptom.** That was false, and the error would have been a use-after-free at
match time rather than a compile failure. `pcre2_set_character_tables_N` stores
the address exactly as it was given (`src/pcre2_context.c:326-329`);
`pcre2_compile_N` stores **that same pointer** in the block it builds
(`src/pcre2_compile.c:10451`, `:10960`) with no `PCRE2_DEREF_TABLES` flag; and
`pcre2_code_free` does not free it either (`:1146`).

**Fix.** The documentation now says what the code does: PCRE2 keeps the
**pointer**, not a copy, so those 256 bytes must stay alive for as long as
every pattern compiled through that context, and nothing here releases them. The
same row records why two blocks built from two different table addresses are
`PCRE2_ERROR_MIXEDTABLES` — upstream compares the pointers rather than the
contents (`src/pcre2_serialize.c:99-102`).

**Status.** `SOURCE-CONFIRMED` for all four cited locations.

### 43. Gave every cross-check cell its own default linkage

**Condition.** The six-target `check` matrix was configured from one host, and
the cells were handed the host build's **resolved** `-Dlinkage` value.

**Fix.** `addTargetCheck` now takes the option and calls `defaultLinkage` per
cell, so the default is read from each cell's own `target.result`:
dynamic on the three GNU-libc cells, static on macOS, Windows and WASI. An
explicit `-Dlinkage` still reaches every cell unchanged, and a cell whose OS has
no dynamic linker is refused by name through `linkageSupported` and
`unsupportedSharedMessage` — the same message the build target's own refusal
uses — as a named failing step rather than as a shared build that cannot exist
or a target quietly dropped from the matrix. The rule is unchanged; only the
target it is read from moved. `PENDING-VERIFICATION`: no check was run here.

### 44. Decorated the in-core POSIX wrapper's calls to the core as local

**Condition.** `src/pcre2posix.c` is compiled into the core artifact as well as
into `pcre2-posix`. On COFF that makes every core entry point it calls a local
definition of the same DLL, while `pcre2.h` — the only header that unit includes
from that family — declares the whole API `extern __declspec(dllimport)` unless
`PCRE2_STATIC` is defined (`src/pcre2.h.generic:56-63`).

**Fix.** One compile line: `PCRE2_EXP_DECL=extern` for `pcre2posix.c` compiled
into the core, on COFF only and for a shared build only. That is upstream's own
override, which `pcre2.h` leaves alone when it is already defined
(`src/pcre2.h.generic:51-52`); it is not put on a shared module, where it would
take the `dllexport` off every core entry point
(`src/pcre2_internal.h:154-160`). The separate `pcre2-posix` artifact keeps
`dllimport`, which is correct there and matches `CMakeLists.txt:1011-1013`. No
native byte is edited and no diagnostic is suppressed.
`PENDING-VERIFICATION`: no build ran here.

**Observed failures these two entries correct**, both from the same six-target
run and neither yet re-run: `wasm32-wasi` linking a shared artifact with 18
`-fPIC` relocation errors (`:19-37`) and `x86_64-windows-gnu` failing with seven
LNK4217 `locally defined symbol imported` lines from `pcre2posix.obj`
(`:3-11`), in `local://foundation-contract-pcre2-current-cross-target-check.log`.
That receipt is the failure, not a result.

### 45. Gave the published module the build cache's loader entry

**Condition.** A dependent's own program is linked against this package's shared
artifact and executed out of a build cache, which is where
`Module.linkLibrary` recorded that the shared object was emitted.

**Symptom.** `cd consumer && zig build run -Druntime=false -Dlinkage=dynamic`
exited 0 with `Build Summary: 17/17 steps succeeded` and every hand-worked
capture offset still correct, and the loader printed
`/lib64/libpcre2-8.so.0: no version information available (required by …)` and
the program answered `linked against 10.45 2025-02-05` — the host's installed
PCRE2, not this build's 10.49
(`local://foundation-resumed-pcre2-standalone-linked-dynamic.json`). The static
row of the same pair resolved correctly
(`local://foundation-resumed-pcre2-standalone-linked-static.json`), so only the
shared route was affected.

**Cause.** The published `pcre2` module was linked with `.install_tree`, so a
dependent's program got `$ORIGIN/../lib` and no other entry. That resolves
nothing out of a build cache, and the loader then falls through to the default
search path, where the same soname is installed. The library's own `test`,
`smoke` and `RunTest` copies never saw it because each was compiled from a
second, private facade carrying the build-cache entry — the entry the *installed*
programs were getting was the one published to dependents, which is backwards.

**Fix.** The published module is the build-cache flavour and the private cache
facade is deleted. `test` and `smoke` now import the published module directly.
Nothing installed is built from that module — `pcre2test`, `pcre2grep`,
`pcre2posix_test` and `libpcre2-posix` are each a C translation unit with a
module of its own, compiled by `addProgram` or `linkInstalledSibling` with
`.install_tree` — so `$ORIGIN/../lib`, the sonames, the version scripts and the
all-width closures are unchanged and no installed file names a build-cache
directory. `needsBothLoaders` now decides only whether `RunTest` gets a second
copy of `pcre2test`.

`consumer/build.zig` stops installing its program and hangs its install step on
the **Compile** step instead, for the reason the library already uses for its
own smoke example: an installed copy would carry the dependency's cache
directory in its `DT_RUNPATH`, and a proof is not a deliverable. `zig build run`
is unchanged and still executes the program.

This is the arrangement `gmp`, `htscodecs`, `inchi` and `luajit` already use in
this workspace, and this package was the one that had it backwards.

`PENDING-VERIFICATION`: no build, test or run happened here. The correction has
not been executed, and the two receipts above are the failure, not a result.

### 46. Corrected `MatchData.next`'s answer and `Regex.decode`'s destination bound

**Condition.** Two wrappers in `zig/widthed.zig` stated a contract that upstream's
own source does not have, and neither had a caller in this repository.

**Cause, first.** `pcre2_next_match_N` answers `TRUE`, 1, when another attempt
should be made and `FALSE`, 0, when there is none — every one of its returns is
one of those two (`src/pcre2_match_next.c:96-169`, `:109`, `:134`, `:152`,
`:138-139`, `:157-158`, `:166-167`; `doc/pcre2.txt:3433-3439`). `MatchData.next`
read that backwards: 0 became `true`, an unreachable -1 became `false`, and 1
became `error.SubstringUnavailable`. A caller resuming after a successful match
was refused on the first step and told to continue at the end of the subject, so
`while (try md.next(...))` could neither run nor stop. Its two parameters were
described as "the arrays the callback was given", which the C signature does not
have (`src/pcre2.h.generic:775`: `PCRE2_SIZE *pstart_offset`, `uint32_t
*poptions`), and the `offsets.len == 0` guard tested a length upstream cannot see.

**Fix.** `next` is now
`next(self: *const MatchData, start_offset: *usize, options: *u32) bool`, the two
out-parameters are the ones upstream actually writes, and the return is the
upstream polarity with no error arm because no error is reachable. The guard is
gone because the length it checked is not part of the contract.

**Cause, second.** `Regex.decode` took `count` and the destination array as two
independent arguments and compared only the array against zero.
`pcre2_serialize_decode_N` caps the request at the number of blocks in the stream
(`src/pcre2_serialize.c:183-184`) and then writes one `pcre2_code *` per block it
decodes (`:204`, `:243`); it never sees how long the caller's array is. Asking for
three blocks of a three-block stream into a one-element destination wrote two
`pcre2_code *` past the end of that array with no diagnostic. `Regex.serialize`
already owned the mirror of this bound for its own scratch array.

**Fix.** `decode` compares `count` against `all.len` before anything runs and
answers `error.OvectorTooSmall`, the name `serialize` already uses for the same
fact about a caller's array. An empty destination is refused by that same
comparison, which replaces the `error.NoSuchGroup` that stood there — a
group-number error that described nothing about a block-pointer array.

**Also corrected, in the same two files.** `Raw.next_match`'s parameters in
`zig/raw.zig` were named `ovector` and `oveccount` and its doc called them the
vector the callback filled; they are now `pstart_offset` and `poptions`, with the
types (`[*c]usize`, `[*c]u32`) and the `@field(c, n("pcre2_next_match"))` dispatch
untouched, so no ABI or linkage fact moved. The `error.SubstringUnavailable`
documentation no longer claims `MatchData.next` as a second site, since it can no
longer return it; the variant itself stays for its other uses. The
`error.OvectorTooSmall` documentation now names the two serialization entries.

**Migrated everywhere, with no alias.** `MatchData.next` has no caller in
`tests.zig`, `smoke.zig`, `consumer/` or `testdata/`, and `Regex.decode`'s two
existing calls in `tests.zig` pass `count` 1 with a one-element array, which the
new bound accepts. There is no compatibility shim and no second spelling.

**Tests added, both consumer-visible.** `tests.zig` gains a resumed-iteration
test over `a*` on the subject `a`, which reaches both answers and checks the
match count, each capture's offsets and the options word; and a decode test with a
three-block stream and a one-slot destination, which checks the refusal, that
nothing was written, and that the same bytes decode into a long-enough
destination. Two regressions were observed failing first, from an independent
consumer outside this repository:
`next` answered `error.SubstringUnavailable` at the first resume, and the decode
leg reported `DestinationOverrun` with both canary words overwritten after the
one-slot destination.

**One correction after the first compile, and it was the test's fault.** The
installed-stage build rejected the new iteration test at `span.start`: it had read
the offsets off `MatchData.group(0)`, which answers the captured code units, not a
range. The facade was not changed to suit the fixture — the test now reads its
offsets through `MatchData.groupRange(0)`, the accessor that exists for that, and
keeps the captured text as a separate check through `group(0)`. The match count,
the start offset, the end offset, the captured units and the options word are all
still asserted independently.

**Teardown in that decode test, stated rather than assumed.** `decode` answers the
first block as a `Regex` and the rest as bare pointers, and every one of the three
is released exactly once: the `Regex` by its own `deinit`, the other two through
`pcre2.c.pcre2_code_free_N`, the width picked at compile time from
`pcre2.compiled_width` so a build names the one symbol that belongs to it. That
route is observable rather than merely correct, because the call is given the
counting allocator pair `tests.zig` already has: a decoded block is allocated
through the `general` handed to `decode` (`src/pcre2_serialize.c:215-218`) and the
copy that follows starts one `pcre2_memctl` past both ends (`:225-228`), so the
allocator that produced the stream is dropped rather than carried over, and
`pcre2_code_free_N` releases the block and its shared tables through that block's
own memctl (`src/pcre2_compile.c:1212-1227`). Before any of it is released, the
test asks the pair for each of the three addresses and requires all three to be
among the blocks it handed out — the assertion that is actually about ownership,
since `allocations` is already positive from the two contexts and the character
tables and would stay positive for a decoder that used upstream's default
throughout. Only then does it check conservation: every block handed out came
back, none came back that was never handed out, none was handed out that could
not be tracked. How many blocks a decode allocates is upstream's business and is
not pinned.

`PENDING-VERIFICATION`: no build, test or run was executed by the role that wrote
these files. The consumer observations and the installed-stage compile named
above are the parent's; no gate has yet reported a result for this entry.

### 47. Made the canonical devenv entries name this repository, and put the install prefix off it

**Condition.** `devenv.nix`'s entries are run as `devenv shell -- <name>`, and a
driver gate runs them the way the workspace's canonical-environment contract
does: `--from path:<sdk>`, with the working directory set to a scratch project
beside the SDK rather than to the SDK. That directory holds `.devenv/` and
`devenv.lock` and nothing else.

**Cause.** Every entry assumed it was already standing in this repository.
`sdk.integrity` ran `sha256sum -c UPSTREAM.sha256`, and `sdk.consumer` ran
`cd consumer` then `zig build run`, both relative to the caller's directory.
Neither is a relative path this fork chose wrongly in the abstract: they are
relative to *a* working directory, and nothing in them said which one. The
driver's run of `2026-10-04T175328Z` observed both fail for that reason and for
no other — `sha256sum: UPSTREAM.sha256: No such file or directory` for the
integrity entry, `cd: consumer: No such file or directory` followed by `error:
no build.zig file found` for the consumer entry, each from the generated
`/nix/store/…-sdk-integrity` / `…-sdk-consumer` wrapper. devenv materialises
tasks and scripts alike as generated shell programs that inherit the caller's
directory, so naming the directory in the entry body covers both and a per-entry
`cwd` would not.

**Fix.** Each entry now begins by changing to this repository's own directory,
which `./.` names from the file that holds it, so it is the same fact whatever
directory the caller is standing in. It is rendered with
`builtins.toString ./.` rather than interpolated as `${./.}`: interpolating the
path asks Nix for its store copy, and a read-only copy of this working tree is
not the tree these entries are gates of. The rendered string is quoted once
with `lib.escapeShellArg`, nixpkgs' own convention, so a directory with a space
or a quote in it is still one argument. `sdk.consumer` changes to
`<sdk>/consumer` directly rather than to the root and then down into it.

**The install prefix moved off this repository.** `sdk.build` is the one entry
that delivers an install prefix, and `zig build`'s own default for that is
`zig-out` beside the build root — a volume mount here, so the default writes a
delivery tree into the source repository. It now passes
`--prefix "$ZIG_LOCAL_CACHE_DIR/pcre2-install"`, beneath the cache `enterShell`
already exports: filled in from `HOST_SCRATCH_ROOT` where the caller has not
chosen one, and left alone where the caller has. `${…:?}` rather than a
fallback, because an entry with nowhere approved to write should name the
variable that is missing instead of quietly choosing a directory of its own.
`sdk.test`, `sdk.test-release-safe`, `sdk.smoke` and `sdk.check` run steps that
do not install, so they name no prefix. `sdk.consumer` installs nothing either:
its install step hangs on the executable's Compile step and installs no file
(`consumer/build.zig:145-149`), which is the same reason the library's smoke
example is compiled but never installed.

**Caller flags survive.** Every entry ends its command line with `"$@"`, after
the flags this file names, so a caller's `-j8`, `--summary all` or `-D…` still
reaches the build runner and still wins. No job count is pinned here: `-j8` is
the workspace's gate convention (the workspace `README.md` § "Verification
ownership and command entry points"), and a committed entry that fixed it would
override a caller who chose otherwise.

**Names are unchanged, deliberately.** `sdk.build`, `sdk.test`,
`sdk.test-release-safe`, `sdk.smoke`, `sdk.check`, `sdk.integrity` and
`sdk.consumer` keep their dotted spelling. These are devenv **scripts**, and
devenv's `namespace:name` rule is a rule about task names; the same run
confirmed the distinction in both directions — these seven were catalogued and
their wrappers executed, and a `sdk.build` *task* spelling was rejected as
`Invalid task name` elsewhere in the same wave. No name was renamed to fix a
cwd.

**Status: `PENDING-VERIFICATION`.** The two failures above are the driver's
observed receipts for the bytes that were in this file before the change. No
build, test, smoke, cross-target, Nix or devenv command was run by the role
that wrote this entry, so nothing here claims that any entry passes now.

### 48. Named the gate flags on every canonical `zig build`, and let each entry settle its own build cache

**Condition.** The workspace's recipe for a canonical verification command is
that it names `-j8`, an explicit `--cache-dir` and `--summary all` — workspace
`AGENTS.md`: "Add -j8, --cache-dir ... and --summary all". Entry 47 above named
none of the three: its six `zig build` lines carried no `-j` and no `--cache-dir`
and no `--summary`, so a canonical `devenv shell -- <name>` run used whatever
core count the host offered and the cache Zig picked by itself.

**Cause.** Entry 47's reasoning was that a committed entry fixing the count
"would override a caller who chose otherwise". That does not hold for this
command line. `"$@"` comes last, and Zig reads the *last* value of each of these
flags, so naming them before `"$@"` changes what the entry does when the caller
says nothing and leaves a caller who does say something exactly as before. Left
alone, the count was delegated to a host nobody controlled and the cache fell
back to the `.zig-cache` Zig writes beside `build.zig` — inside this checkout —
so a gate could not be reproduced and a build wrote into the source tree.

**Fix.** Every `zig build` in `devenv.nix` now carries `-j8 --cache-dir … --summary all`
before `"$@"`: `sdk.build` (the default step, with `--prefix`), `sdk.test`,
`sdk.test-release-safe`, `sdk.smoke`, `sdk.check` and `sdk.consumer`. `"$@"`
still comes last in all six, so a caller's own `-j`, `--cache-dir`,
`--summary none` or `-D…` still wins; each flag is named exactly once per
command. No prefix was added to the five steps that install nothing, and no step
name, script name, description, linkage default or `"$@"` forwarding was
changed. `sdk.integrity` runs `sha256sum` and reaches no build, so it is
unchanged. This supersedes the "No job count is pinned here" paragraph of
entry 47, which is left above as the record of what that entry did.

**The caches are settled in the body, not only in `enterShell`.** `enterShell`
still fills `ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` from
`HOST_SCRATCH_ROOT` and still leaves a caller's values alone; a `TasksRun`-mode
route never reaches that hook, so it was never enough on its own. Each entry
that reaches `zig build` now runs one shared preamble first: a caller's
`ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` win untouched, a missing one is
filled from `XDG_CACHE_HOME`, else from `TMPDIR`, and with the local cache still
unnamed the entry stops and says which variable is missing. Both are scratch the
caller already named, so no host path is written: `/tmp` and `/var/tmp` are not
approved mounts and this checkout is not scratch. Each of the six commands then
passes `--cache-dir "$ZIG_LOCAL_CACHE_DIR"` explicitly, so no entry can reach the
SDK default `.zig-cache`; for `sdk.consumer` that also keeps a second one out of
`<sdk>/consumer`.

**A `cd` that fails now stops the entry.** `inSdk` and `inConsumer` gained
`|| exit 1`. Without it, a missing SDK directory left the body running in the
caller's own directory, which is the one directory entry 47 exists to keep a
build out of.

**Not touched, deliberately.** `cross-test` is not one of these entries:
`cross-test.profile.sh` and the harness's `--jobs`/`--build-jobs` defaults are
the harness's own, not a `devenv` route. `README.zig.md` § "Verification status"
records one observed 53-target `cross-test` invocation with `--jobs 2
--build-jobs 4`; that is a receipt of a run that happened, and it is not
rewritten. A *new* cross-test invocation names `--jobs 8 --build-jobs 8`.
No new cache variable name was introduced either: the preamble uses the
`ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` this file and `enterShell`
already used, and no alias for them exists anywhere. `package.nix`, `build.zig`,
the flake, the native sources, headers, tests, data and licence bytes are
unchanged.

**Status: `PENDING-VERIFICATION`.** This entry is source-only. No build, test,
smoke, cross-target, Nix or devenv command was run by the role that wrote it,
and no gate has yet looked at these bytes.

### 49. Gave each interpolated preamble its own line, so a `cd` and an `if` stop being one word

**Condition.** Entry 48 gave every `zig build` entry two interpolated fragments:
the directory change (`${inSdk}`, or `${inConsumer}` for the consumer package)
and the shared cache preamble `${requireExternalCache}`. Both are Nix indented
strings and both were correct as values. The driver's canonical-environment run
of `2026-10-04T212645Z` executed `sdk.consumer` and it exited **2** before a
single build step ran, with the generated wrapper reporting
``syntax error near unexpected token `then'`` on line 1 and echoing that line.

**Cause.** An indented string is line-oriented and an interpolation contributes
no separator of its own, so two interpolations written on one source line
become one shell line. `requireExternalCache` begins with the `i` of `if` —
the newline that opens `''` is not part of its value — and `inSdk` ends with
`exit 1`, so the rendered line was
`cd …/consumer || exit 1if [ -z "${ZIG_LOCAL_CACHE_DIR:-}" ] … ; then`. The
`1if` is the diagnosis: `exit` was handed the argument `1if`. Both fragments
were correct and their composition was not, which is why the other seven gates
of that same run passed and this one did not.

**Fix.** One interpolation per source line, at all six sites: `sdk.build`
(`devenv.nix:139-140`), `sdk.test` (`:162-163`), `sdk.test-release-safe`
(`:174-175`), `sdk.smoke` (`:183-184`), `sdk.check` (`:192-193`) and
`sdk.consumer` (`:212-213`). That is the whole change to the file.
`sdk.integrity` is untouched and correctly so: it runs `sha256sum`, reaches no
build and has no preamble (`:204-205`). Nothing else moved — the seven dotted
script names, their descriptions, `"$@"` still last on every command so a
caller's own flags still win, `sdk.build`'s `--prefix` still under
`ZIG_LOCAL_CACHE_DIR` and still alone in naming one, a caller's own cache
variables still untouched, the pinned nixpkgs revision in `devenv.yaml`, and
`package.nix`, `flake.nix`, `build.zig`, `build.zig.zon`, the native sources,
headers, tests, data and licence bytes.

**Status: `observed`.** The canonical run of `2026-10-04T214134Z`
(`pcre2-index.json`) is **devenv-only** — `scope: "devenv"`, `gates_not_run:
["nix:build"]` — and answers `status: "pass"` with `gates_failed: []`,
`gates_unsupported: []` and `problems: []` across eight gates: `devenv:info`,
`devenv:tasks-list`, `devenv:canonical-integrity-mapping`,
`devenv:shell-zig-version`, `devenv:shell-zig-env`, `devenv:consumer`,
`devenv:integrity` and `repo:untouched`. The gate that was red now answers 0,
with `pcre2-devenv-consumer.log` printing `run success`,
`Build Summary: 18/18 steps succeeded` and `every line matched with the offsets
worked out by hand`; `pcre2-devenv-integrity.log` answers `OK` for every
record it replays; `pcre2-devenv-shell-zig-version.log` answers `0.16.0`, the
real compiler this SDK pins. `repo:untouched` records the seven canonical
config files and the 718-entry source listing as identical before and after
the run, which is a statement about that run.

**What this run does not say.** No Nix output was built and no
`devenv build outputs.static` / `outputs.shared` was evaluated, because
`nix:build` is on the not-run list. Neither did `sdk.build`, `sdk.test`,
`sdk.test-release-safe`, `sdk.smoke` or `sdk.check` execute in it: the route
ran `sdk.consumer` and `sdk.integrity`, and catalogued the other five by name.
Those five keep the `PENDING-VERIFICATION` state entry 48 left them in, and
nothing here is a claim that this SDK is finished.

### 50. Established the translated-header generation's platform configuration before it creates the modules

**Condition.** The runtime branch substitutes one call for the other at
`build.zig:1381-1388`: it takes
`graph.createModule(b, translate_c, options.target, options.optimize)`, and the
linked branch takes `translate_c.createModule()`. The comment at
`build.zig:1029-1034` says why — the runtime branch generates its dispatch from
*this* build's `translate_c` step, so the translated type and constant namespace
is the one this build produced rather than a second, nominally distinct copy.
Below that, `runtime/graph.zig:294` (`createModule`) builds
`runtime/library.zig` (`:302`), calls `generateDispatch` (`:326`), and builds the
dispatch (`:328`) and native (`:342`) modules; `generateDispatch` (`:365-379`)
is where the generator executable is created, `runtime/generate.zig` as its root
module at `.target = b.graph.host` and `.optimize = .Debug`.

An earlier positive-system **case** reported **28 undefined-symbol diagnostics
from the compiler — one case, 28 diagnostics, not 28 separate cells**. That was a
red result, not an all-PASS one, and this entry does not turn it into one.

**Fix.** The host/target selection and the selected platform configuration are
now established **before** `createModule` is called, rather than being read
afterwards. The ordering that was staged before it was itself wrong and has been
replaced by the correct one; it is not what this entry records. No native byte,
header, test, fixture, licence or upstream file changed with it — `build.zig` and
`runtime/graph.zig` are the whole of the change.

**Status: applied; not yet re-gated.** **No receipt re-runs pcre2 after this
fix**, so every count this repository holds predates it and none of them is
evidence for it: the 53-target cohort `20261004T221720228710Z-45046`
(`pcre2-53-target-8.json`) at **20 runtime PASS, 33 `build_only`, 0 fail**, exit
0, `source_unchanged: true`, `jobs_honoured: true`; the compile-only six-target
baseline `20261005T014547Z-797a73f2` (`baseline-pcre2-check`, exit 0,
`failed: false`, `runtime_pass_claimed: false`); the native 8-cell wave
`20261004T233628757747Z-69351` at 8 pass; and the own-loaded 8-cell wave
`20261004T232823091897Z-23133` at 8 pass. `build_only` is
compiled-but-not-run and is never a runtime pass, so 53 targets built is not 53
runtime passes. **No cell from the red wave is promoted to PASS.** The
independent external-provider route recorded no
`counts_as_external_coverage: true` at all (`20261004T232439Z`,
`pcre2-index.json`): the only successful route is this package's own
source-built provider, and every external candidate is an expected refusal — a
boundary, not coverage.
