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

## 3. Compiled the full 8-bit Unicode core — 31 translation units, explicitly

The core is the 30 entries of `core_sources` (`build.zig:90-121`) plus
`src/pcre2_chartables.c.dist`, which ships under a `.dist` name and is copied
to `pcre2_chartables.c` and compiled (`build.zig:486-494`). That is the
interpreter (`pcre2_match.c`), the DFA matcher (`pcre2_dfa_match.c`) and the
complete Unicode property machinery — not a subset chosen for convenience. The
list is explicit rather than globbed so a new upstream unit cannot enter the
archive without a decision here.

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
declarations, `pcre2_dfa_match`, `pcre2_substitute` and the serialization calls
the facade does not wrap.

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
`10/10 tests passed`: the default **8-bit** build and the whole suite. The
width cannot drift — the harness passes `-Dtarget` and nothing else,
`-Dcode-unit-width` keeps its default of 8, and `test`, `smoke` and `check`
refuse 16 or 32 outright (`build.zig:326-342`) rather than running an empty
step.

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
