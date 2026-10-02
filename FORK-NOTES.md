# FORK-NOTES.md — what actually went wrong, and what was decided

Problems met while packaging `PCRE2Project/pcre2` as a Zig 0.16 package, and
the decisions they forced. Written in the shape a later wave can reuse:
**condition, symptom, fix, targets bound**. Statuses are the workspace's:
`OBSERVED` (a driver run printed it, receipt named), `SOURCE-CONFIRMED` (read
out of a file, never executed), `PENDING-VERIFICATION` (landed, no gate has
looked at it), `NOT RUN` (no receipt exists at all).

Most of the entries below are not defects in PCRE2. They are mistakes in this
fork's own Zig, its own build graph and its own expectations.

---

## 0. Every gate this package has ever run

**The current states live in [`README.zig.md`](README.zig.md) § "Verification
status"**, which is the only gate table in this repository that is kept current.
This one is history, kept because entries 2, 3, 6 and 7 are only legible against
the receipts that found them.

All eleven receipts below are from 2026-10-01. The time column is the receipt
file's modification time, which orders the runs but is not itself a run
timestamp; no run recorded its own clock here.

| # | Command (after `zig`, with `-j8 --cache-dir /home/tmp/gertullj/foundation-libs-cache/pcre2/native-debug --summary all`) | mtime | Exit | Receipt |
|---|---|---|---|---|
| 1 | `build test -Doptimize=Debug` | 17:48 | 1 | `local://foundation-expansion-pcre2-initial-debug-19.log` |
| 2 | `build test -Doptimize=Debug` | 18:11 | 1 | `local://foundation-expansion-pcre2-repaired-debug-27.log` |
| 3 | `build test -Doptimize=Debug` | 19:16 | 1 | `local://foundation-expansion-pcre2-current-debug-51.log` |
| 4 | `build smoke` | 19:16 | 1 | `local://foundation-expansion-pcre2-current-smoke-57.log` |
| 5 | `build` | 19:17 | 1 | `local://foundation-expansion-pcre2-current-install-61.log` |
| 6 | `build test -Doptimize=ReleaseSafe` | 19:17 | 1 | `local://foundation-expansion-pcre2-current-releasesafe-63.log` |
| 7 | `build run` in `consumer/` | 19:17 | 1 | `local://foundation-expansion-pcre2-current-consumer-64.log` |
| 8 | `build smoke` | 19:35 | 1 | `local://foundation-expansion-pcre2-repaired-smoke-proof-70.log` |
| 9 | `build smoke` | 20:01 | 1 | `local://foundation-expansion-pcre2-latest-smoke-88.log` |
| 10 | `build smoke` | 20:21 | **0** | `local://foundation-expansion-pcre2-api-smoke-proof-110.log` |
| 11 | `build test -Doptimize=Debug` | 20:21 | 1 | `local://foundation-expansion-pcre2-api-debug-proof-117.log` |

**Everything after those eleven.** The suite went green in both modes, the
install and consumer gates produced results for the first time, all six
cross-target compiles ran, `sha256sum -c UPSTREAM.sha256` ran, the installed-C
program was compiled and run against this tree's own prefix, and `-fsys=pcre2-8`
was run against an installed **10.45**. On 2026-10-02 the published
53-platform matrix ran for the first time — red, and entries 17-20 below are
what closed it. Those receipts are `observed`; the current states live in
`README.zig.md` § "Verification status", which is the only table kept true.
What is still **not run** is system-mode ReleaseSafe, this repository's own
`.github/workflows/verify.yml`, any execution of a foreign cell's binary, and
the current filtered-package proof that runs after these documents settle.

Two things follow from the table above and are worth stating before any of the
entries: **exactly one of these eleven receipts is green**, and it is a smoke
run, not a test run; and a receipt describes the files as they stood when it was
produced. Receipts 3 to 7 all failed at *configure* time, before a single step
ran, so they are not evidence about the library, the tests or the consumer at
all.

---

## 1. `packed struct(Compile)` — a backreference this Zig no longer has

**Condition.** The option structs were written in Zig 0.14's backreferencing
form, naming the enum type in the struct header so the field type could be
inferred.

**Symptom.** Receipt 1, three compile errors before the first test could run:

```
zig/root.zig:143:42: error: use of undeclared identifier 'Compile'
pub const CompileOptions = packed struct(Compile) {
                                         ^~~~~~~
zig/root.zig:237:40: error: use of undeclared identifier 'Match'
pub const MatchOptions = packed struct(Match) {
                                       ^~~~~~~
```

**Fix.** Write the field type out: `packed struct { … }` with every field
annotated. The current `CompileOptions` and `MatchOptions` are
`packed struct` with explicit `bool` fields defaulted to `false`, which is also
what makes `.{ .{} }` and a partial literal both valid.

**Bound to.** The pinned Zig 0.16.0 compiler. A diagnostic of this shape is a
removed language feature, not a typo: the identifier in the error is a name the
compiler looked for and did not find, and the fix is the modern spelling rather
than a local declaration of something with that name.

**Status.** `OBSERVED` (receipt 1); repaired before receipt 2.

---

## 2. `-3...-23` is a range with its ends the wrong way round

**Condition.** The invalid-UTF arm of `Regex.match` has to name the numeric
range PCRE2 uses for UTF validity failures, which are **negative**:
`PCRE2_ERROR_UTF8_ERR1` is -3 and `PCRE2_ERROR_UTF8_ERR21` is -23, so the
range runs from -23 up to -3.

**Symptom.** Receipt 2, a compile error rather than a wrong answer:

```
zig/root.zig:563:15: error: range start value is greater than the end value
           -3...-23, -36 => .{ .invalid_utf = .{ .code = rc, .text = diagnostic(rc) } },
           ~~^~~~~~
```

**Fix.** `-23...-3, -36`.

**Cause, and the general part.** The error numbers were read off the header's
*declaration order* rather than their *numeric order*, and a C error table is
declared in whatever order is readable, not sorted. When a numeric range is
built from a C enumeration, read the **values**, not the sequence. Zig's
compile-time rejection of the reversed range is the good outcome: a reversed
range that happened to be accepted would have been a silently empty arm.

**Bound to.** Any wrapper that turns C's negative status codes into a Zig range
or a `switch` arm. This one is specific to Zig's `...` rejecting a descending
pair, but the read-the-values rule is not.

**Status.** `OBSERVED` (receipt 2) for the failure; the repair is in the sources
the green Debug and ReleaseSafe suites were built from.

---

## 3. A `usize` index where the facade takes a `u32`

**Condition.** The fixture replay loops over capture numbers and calls
`MatchData.groupRange(number: u32)` with a loop index that Zig types as
`usize`.

**Symptom.** Receipt 2:

```
tests.zig:389:50: error: expected type 'u32', found 'usize'
       const range = (try match_data.groupRange(i)) orelse return error.FixtureMismatch;
                                                 ^
tests.zig:389:50: note: unsigned 32-bit int cannot represent all possible unsigned 64-bit values
```

**Fix.** An explicit bounded conversion at the call site, `@intCast` under a
`u32` bound the loop already establishes, rather than widening the parameter to
`usize` to make the call compile.

**Bound to.** Any facade whose group numbers are `u32` because that is what
`PCRE2_SIZE`-derived indices are on this target. Widening the parameter would
have been the wrong fix twice over: it hides the bound, and it makes a later
unbounded `usize` index look type-safe when it is not.

**Status.** `OBSERVED` (receipt 2) for the failure; the repair is in the sources
the green Debug and ReleaseSafe suites were built from.

---

## 4. A struct literal that does not compile means nothing ran, not something failed

**Condition.** `build.zig` passes one `Pcre2Options` literal into
`addPcre2(b, .{ … })`. The options struct and that literal are edited together,
and they drifted apart twice.

**Symptom.** Receipts 3, 4, 5, 6 and 7 are **five different commands printing
the same two lines**:

```
build.zig:262:10: error: no field named 'sanitize_c' in struct 'build.Pcre2Options'
        .sanitize_c = sanitize_c,
         ^~~~~~~~~~
build.zig:160:22: note: struct declared here
const Pcre2Options = struct {
```

and then, after that was fixed, receipt 8:

```
build.zig:260:32: error: missing struct field: use_system
const pcre2 = addPcre2(b, .{
                              ~^
```

**Fix.** Bring the struct declaration and the literal back into agreement.

**Cause, and the general part.** These are the two directions of the same
check — a field the struct does not have, and a field the literal does not
supply — and both are diagnosed **at configure time, before any build step
runs**. That is why five receipts for five unrelated gates (Debug, smoke,
install, ReleaseSafe, consumer) carry the same error: the graph never reached
the C, the facade, the tests or the consumer. A receipt of that shape is
evidence about `build.zig` and about nothing else, and a reader who treats five
identical red receipts as five findings has misread all five.

**Bound to.** Any build graph with a hand-written options struct threaded
through more than one call site. The check is exact and bidirectional, which is
what makes it cheap — but it fires before any work, so it must never be read as
a partial result.

**Status.** `OBSERVED` (receipts 3-8); repaired before receipt 10, and every one
of the five gates that failed at configure time has since produced a result.

---

## 5. A sentinel in a return type is a fact about storage, not a decoration

**Condition.** `version()` builds the version string in a local buffer and
returns a slice of it. The declared return type gained a `[:0]` sentinel to
say "this really is NUL-terminated at `len`".

**Symptom.** Receipt 9, one line:

```
zig/root.zig:819:49: error: expected type '[:0]const u8', found '[]const u8'
           return @as([*:0]const u8, @ptrCast(&buffer))[0..@intCast(written - 1)];
           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~
zig/root.zig:819:49: note: destination pointer requires '0' sentinel
```

**Cause.** The sentinel is a **promise the compiler then checks**. A
`@ptrCast` to `[*:0]` asserts that the last byte is a zero; the code asserted it
without having established it. The compiler caught a claim the function was
making up.

**Fix.** Query the required size with `pcre2_config_8(PCRE2_CONFIG_VERSION, null)`
first, compare it against `buffer.len` — the count **includes the terminating
NUL** — as an ordinary comparison before the call that writes, and then return
`buffer[0..len :0]` into a **caller-owned** buffer. The real bug underneath was
never the sentinel: the original function returned a pointer into a frame that
had already been reused, and the sentinel made the lie checkable.

**Bound to.** Any function returning `[:0]const u8` derived from a C library
that writes into storage the caller owns. Two rules generalise: a `pcre2_config`
style query is a size query when its second argument is null, and a function
must never return a borrow of its own frame.

**Status.** `OBSERVED` (receipt 9); repaired, receipt 10 is the green run that
shows the repaired form working, and the contract is now a permanent test
(`the version answer is the caller's own buffer, and a short one is refused`)
that passes in both Debug and ReleaseSafe.

---

## 6. A reused match block hands back offsets from a subject that is gone

**Condition.** One `MatchData` is reused across several subjects, which is what
a caller streaming lines does. Upstream keeps its offset vector across a failed
attempt.

**Symptom.** Not a gate failure first: a **real out-of-bounds read** found by
review and then made into a test. Reusing one block for `(\d+)-(\w+)` matching
`"123-abc"` and then a non-match on the one-byte subject `"z"` leaves group 2
at bytes 4..7 of the *first* subject. Returning those offsets and indexing the
*second* subject with them reads past its end: a bounds panic in Debug and
ReleaseSafe, a silent read of unrelated memory in ReleaseFast.

**Cause.** Upstream's contract, which is documented rather than inferred —
`doc/html/pcre2api.html:3330-3334`, "After a failed match attempt, the contents
of the ovector are unchanged" — combined with `src/pcre2_match.c:1045-1053`,
where `ovector[]` is written only on the path that matched. The facade returned
upstream's vector without asking whether that path was the one taken.

**Fix.** A chosen contract, and the choice is the lesson:

* `MatchData` carries an explicit `matched` validity flag.
* `Regex.match` **clears it for every attempt**, including one refused before
  any C runs, and sets it only when `pcre2_match_8` returned zero or more.
* `groupRange` and `group` answer null whenever the flag is false.
* The group-number bound still comes **first**, so `NoSuchGroup` stays a
  statement about the index rather than about the match state.
* `startOffset()` is documented as the one field that survives a failed attempt,
  because every negative return except a validity failure leaves it untouched.

Two alternatives were considered and rejected: returning the previous attempt's
offsets (which is what upstream does, and which is a trap rather than a
contract), and silently keeping a borrow of the previous subject (whose
lifetime the caller may already have ended). The raw C escape hatch still
offers upstream's behaviour, and `MatchData.subject` is public for a caller who
deliberately wants the last subject.

**Bound to.** Any wrapper over a library whose result vector is caller-owned and
whose "no result" path leaves that vector untouched. The rule generalises
further: **when a library documents that a failed call leaves its output buffer
alone, a wrapper must invalidate that buffer's meaning itself** — an explicit
validity flag, not a sentinel value, because a sentinel is one of the values a
real result can take.

**Status.** `OBSERVED`, in both directions. The stale-offset condition was
observed for; the repair is now permanent — `tests.zig`'s `an attempt that did
not match leaves nothing readable, whatever the last one found` and
`smoke.zig`'s last two lines both prove it, and that test passes in Debug and in
ReleaseSafe. Receipt 11 remains what it was: a later run reporting two `nameAt`
failures rather than this one.

---

## 7. A C out-parameter that was a Zig optional, not a pointer

**Condition.** A C function that fills in an out-parameter of pointer type,
reached from Zig through a variable declared as an **optional** pointer.
`pcre2_pattern_info_8` writes `PCRE2_INFO_NAMETABLE` through such a parameter,
and `Regex.nameAt` then dereferences the result per call.

**Symptom.** Receipt 11, the first gate that reached the test binary, two
failures with the same cause:

```
run test 7 pass, 2 fail (9 total)
error: 'tests.test.every known answer in the fixture table holds' failed:
       tests.zig:83:63: const entry = compiled.nameAt(@intCast(i)) orelse return error.FixtureMismatch;
error: 'tests.test.a name the pattern did not declare, and a name too long to declare, are both null' failed:
       tests.zig:294:41: const last = regex.nameAt(1) orelse return error.FixtureMismatch;
```

**Why the second failure is the informative one.** The same test asserts that
`nameAt(2)` on a two-entry table **is** null, and the facade agreed there. So
the bug is not a table that is always absent; it is a read that comes back
empty for a real entry and coincidentally right past the end of the table. A
test whose only assertion were "a name can be read" would not have localised
it; the control case beside it did.

**Cause — and the detail that made it look like a different bug.** `fromRaw`
declared the `PCRE2_INFO_NAMETABLE` out-parameter
`var name_table: ?[*c]const u8 = null;` and passed `&name_table` to
`pcre2_pattern_info_8` (`zig/root.zig:625` and `:642-643`, before the
repair). **A Zig optional of a C pointer is not a pointer.**
`?[*c]const u8` is 16 bytes — an 8-byte payload with the tag byte after it —
because only `?*T` is given the null-pointer representation, which is why
`Regex.code: ?*c.pcre2_code_8` is 8 bytes and `Regex.name_table:
?[*c]const u8` is 16. `src/pcre2_pattern_info.c:229-232` writes
`sizeof(PCRE2_SPTR)` = 8 bytes into the payload and never touches the tag, so
the optional read back as **null for every compiled block**. `nameAt` then
took its `self.name_table orelse return null` guard for every in-range index.

The misleading part is that the *other three* queries were right:
`capture_count` and `name_count` are `u32` out-parameters, four bytes, written
correctly, so `captureCount()` and `nameCount()` passed **first** in both
failing tests and the failure presented as a table-indexing problem. It was
not one. `Regex` has byte size 40, with `code` at offset 0, `name_table` at
offset 8 (byte size 16, its `has_value` tag at offset 8), `capture_count` at
24, `name_count` at 28 and `name_entry_size` at 32 — and `Regex.nameAt`
compiles to one comparison of that tag byte against zero before it reads
anything.

**Fix.** The out-parameter is a bare C pointer,
`var name_table: [*c]const u8 = undefined`, and `.name_table = name_table`
coerces into the **unchanged** field type `Regex.name_table: ?[*c]const u8`,
because a caller genuinely wants to be able to see an absent table. No
signature changed: `nameAt`, `nameForNumber`, `numberForName` and `nameCount`
keep theirs, and the name slice is still the same window on the compiled block,
still valid only while the `Regex` lives, still not NUL-terminated within the
slice. Two smaller corrections came with it: the four request numbers are now
the translated header's own `PCRE2_INFO_CAPTURECOUNT` / `NAMECOUNT` /
`NAMEENTRYSIZE` / `NAMETABLE` constants (`src/pcre2.h.generic:450`, `:463-465`)
rather than the numbers `4`, `17`, `18`, `19` written out by hand, so the
request cannot drift from the header the archive was compiled against — which
also matters in `-fsys=pcre2-8` mode, where the translated header is the
installed one; and the entry-size floor is a checked `if (size < 3) return
null` with its reason beside it.

**The contract wording that was wrong with it.** The facade claimed PCRE2
"stores names in order of first appearance". Upstream keeps the table in
**name (alphabetical, `strcmp`) order** — see the three facts below. Every doc
comment on `nameCount`, `nameAt` and `nameForNumber` and on the `name_table`
field was reworded, and one claim was dropped: that the field is "empty when
the pattern has no names". PCRE2 answers a table address for **every** compiled
block, including one with no names
(`src/pcre2_pattern_info.c:229-232`).

**The test that now distinguishes order from appearance.** Every existing
fixture used two same-length names written in sorted order, so none of them
could tell name order from appearance order, and none reached the padding
boundary. A new test, `the name table is walked in name order, and an entry
ends at its own NUL`, uses `(?<zebra>1)(?<m>2)(?<alpha>3)(?<al>4)`, whose
table is `al(4), alpha(3), m(2), zebra(1)` — a prefix pair of different
lengths, which is what makes "the name ends at the entry's own NUL, not at the
end of the entry" observable at all. No fixture, expected name, expected count
or expected capture in `testdata/foundation-fixtures.zig` changed.

**Bound to.** Any wrapper that passes `&optional_thing` to a C function as an
out-parameter. The general rule, and the part that transfers: **a C
out-parameter must have exactly the C type.** A Zig optional is a different
type with a different size, and a C function that writes `sizeof(T)` bytes
into it will leave the tag whatever it was — `null` for a fresh local, and
something else for a reused one. This is invisible to the type checker,
survives Debug, and produces a *plausible* wrong answer rather than a crash;
and it hides best when the neighbouring out-parameters of the same call are
correct, which is exactly what happened here. The test that found it was not
a table test; it was the control assertion that an out-of-range index is null,
sitting next to the in-range one.

**The three facts about the table itself, read out of the C in this tree, so
that a later wave does not re-derive them.** `PCRE2_INFO_NAMETABLE` answers
`(const char *)re + sizeof(pcre2_real_code)`
(`src/pcre2_pattern_info.c:230-232`), and the compiled code follows *after* the
table (`src/pcre2_compile.c:10985-10990`). `name_entry_size` is sized to the
**longest** name in the pattern plus `IMM2_SIZE` plus one
(`src/pcre2_compile.c:5713-5716`), and each entry is written with a
terminating zero and zero padding out to that size
(`src/pcre2_compile_cgroup.c:167-175`), so a short name is followed by NUL
bytes rather than by the next entry — the name is ended by the NUL *inside* the
entry, not by the end of the entry. And the table is in **alphabetical (name)
order**: the insert routine's own header says it is "maintaining alphabetical
order" (`src/pcre2_compile_cgroup.c:106-108`) and
`pcre2_substring_number_from_name` binary-searches it with `strcmp`
(`src/pcre2_substring.c:495-523`). So `nameAt`'s index is a position in the
table, not a group number, the group numbers it yields need not ascend, and
`nameForNumber` is a scan rather than an index. The `(?<abc>x)(?'xyz'y)`
fixture shows `abc 1` then `xyz 2` (`testdata/testoutput2:7312-7314`), which is
what alphabetical order gives there and also what appearance order gives, so
that fixture does not by itself distinguish the two — the C does.

**Status.** `OBSERVED red` (receipt 11), and `OBSERVED green` since: the suite
is `10/10 tests passed` in both Debug and ReleaseSafe against the current
sources, so the repair and the test it added are both exercised.

---

## 8. A compile-only cross-target check proves what it compiles, and nothing else

**Condition.** `zig build check` compiles the C core, the facade, `tests.zig`
and `smoke.zig` for six targets and runs nothing. Zig analyses a function body
only when something calls it, so the test and smoke roots are what make the
check a check of the facade rather than of an unreferenced archive.

**Result.** All six current baseline commands exit 0: 9/9 steps on the three
GNU-libc Linux cells, 10/10 on the three extra-front-end cells. Earlier uniform
9/9 counts are historical. Both rounds prove compilation, not execution.

**Bound to, and the rule to carry.** A cross-target *compile* is evidence about
types, symbols, widths, `link_libc` and the target's own header assumptions. It
is **not** evidence about a platform's runtime limits: locking, threads, syscalls
that are absent, and an SDK a build needs are all invisible to it. Every one of
the six now has a compile observation and **none** has a runtime observation,
because `check` cannot produce one. So this package claims that all six compile,
and claims **neither** that any of them works at run time **nor** that any of
them is unsupported. A runner, an emulator or a real device owns the other half
of that answer.

The related obligation: every public declaration in `zig/root.zig` must have a
call site in `tests.zig` or `smoke.zig`, or `check` silently stops covering
it. `std.testing.refAllDeclsRecursive` does not help — a namespace has no body
to analyse, so a function reached through a public namespace still needs its own
call.

---

## 9. A red system-mode gate is a version difference until it is shown otherwise

**Condition.** `-fsys=pcre2-8` links an **installed** PCRE2, which need not be
10.49. The fixture table, on the other hand, is pinned to 10.49 by construction,
because it is transcribed from this tree's own `testdata/`.

**Result.** The mode has now been run against this machine's installed PCRE2,
which reports `10.45 2025-02-05`. `smoke` and `consumer` both passed and both
printed that version; the Debug suite came back `9 pass, 1 fail (10 total)`.
The failure is the **first** of the three pinned rejections below:
`unmatched_closing_parenthesis_is_rejected_at_its_offset` answered error 122 and
the right message but **offset 0**, where 10.49 answers 1. Nothing was re-pinned,
loosened, skipped or hidden, and the red row was left red.

**Fix/decision.** Three fixture cases pin a compile rejection that 10.49
produces: error 122 at offset 1, error 106 at offset 4 and error 142 at offset
6, each with its exact message. A different installed release can legitimately
answer one of those differently, and that is a real difference between two
releases, not a binding fault. The system job therefore **prints** the installed
version rather than asserting one, and the rule is that such a difference is
read against that version and **never fixed by loosening a fixture**.

**What the difference turned out to be, and how far it can be pinned.** It is
not an ABI or header-mixing fault: the receipt shows `translate-c success` and
the test binary compiling and linking against the installed library before it
failed an assertion about one number. What this repository can say about *why*
is bounded by what it carries. Upstream's `ChangeLog` travels in this tree, and
its entry 13 of the **10.47** section (`ChangeLog:164`, `:220-221`) is *"(#756)
Improved error offsets and diagnostics for syntax errors during pattern
compilation"*, while 10.46's only entry is a security fix
(`ChangeLog:243-252`) — so a compile-error-offset change between 10.45 and
10.49 is documented in bytes this repository owns, and 10.47 is the release that
record names. The precise line of 10.45's `pcre2_compile.c` is **not**
identified, because those sources are not here; 10.49's are. Naming the exact
cause would be a guess wearing a citation.

**The general part, now that it has happened.** The decision above was written
down before the gate existed, and the gate paid it out: the red row was read as
a version difference, the fixture was left alone, and the two passing
system-mode gates were reported beside the failing one rather than instead of
it. A cross-implementation gate that only ever runs green cannot tell you which
half of the code was wrong; this one got to say that the binding was not.

**Bound to.** Any package whose known answers are transcribed from a specific
upstream release while offering a mode that binds a different one. The
generalisation: a cross-implementation gate needs a *release-independent*
oracle. `smoke.zig` has one by construction — every offset it checks is worked
out by hand from the subject string it prints, so a release can move it only by
changing what a match means — which is why the system job runs the smoke even
though its test run is expected to be release-sensitive.

---

## 10. A licence split by content must not be flattened into one grant

**Condition.** PCRE2's `LICENCE.md` grants three different things over one
tree: BSD-3-Clause-with-exception for the library and `doc/`, **public domain**
for `testdata/`, and a separate 2-clause BSD for the just-in-time compiler.

**Symptom.** None. This is a decision recorded before writing `NOTICE.md`, and
the reason it is written down is that the failure mode is easy and silent.

**Fix/decision.** `NOTICE.md` states the grant **per path**, names the two
files inside the hashed set that carry no per-file copyright header
(`src/pcre2_chartables.c.dist`, which is machine-written by `pcre2_dftables`,
and `src/config-cmake.h.in`, which is a bare `#cmakedefine` template), and says
plainly that **this is a BSD licence and no Apache-2.0 obligation applies**: no
`NOTICE`-file requirement, no change statement requirement, and **no patent grant
and no patent-grant termination clause**, because the shipped licence grants no
patent licence. The file exists because this fork wants the attribution in one
greppable place, and it says so.

**Bound to.** Any vendored tree whose licence file splits its terms by content
rather than covering everything at once. Two traps: treating a whole tree as one
grant when the licence says otherwise, and importing another licence's
obligation vocabulary (`NOTICE`, "state that files were changed", patent
termination) into a licence that has none of them.

---

## 11. An option that can only work with a network fetch must be removed, not kept

**Condition.** Upstream's Zig graph exposes `-Dsupport_jit` and a lazy `sljit`
package dependency, because `pcre2_jit_compile.c` compiles against sljit.

**Symptom.** Not a failure. The finding is from reading the tree:
`.gitmodules:1-3` names `deps/sljit` as a submodule, and **`deps/sljit` is an
empty directory in this checkout**. Upstream's option therefore resolves the
source either from a submodule that is not there or from `b.lazyDependency`,
which is a network fetch.

**Fix.** The dependency and the option are **gone**, not left to fail later, and
`SUPPORT_JIT` is 0 in the generated `config.h` so the consequence is visible in
the build rather than in a comment. `src/pcre2_jit_compile.c` stays in the
compile list: with `SUPPORT_JIT` at 0 it defines nothing, and a unit that is
part of upstream's source set should still compile.

**Bound to.** Any fork whose contract is "no build-time download". A feature
flag that can only be satisfied by a fetch is not a feature, and leaving it in
the graph makes a package that appears to support something it cannot build.
Re-taking this decision is step 2 of the sync procedure in `UPSTREAM.md`,
because a populated submodule changes the answer.

---

## 12. An empty subdirectory in `.gitignore` is a latent deletion, not a comment

**Condition.** `.gitignore` is upstream's file, shared with every other PCRE2
checkout, and it is broad enough that a future upstream rule could swallow this
fork's own sources.

**Symptom.** None. The original six negations gained a seventh for the profile.

**Fix.** Upstream's list is kept verbatim and unedited
(`.gitignore:1-128`); the fork appends one comment block and `!translate.h`,
`!cross-test.profile.sh`, `!/zig/`, `!/tests.zig`, `!/smoke.zig`,
`!/consumer/`, `!/testdata/` (`.gitignore:150-156`). Each **directory**
is named as well as its contents,
because a negation cannot re-include a file whose parent directory is excluded.
The file is therefore not byte-identical to upstream's, so it is deliberately
absent from `UPSTREAM.sha256` and the append is recorded in `NOTICE.md` instead.

**Bound to.** Any fork that edits an upstream ignore file. The hash record and
the "files this fork changed" list then have to agree about the same file, or a
red `sha256sum -c` and an incomplete notice are the two symptoms of one
mistake.

---

## 13. `sha256sum -c` ignores comment lines, so a record can state its own scope

**Condition.** An integrity record that is only a list of digests says nothing
about *which* bytes it covers or how they were produced, and a reader who has to
guess will eventually guess wrong.

**Symptom.** None — a design decision taken before writing the file and checked
once, so the record could be written in the form it was wanted in.

**Cause.** If `sha256sum -c` refused comment lines, the record would have to be
either bare (and silent about its own scope) or split across two files. It does
not refuse them: `sha256sum -c` skips any line whose first non-blank character
is `#`, and so a single `UPSTREAM.sha256` can carry its own header, its record
count, its exclusions and the method that produced it, and still be directly
checkable with

```
sha256sum -c UPSTREAM.sha256
```

**Fix.** One file, `#`-prefixed header, `<hex>  <path>` records. The header names
every excluded path and the reason, names the hashing method (raw byte read,
Bun `arrayBuffer`, `node:crypto` SHA-256, no shell hashing command and no git
command), and states plainly that the record is a hash of **this working tree**
and not a re-derivation from the pinned commit.

**Bound to.** `sha256sum`'s comment handling, which is the same in every coreutils
this has met, and to any integrity record that wants to be self-describing. What
the record does **not** establish is equally important and belongs in the header
too: not a signature, not a Git object id, and not a claim that the tree equals
the pinned commit.

**Status.** `OBSERVED`. `sha256sum -c UPSTREAM.sha256` reported 59 records with
every line `OK` (exit 0) in this workspace, and `.github/workflows/verify.yml`
runs the same command as the first step of its native job, so the record is
checked here and in CI.

---

## 14. A receipt that reports a count becomes historical when the count moves

**Condition.** Receipt 11 reports `7 pass, 2 fail (9 total)`. Any later edit
that adds or removes a test changes what that number means.

**Symptom.** Not a failure — a change in what a receipt can mean. A reader who
compares "9 total" against a later suite has to work out which number moved and
why.

**Cause.** A suite's size is part of what a receipt reports, and a policy
removal or an addition changes it.

**Fix.** `README.zig.md` § "Verification status" is the one current table, and
it reports the current count next to the historical one: **10 tests now, `9
total` in receipt 11**, with the tenth named as the one the entry-7 repair
added. The same table reports `10/10 tests passed` for both Debug and
ReleaseSafe, so the count is no longer a claim about what has not been run.
(Entry 6's stale-offset repair landed *before* receipt 11, which is why receipt
11's seven passing tests already include the one that proves the stale read is
gone.)

**Bound to.** Any receipt that reports a count. When a gate's denominator
changes, every receipt with that denominator is historical, not current.

---

## 15. What is still open, stated so it is not mistaken for a plan

* **Nothing in the repair entries above is `PENDING-VERIFICATION` any more.**
  Every repair in entries 2, 3, 5, 6 and 7 is in the sources the green Debug and
  ReleaseSafe suites were built from. The states are in `README.zig.md` §
  "Verification status".
* **`-fsys=pcre2-8` has no ReleaseSafe receipt.** Debug is the only
  system-mode test run, and it is `9 pass, 1 fail` against an installed 10.45,
  for the reason entry 9 gives. System-mode `smoke` and `consumer` both passed.
* **This package is unpublished** — no registry entry, no release, no tag.
  `consumer/` resolves the dependency by relative path, so the package boundary
  is proven and the registry path is not.
* **This repository's own `.github/workflows/verify.yml` has never run here.**
  Its C-gate program has been built and run by hand, which is evidence about the
  program and not about the workflow.
* **The 10.45 offset difference is not an open bug.** It is a recorded difference
  between two releases; re-pinning the fixture is a decision someone may take
  deliberately, not a defect waiting to be closed.
* **The 53-platform `cross-test` matrix has been run; 33 of its 53 cells are
  compile-only.** Entries 17-20 are what its first sweep found and what closed
  the twelve failures. The current sweep is **20 pass, 0 fail, 33 build_only**,
  exit 0, and the 33 report `runtime_unavailable` on this host, so no BSD,
  Darwin, Windows or WASM binary has been executed here.

---

## 16. The cross-test settings are a file, and the file carries no licence

**Condition.** Entry 8 established that `zig build check` proves six
compile-only cells and nothing more. The workspace gate for the eight additions
is the published Zig 0.16.0 Tier 1/2 matrix, 53 platforms, run by
`~/.local/bin/cross-test`, whose cell is a real
`zig build test -Dtarget=TARGET`.

**Decision.** `cross-test.profile.sh` sits at the package root with four
variable definitions and nothing else — `CROSS_BUILD_STEP=test`,
`CROSS_BUILD_JOBS=2`, `CROSS_BUILD_TIMEOUT=1800`, `CROSS_TIMEOUT=600` — is
listed in `.paths`, is re-included by `!cross-test.profile.sh` in the fork's
block of `.gitignore`, and is named in `NOTICE.md` with **no licence
asserted**.

*Why a file at all.* `cross-test` discovers `./cross-test.profile.sh` and
`./test/cross-test.profile.sh` and sources whichever it finds
(`cross-test:618-622`). Without one it still runs, on its own defaults; with
one, this package states its own deadlines and the file travels with the
package, which is the half that matters — a harness settings file that only
exists in a working tree is a settings file the package does not have.

*Why no hooks and no matrix.* A profile defining `cross_build_command` or
`cross_artifact` switches the harness out of its standard Zig-build mode
(`cross-test:645-648`); one setting `CROSS_MATRIX` or `TARGETS` narrows the run
(`cross-test:650`, `:676-691`). Either would trade a published 53-platform gate
for a self-chosen subset. Every value here is a default, and
`--build-timeout`, `--timeout`, `--jobs` and `--build-jobs` override it
(`cross-test:628-633`).

*Why `CROSS_LIBC_RUNTIMES` is absent.* It is a directory of foreign libc loaders
on the machine running the harness. A host path inside a shipped package file
would make the package claim something about one machine. The harness reads it
from the environment, so it can be supplied without this package knowing.

*What this entry deliberately left alone.* Landing the profile changed no
`build.zig` line, no native source, no test and no fixture; running the matrix
is what later changed `build.zig` and `translate.h`, in entries 17-20.
`test` already attached a real run artifact (`build.zig:341-342`), so a cell
with a runner executes all ten tests and a cell
without one still compiles them; the harness replaces the run step's action
with a skip and keeps the compile dependencies (`run_policy.zig:55-57`,
`:103-105`), which makes an unrun cell `build_only` and not a pass. The
fifteen-case fixture table and the nine other tests are the same ten on every
cell, and entry 9's 10.45 offset difference is untouched because every cell
builds this tree's bundled 10.49.

**Status.** `OBSERVED`. The profile is what the harness reads, and the matrix
runs this package's real `test` step over all 53 published targets. The first
sweep, `20261002-040235-43000-5735`, was **20 pass, 12 fail, 21 build_only**,
exit 1; entries 17-20 are what those twelve became. The current sweep,
`20261002-071302-33056-11212`, is **20 pass, 0 fail, 33 build_only, 0 partial**,
exit 0, with all ten tests executed on each of the twenty cells that had a
runner.

---

## 17. Aro's preprocessor cannot read a foreign C library, so the real one runs first

**Condition.** `zig translate-c` parses with Aro, and Aro preprocesses as well
as parses, so `translate.h` was handed to it as it stands on every target.
`src/pcre2.h.generic:87-89` includes `<limits.h>`, `<stdlib.h>` and
`<inttypes.h>`, so every translation pulls in the **target's** C library
headers, not this repository's.

**Symptom.** The first full sweep of the published matrix, run
`20261002-040235-43000-5735`, came back **20 pass, 12 fail, 21 build_only**,
exit 1, and every one of the twelve was a `translate-c` failure on a C library
header rather than on anything PCRE2 writes:

* the **nine NetBSD cells** — NetBSD defines `__BEGIN_PUBLIC_DECLS` and
  `__END_PUBLIC_DECLS` with the `_Pragma` operator
  (`generic-netbsd/sys/cdefs.h:411-416`), Aro 0.16 leaves the pragma in the
  token stream, and the trailing `__END_DECLS` of `sys/types.h`, `sys/endian.h`,
  `sys/bswap.h`, `<stdlib.h>` and `<inttypes.h>` each stop parsing with
  `unknown type name 'pragma'`; `translate-c 25 errors` on `aarch64-netbsd`
  (`local://foundation-cross-test-matrix-pcre2-aarch64-netbsd.log:6-21`);
* **`mips64-openbsd` and `mips64el-openbsd`** —
  `generic-openbsd/mips64/endian.h:32-41` refuses to define `BYTE_ORDER` unless
  `__MIPSEL__` or `__MIPSEB__` is defined, and Aro's MIPS predefined macro
  table defines neither;
* **`x86-windows`** — `any-windows-any/malloc.h:183-187` derives
  `_ALLOCA_S_MARKER_SIZE` from `_ARM_`, `_X86_`, `__ia64__`, `__x86_64` or
  `__aarch64__`, and Aro's Windows-x86 predefined table defines none of them, so
  the two inline functions naming it do not compile.

**Fix.** `aggregateRoute` (`build.zig:635-700`) sends every target whose C
library is not GNU libc through the preprocessor that already compiles the C
core for it: `zig cc -E -dD -fno-blocks -x c` with the same `-target`, the same
`-I` on the generated `pcre2.h` copy, the same `-DPCRE2_CODE_UNIT_WIDTH` and
the same `-DPCRE2_STATIC` (`build.zig:825-851`), after which Aro parses the
result. `-dD` is load-bearing: without it the `#define` lines are gone from the
file Aro reads, and `pcre2.c.PCRE2_INFO_CAPTURECOUNT` and
`pcre2.c.PCRE2_CONFIG_VERSION`, which `zig/root.zig` names, stop existing.
`core_c_flags` is deliberately absent from that line — it is code generation,
and the preprocessor neither needs it nor acts on it.

**Why not a local repair.** Every substitute on offer invents the predefine the
real compiler supplies — `-D__MIPSEB__`, `-D_X86_`, a replacement for
`_Pragma` — and those macros decide what the C library headers *mean*, so each
one describes a target that does not exist. Reading the same header through the
compiler that builds the archive is not a substitute for any of them: the
target, the include path, the width and the linkage macro are the ones the
archive was built with, so the declarations the translator reads are the ones
that archive answers to.

**Bound to.** Aro 0.16.0's handling of `_Pragma` and its per-target predefined
macro tables, together with Zig 0.16.0's bundled libc headers. An Aro that
learned to read all of these would make the extra front end unnecessary; the
route would stay correct either way, because it reads the same header the core
was compiled against.

**Status.** `OBSERVED`. The next sweep, `20261002-054414-46667-18828`, is
**20 pass, 6 fail, 27 build_only**. Ten of the twelve closed; the four Darwin
and MacCatalyst cells, which had compiled while Aro preprocessed for itself,
failed for the first time in that sweep — entry 19 — and the two aarch64 NetBSD
cells stayed red with a different error, entry 20.

---

## 18. The one C library Aro reads well is the one the other front end breaks

**Condition.** Entry 17 fixed twelve cells by putting the target's own
preprocessor in front of Aro. The obvious generalisation of that rule is
"always preprocess", and following it regressed the three GNU-libc `check`
cells that had been green.

**Symptom.** The six-target baseline taken before these corrections
(`local://foundation-cross-test-baseline-before-sdk-corrections.json`, created
06:20:42Z, finished 06:32:06Z; 42 success, 5 failed, 0 timeout, 1 refused over
48 cells) reports `x86_64-linux-gnu`, `aarch64-linux-gnu` and `riscv64-linux-gnu`
**failed**, each `Build Summary: 6/10 steps succeeded` with
`translate-c 11 errors`. Aro reads the glibc headers; the target's own
preprocessor reads the same headers, expands them, and leaves five lines in the
file Aro then parses that Aro cannot parse. glibc hands a compiler with no
native `_FloatN` type a `typedef` for one, and the `!__GNUC_PREREQ(7, 0)` guard
on each of those lines held for the compiler that expands them here: the four
in `generic-glibc/bits/floatn-common.h:213-215`, `:250-252`, `:267-269` and
`:284-286`, and `_Float128` at `generic-glibc/bits/floatn.h:79-81` on aarch64
and riscv64 or `x86-linux-gnu/bits/floatn.h:94-97` on x86. Aro holds those five
names as builtin type specifiers of its own, so on each of those lines it has
read one declaration specifier, then a second, and then wants the name being
declared — `cannot combine with previous 'float' specifier` and
`expected identifier or '('`, eleven errors on `x86_64-linux-gnu`
(`local://foundation-cross-test-baseline-pcre2-x86_64-linux-gnu.log:3-35`).

**Fix.** The rule is the reverse of "always", and it is one line
(`build.zig:698-700`): `if (options.target.result.isGnuLibC()) .aro else
.preprocessed`. GNU libc is the one C library the translator's own front end
reads best, so that is the half of the matrix that reads `translate.h` as it
stands, with the two declaration macros on the translation line.

**Why the header is not repaired instead.** `pcre2.h` names none of those five
types and includes only `<limits.h>`, `<stdlib.h>` and `<inttypes.h>`
(`src/pcre2.h.generic:87-89`). Taking the typedefs out of the preprocessed text
would edit a C library header this build does not own; spelling
`typedef float _Float32` as anything else renames a standard type; and
`-D__GNUC__=7` or a `-D__clang_major__` on the preprocessing line describes a
compiler this target does not have — the same substitute entry 17 refuses.

**Bound to.** glibc's `bits/floatn*.h` and Aro's builtin `_FloatN` type
specifiers, in Zig 0.16.0's bundled libc. A glibc that stopped emitting those
typedefs, or an Aro that parsed them, would let these targets take the other
route too, and the rule would have to be re-read rather than assumed.

**Status.** `OBSERVED`, closed. All six of this package's cells are `success` in
the corrected baseline (`local://foundation-cross-test-final-baseline.json`),
and each GNU-libc log shows `translate-c success` with nothing but
`WriteFile pcre2.h (reused)` beneath it and **no `preprocess pcre2.h` step at
all** (`local://foundation-cross-test-final-baseline-pcre2-x86_64-linux-gnu.log:11-12`).

---

## 19. Two front ends must be asked for the same dialect

**Condition.** Entry 17 introduced a second front end. Before it, Aro
preprocessed the header itself; now, on most targets, Clang writes that text
and Aro parses it.

**Symptom.** Four cells failed in the sweep that first carried the extra front
end — `aarch64-macos`, `x86_64-macos`, `aarch64-maccatalyst` and
`x86_64-maccatalyst`, and they had been compiling before it. Clang's driver
enables the blocks extension by default for a Darwin target, and Clang defines
`__BLOCKS__` only while it is enabled, so the Darwin C library then declares six
entry points that take a block pointer — `atexit_b`, `bsearch_b`, `heapsort_b`,
`mergesort_b`, `psort_b` and `qsort_b`, each under `#ifdef __BLOCKS__` in
`any-darwin-any/_stdlib.h`. Aro has no block pointers and stops on every one:
23 errors, `expected ')', found '^'` at `_stdlib.h:298`
(`local://foundation-cross-test-corrected-pcre2-aarch64-macos.log:6-22`).

**Fix.** `-fno-blocks` on the preprocessing line. It describes the translator
rather than the target, so it is on the line for **every** target that reaches
this route, not only the Darwin ones; on every other target Clang leaves blocks
off by default and it changes nothing. Nothing of PCRE2's is lost:
`src/pcre2.h.generic` names no block type anywhere, so what leaves the file is
six declarations of the target's C library that the translator could never
have held — which is exactly where they were before this step existed.

**Bound to.** Clang's default `-fblocks` for Darwin targets and Aro's lack of
block pointers, in this toolchain pair. Any future block-taking declaration in
another target's C library would be the same failure again.

**Status.** `OBSERVED`. All four cells are `build_only` with build exit 0 in the
current sweep, each showing a `translate-c success` sitting directly on a
`preprocess pcre2.h` step
(`local://foundation-cross-test-final-current-pcre2-aarch64-macos.log:16-18`).

---

## 20. `__int128_t` is the compiler's typedef, and no header declares it

**Condition.** Two cells stayed red after entries 17 and 19: `aarch64-netbsd`
and `aarch64_be-netbsd`.

**Symptom.** One error each, and **after** the translation itself had
succeeded. A NetBSD header in the `src/pcre2.h.generic:87-89` chain spells
`__ALIGNBYTES` through `__int128_t` — `generic-netbsd/sys/param.h:290` is
`#define ALIGNBYTES __ALIGNBYTES`, and the value is the target's
`machine/param.h` — `-dD` keeps the spelling, and the translated Zig came out
naming an identifier nothing in it declared:
`pub const __ALIGNBYTES = __helpers.sizeof(__int128_t) - @as(c_int, 1);`,
`use of undeclared identifier '__int128_t'` at `pcre2_preprocessed.zig:1817`
(`local://foundation-cross-test-corrected-pcre2-aarch64-netbsd.log:6-9`, and
the same single error on `aarch64_be-netbsd`).

**Fix.** `translate.h` restates the two typedefs the compiler itself provides,
under the compiler's own capability macro:

```c
#if defined(__SIZEOF_INT128__)
typedef __int128 __int128_t;
typedef unsigned __int128 __uint128_t;
#endif
```

Clang declares these names next to the `__int128` primitive it provides and no
header declares them, so restating them is what carries the declaration into
the file `zig translate-c` reads. The guard is not this fork's guess at a
capability: Clang defines `__SIZEOF_INT128__` exactly when
`TI.hasInt128Type()` holds for the target, so every 32-bit cell leaves it false
and declares neither name, and C permits a typedef to be restated for the type
it already denotes, so a target whose own headers declare them ends on the
same declaration. `x86_64-netbsd` builds without any of this.

**What this is not.** It is not a stub, a copied prototype or a fake feature: no
PCRE2 declaration, constant or prototype was added, and the file remains a
macro prelude, two compiler typedefs and one include.

**Bound to.** Clang's builtin `__int128` typedefs and Aro's treatment of a
typedef restated for a builtin type. A NetBSD header that spelled the constant
itself would not have needed it.

**Status.** `OBSERVED`. Both cells are `build_only` with build exit 0 in the
current sweep.
