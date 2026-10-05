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

**Superseded in part by entry 38.** That result was true of the tree entry 13
measured. The record for `testdata/foundation-fixtures.zig` — the fork's own
fixture module, which this manifest pins on purpose — no longer matches, so the
command now reports 58 `OK` and one failing line. The 58 upstream records still
verify. `.github/workflows/verify.yml` runs the same command first in its native
job, so CI will show the same red line until the digest is re-derived.

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
  the twelve failures. The current cohort — epoch
  `20261004T221720228710Z-45046`, receipt `pcre2-53-target-8.json` — is **20
  runtime PASS, 33 `build_only`, 0 fail**, driver exit 0, `source_unchanged:
  true`, `jobs_honoured: true`. `build_only` is compiled-but-not-run and is
  **never a pass**, so this is 20 runtime passes and 33 compile-only cells, not
  53 passes. The 33 report `runtime_unavailable` on this host, so no BSD,
  Darwin, Windows or WASM binary has been executed here.
* **The 2026-10-04 packaging and licence wave is entirely
  `PENDING-VERIFICATION`.** Entries 21-28 are what it needed to get right, and
  nothing in it has been exercised: no build, test, smoke, cross-target, Nix,
  devenv or consumer command was run by the role that wrote it. The commands
  the driver owes are written out in `README.zig.md` § "Verification status" and
  summarised in `README.md`'s matrix. Two things this wave cannot close by
  itself, both owned by the native-delivery role: `build.zig.zon` `.paths` must
  list the new files, or a fetched copy loses upstream's README and the licence
  material; and the build graph must install the pkg-config metadata, the
  licence records, the `testdata` oracle and the manual, because packaging
  deliberately installs none of them.
* **Entries 29 to 37 are backed by the last green at all three code-unit
  widths, and sources moved after it.** `test` and `smoke` reported
  `24/24 tests passed` and `21/21 steps succeeded` at width 8, 16 and 32, in the
  default optimize mode and the default linkage. **A further round of API
  changes then landed in `zig/**`** — `error.SerializationRefused` with the
  reshaped `OutOfMemory`, the non-optional `enumerateCallouts` callback,
  `substitute` invalidating the captures it leaves behind, and the corrected
  character-tables ownership — so those rows are the most recent evidence, not
  a description of the present bytes. Everything else this wave touched was
  still open when the wave closed: **static linkage**, the other three optimize
  modes, **`install` at width 16 or 32**, the six-target `check`, the 53-platform
  matrix re-run, every Nix output, `devenv`, and the **runtime** route. Two of
  those have since been answered by driver receipts and neither closes the rest:
  the six-target `check` as a compile-only row (`20261005T014547Z-797a73f2`) and
  the 53-platform matrix as **20 runtime PASS, 33 `build_only`**
  (`20261004T221720228710Z-45046`). The runtime row is the one worth repeating:
  the runtime-loaded route has since been exercised — the own-loaded 8-cell wave
  `20261004T232823091897Z-23133` reports **8 pass** — but against **this
  repository's own source-built provider**, on eight cells, and predating the
  applied ordering fix. No *foreign* provider has been, and one would have to be
  a file exporting all three widths, because the translated header declares all
  three. The commands are in
  `README.zig.md` § "Verification status"; nothing above is a plan.
* **The integrity record is red on one line, and the fix is the owner's.**
  `UPSTREAM.sha256` reports 58 `OK` and one failing record,
  `testdata/foundation-fixtures.zig`, because this wave edited that module
  after the digest was taken. **All 58 upstream records verify**, so this is
  not a native-byte finding and **does not complete the native-byte
  criterion**. What is needed is to **re-derive that single digest** — not to
  re-pin an upstream record, not to delete the line, and not to suppress the
  check. Entry 38 has the reasoning; `README.md` and `README.zig.md` state the
  scope wherever the count appears.
* **One applied fix has no gate behind it yet.** The translated-header
  generation now resolves its host/target selection and establishes the
  selected platform configuration **before** it calls `createModule`, at the
  seam `build.zig:1381-1388` reaches through `runtime/graph.zig:294`
  (`createModule`) and `runtime/graph.zig:365-379` (`generateDispatch`). It
  answers an earlier positive-system **case** that reported **28
  undefined-symbol diagnostics from the compiler — one case, 28 diagnostics, not
  28 separate cells**; a red result, not an all-PASS one — and the ordering
  staged before it was itself wrong, so what landed is a replacement and not an
  addition. **Applied; not yet re-gated:** no receipt re-runs pcre2 after it,
  so the cohort above, the compile-only baseline `20261005T014547Z-797a73f2`
  and both 8-cell waves (`20261004T233628757747Z-69351`,
  `20261004T232823091897Z-23133`) all predate it and none of them is evidence
  for it. No native byte, header, test, fixture, licence or upstream file
  changed with it. `CHANGELOG.md` entry 50 says the same thing; the gate states
  live in `README.zig.md` § "Verification status".
* **No independent external provider has been exercised.** The external-route
  wave `20261004T232439Z` (`pcre2-index.json`) records no route carrying
  `counts_as_external_coverage: true`. The only successful route is this
  package's own source-built provider (`independence: own`), and every external
  candidate is an expected refusal — a library that does not export the surface
  this header declares. **That is a boundary, not coverage**, and it is the
  three-width boundary this package's own ABI section already records: an
  installed `libpcre2-8` answers for width 8 only.

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

---

## 21. A fork README that is upstream's README cannot be the fork's entry point

**Condition.** The workspace contract asks a fork's README to open with the
current native-source deviations, then the native-build deviations with a dated
history link, then the build/run/test matrix, then consumption. This fork's
`README.md` was upstream's own README, byte for byte, and answered none of
those four questions. Overwriting it would have destroyed the only copy of
upstream's wording in the tree.

**Symptom.** The repository's front door described PCRE2 in general and said
nothing about this fork's `config.h`, its removed `sljit` dependency, its
disabled JIT, its three code-unit widths or its linkage policy. Every one of
those lived in `UPSTREAM.md`, which a reader arriving at `README.md` has no
reason to open.

**Fix.** Two files with two jobs. `README.md` became fork-authored and follows
the four-part order, including consumption for C against an installed prefix
and for the Nix outputs rather than a Zig-only shell. Upstream's bytes moved,
unchanged, to `README.upstream.md`. The move is recorded as a move and not as
an upstream-file edit: `sha256sum` printed
`579446220c54f9b406a6c7b9b2bf155abf699c6e0b6211c7189f3aa1b174246d` for both
files immediately before it, and the driver's extraction record names the same
digest, this commit and this preserved path. `UPSTREAM.sha256` still does not
hash it, for the reason it never hashed `README.md`: the record covers the
bytes this package compiles, installs, reads as an oracle and publishes terms
for, and widening a 59-record gate to a document changes a count that existing
receipts depend on.

**Bound to.** A fork whose canonical entry point must carry the same
information upstream's own README carries. The byte-identity receipt lives
outside the tree, so a fork with no such record has only its own word for the
preservation.

**Status.** `PENDING-VERIFICATION`. `README.upstream.md` was not touched, and
its digest was read and matched; nothing about the fork-authored `README.md`
has been exercised, and the driver's filtered-package proof — the one that
would show a fetched copy still carries the preserved upstream README — has not
been run.


## 22. A shared library's rpath and soname belong to the build graph

**Condition.** A Nix output for the shared variant, where `pcre2test` is linked
against the `libpcre2-8.so` the same build just produced.

**Symptom.** The installed tool records the library by the path the linker was
given and adds the build directory as its search path. Both name a directory
that is gone once the build finishes, so the tool cannot resolve the library it
was linked against. The tool worked in the build tree, which is why it is easy
to miss.

**Fix, and where.** The fix is an rpath into the installed `lib` directory and a
soname that lets `DT_NEEDED` name the library rather than a path — and that is
build-graph work, because the graph owns the tool's link line and the library's
identity exactly as it owns every other installed path. Packaging does not
patch the binary afterwards: a second writer for one path is how the packaged
artifact and the graph stop agreeing.

**Bound to.** A shared output whose executables link a library produced in the
same build. Where the derivation runs is irrelevant.

**Status.** `PENDING-VERIFICATION`, and routed to the native-delivery role as an
open requirement. Nothing has been observed about which shape Zig's link emits.

## 23. Variants are arguments of one derivation, and the default stays unforced

**Condition.** A standalone package that must offer a static and a shared
variant, a default, and three code-unit widths.

**Symptom.** Written as separate modules, the variants are separate copies of
the same logic, and the copy nobody re-reads is the one that stops matching the
graph. Restating the SDK's linkage policy inside the packaging is the same bug
one level down: a derivation and a build graph then disagree about which kind of
library was produced.

**Fix.** One `package.nix` with `linkage` and `codeUnitWidth` as arguments.
`default` passes no `-Dlinkage` at all, so the SDK's policy runs unforced. The
variants live in the entry points — `packages.<system>.default` / `.static` /
`.shared`, and `outputs.static` / `outputs.shared` in devenv — and the widths are
the same derivation with the argument set.

**Bound to.** Any package whose linkage default is a *policy* rather than a
constant.

**Status.** `PENDING-VERIFICATION`.

## 24. One writer per installed path

**Condition.** A packaging layer next to a build graph, with upstream's own
`libpcre2-*.pc.in` templates carried but unsubstituted.

**Symptom.** Two temptations, both wrong. Writing a `.pc` file in packaging
invents metadata the graph does not produce, and gets it wrong the moment the
default policy rather than the caller chose the linkage. Installing licences and
data twice gives one path two writers, and that disagreement is the silent one.

**Fix.** The build graph installs the artifacts, headers, tools, data, licence
records and pkg-config metadata; packaging names the variant, width, CPU
baseline, optimization mode and prefix and installs nothing of its own. The
templates are the spec the graph writes against: `-DPCRE2_STATIC` for a static
build and `-DPCRE2POSIX_SHARED` on the POSIX wrapper for a shared one
(`CMakeLists.txt:1202-1210`), `Requires.private` on the core for the wrapper, and
an empty `Libs.private` because nothing here requires a thread library.

**Bound to.** A package whose graph can be made to install these. Until it does,
the requirement is unmet and stated as unmet rather than filled in downstream.

**Status.** `PENDING-VERIFICATION`.

## 25. An indented Nix string cannot contain a nested one

**Condition.** A shell block inside `installPhase = ''…''` needs a
platform-conditional fragment, written the obvious way as
`${lib.optionalString stdenv.hostPlatform.isLinux ''…''}`.

**Symptom.** Inside an indented string the sequence `''` is an **escape** —
`''$`, `'''`, or `''` before a newline — not the start of a new string. The
fragment's contents are then reinterpreted as string text or rejected as an
invalid escape, instead of being parsed.

**Fix.** Assemble such fragments in a `let` binding, where `lib.optionalString`
is ordinary Nix, and interpolate the finished block into the shell string.

**Bound to.** Nix indented strings at any depth. A `"…"` string nested inside
`''…''` is fine; only the `''` opener is not.

**Status.** `SOURCE-CONFIRMED` — the string syntax. Nothing here was evaluated,
because this role runs no Nix command.

## 26. A development shell must not contain the thing it is for

**Condition.** A canonical dev environment for an SDK that is itself a package.

**Symptom.** Listing the SDK in the shell's `packages` makes entering the shell
depend on building it, so a developer who came to fix the build waits on the
build. Naming it eagerly in an environment attribute has the same effect: the
value is computed on every shell entry.

**Fix.** Tools in `packages`; the SDK's variants as lazy `outputs`, built on
demand with `devenv build outputs.static`. A package attribute is lazy, so the
shell names the same `package.nix` the flake exposes without instantiating
anything until it is asked.

**Bound to.** Any project whose dev environment is also a package of the
project.

**Status.** `PENDING-VERIFICATION`.

## 27. A committed file names no host path and overrides nothing the caller chose

**Condition.** The workspace requires every Nix and Zig cache on approved local
scratch, and a flake evaluation is pure.

**Symptom.** `builtins.getEnv` in `devenv.nix` bakes this host's layout into a
file every other host reads, and in a pure evaluation it is refused or empty. In
the other direction, an `env` attribute that overwrites a caller's
`ZIG_GLOBAL_CACHE_DIR` is the same mistake in portable clothing, and setting
`TMPDIR` does not move devenv's runtime sockets or its `DEVENV_ROOT` state,
which exist before a shell starts.

**Fix.** Read `HOST_SCRATCH_ROOT` in `enterShell`, in shell code, and fill in a
cache location **only where the caller has not already chosen one**. Nothing is
invented when it is unset.

**Bound to.** A workspace whose scratch policy is an environment variable. A
host without one keeps its own defaults, which is correct rather than a silent
`/tmp`.

**Status.** `PENDING-VERIFICATION`.

## 28. A fork's own files need their own grant, and a withdrawn grant is still a record

**Condition.** An owner authorizes a licence for fork-authored additions, after
an earlier record had withdrawn an offer of the same terms as unsupported.

**Symptom.** Two records then disagree on purpose; deleting either loses
something. And granting fork work the same terms as upstream's tempts a claim
that the grant reaches upstream's files, which it does not.

**Fix.** Keep both, in order, and say which is which. `FORK-LICENSE.md` holds the
grant, the authorization it rests on and the terms; `NOTICE.md` points at it and
states that the earlier record described the state before it; `CHANGELOG.md`
entry 21 stays as history and entry 29 records the replacement. The per-path
split upstream states is carried forward rather than flattened: the library and
`doc/` under the BSD terms, `testdata/` public domain, the JIT under the 2-clause
BSD grant with an empty `deps/sljit`.

**Bound to.** A fork whose additions are genuinely new files.

**Status.** `SOURCE-CONFIRMED` for the facts it records — read out of
`LICENCE.md`, `NOTICE.md` and the empty `deps/sljit`. The authorization is the
owner's statement, recorded as such.

---

## 29. A scratch buffer is not a result, and a pair you invented is not a reading

**Condition.** `pcre2_dfa_match_N` takes two caller buffers: a `wscount`-sized
workspace and a `pcre2_match_data`. It is natural to read the first as the
output because it is the one whose size the caller chooses per subject, and
natural to give the result a field of its own so the API has somewhere to put
it.

**Symptom.** Both readings are wrong, and the second one is worse than the
first because it looks like a fact rather than a guess. The matcher is handed
the match block's own offset vector as its output
(`src/pcre2_dfa_match.c:4062-4063`), and upstream's own substring helpers read
a DFA result back out of that block (`src/pcre2_substring.c:334-341`). The
workspace is filled with the matcher's active and new state blocks
(`:605-606`) and what is left there afterwards is its business. A
`DfaWorkspace.pair` would be a value PCRE2 never wrote, and a caller reading it
would get a plausible-looking number with nothing behind it.

**Fix.** Report the count upstream returned, leave the pairs where the library
put them, and say so in three places — the `dfa` doc comment, the
`DfaWorkspace` doc comment, and the ABI section of `README.zig.md`. Three
consequences have to travel with it: the vector must be sized for **every
simultaneous match** and not one pair per parenthesis, because this matcher has
no groups (`doc/pcre2_dfa_match.3:33-35`, `doc/pcre2.txt:4340-4343`); the pairs
come out longest first (`doc/pcre2.txt:4352-4360`); and a return of **zero** is
its own outcome, not a failure and not an empty one — the vector holds the
longest matches and is readable but incomplete
(`src/pcre2_dfa_match.c:905-911`). `DfaOutcome.truncated` is that answer, and
`MatchData.matched` is true when it is returned.

**Bound to.** Any wrapper over a C entry point that takes both scratch and
output storage. The general rule: **read where the callee wrote, not where the
caller allocated.**

**Status.** `SOURCE-CONFIRMED` for the source facts, `OBSERVED` for the
behaviour — `the DFA matcher finds the longest match and says when it could not
fit them all` runs at all three widths.

---

## 30. A field whose size is a function of the build is a per-width fact, not a constant

**Condition.** A wrapper exposes a table the library laid out. In PCRE2's name
table each entry is a group number followed by the name, and the group number is
`IMM2_SIZE` code units wide.

**Symptom.** `IMM2_SIZE` is **two** code units at width 8, where `GET2` is a
big-endian pair, and **one** at width 16 and 32
(`src/pcre2_intmodedep.h:212-221`). Upstream reaches the name by adding
`IMM2_SIZE` to a **code-unit** pointer
(`src/pcre2_compile_cgroup.c:142-144`, `:167-175`;
`src/pcre2_substring.c:498-518`), and writes the name one name character per
code unit of this width. A wrapper that hard-codes "two bytes, then the name"
is correct at width 8 and lands **inside a code unit** at width 16 or 32, which
does not fail loudly — it names a different group every time.

**Fix.** Derive the offset from the compiled width rather than restating it, and
say the number as well so a reader can check it: two big-endian code units at
width 8, one at width 16 and 32. The same rule applies to every slice in the
table: `Name.name` is `[]const code_unit`, not `[]const u8`, because upstream
copies `CU2BYTES(length)` code units. Entries are sized to the **longest** name
in the pattern plus `IMM2_SIZE` plus one
(`src/pcre2_compile.c:5713-5716`) and NUL-padded to that size, so a name ends
at its own NUL and not at the end of the entry — which is the only reason a
name shorter than the longest is readable at all.

**Bound to.** Any table laid out by the library in its own code units. The
general rule: **an offset into library-written memory is measured in the same
units the library used.**

**Status.** `OBSERVED` — `the name table is walked in name order, and an entry
ends at its own NUL` runs at all three widths.

---

## 31. Four blocks, four frees, and one of them is freed from its own array

**Condition.** A wrapper hands back library-allocated memory in four different
shapes: a single copied substring, a list of them, a converted pattern, a
serialized block.

**Symptom.** Each block carries a **hidden header naming the allocator that
produced it**, so `free`, `pcre2_code_free` and a Zig allocator are all wrong,
and each has exactly one correct release: `pcre2_substring_free_N`,
`pcre2_substring_list_free_N`, `pcre2_converted_pattern_free_N`,
`pcre2_serialize_free`. The list is the sharpest: `pcre2_substring_list_free_N`
frees the block **from the array of pointers** (`src/pcre2_substring.c:451-459`),
so the address to hand it is that array and not the first string inside it.
Two length facts travel with them and are equally easy to get wrong:
`Converted`'s slice **excludes** the terminating NUL, because
`pcre2_pattern_convert_N` writes the NUL and then answers `out.output_size - 1`
(`src/pcre2_convert.c:381-382`, `:1080`, `:1092`); and `MatchData.copy`'s buffer
needs `size + 1`, because PCRE2 writes a terminating NUL after the last code
unit (`src/pcre2_substring.c:117-130`, `:127`).

**Fix.** Give each one a `deinit` that calls its own `*_free` and clears the
handle, so a second call is the same no-op rather than a second free, and
document the release next to the type. Never hand the caller's `free` one of
these blocks, and never index into one to find its header.

**Bound to.** A library that allocates on the caller's behalf. The general
rule: **a pointer and a length is what comes back, and one named function is
what gives it back.**

**Status.** `OBSERVED` — `every capture of an attempt comes back as one list the
caller owns` and `a capture is copied out of the block, and the caller says
where the copy lands` run at all three widths.

---

## 32. "Did not participate" has more than one marker, and none of them is zero

**Condition.** One library, two surfaces. The core's offset vector and the
POSIX `regmatch_t` array both answer the same question.

**Symptom.** They answer it differently. The core leaves `PCRE2_UNSET`, which is
`SIZE_MAX` (`src/pcre2.h.generic:539`). The POSIX wrapper writes the literal
**`-1`** into both ends of a `regmatch_t` and into **every slot past the ones
the match filled** (`src/pcre2posix.c:403-408`). `-1` is not `PCRE2_UNSET`
narrowed, so a POSIX capture compared against the core surface's marker never
matches — and because the wrapper also fills the tail, a `regmatch_t` array
shorter than the pattern's capture count is a smaller answer rather than an
overrun, which is a fact worth stating rather than discovering.

The same shape appears in the wrapper's error table: `REG_BADPAT` is the
**fallback** for a compile-error index not in either of its two tables
(`src/pcre2posix.c:312-319`), so `a(b` is `REG_EPAREN`, not `REG_BADPAT`. And
`REG_NOSUB` is remembered in the compiled block, which is why
`matched_without_reporting` is decided from the compiled flags and not from
`exec`'s own argument (`:368-372`).

**Fix.** Publish the wrapper's own `unset` as its own constant, type it
`c_int` so it exists even in a translation with no `regoff_t`, and never let a
caller's natural reach for `pcre2.unset` stand in for it. Match codes; do not
infer the kind of wrong from a code's value.

**Bound to.** Any wrapper that re-presents another library's result type.

**Status.** `OBSERVED` — the POSIX test runs at width 8 and asserts the codes,
the unset marker and the `REG_EPAREN` mapping.

---

## 33. A callback's return is a sign, not a boolean

**Condition.** `pcre2_set_callout_N`'s callback returns an `int`, and the
matcher branches on it.

**Symptom.** "Zero means continue, non-zero means stop reading it as a flag"
is only half the rule, and the wrong half reads as "non-zero means keep going"
(`src/pcre2_match.c:5989-5994`). **Zero** carries on from just after the
callout. A **positive** answer is `MATCH_NOMATCH` for this start position, so
the matcher keeps bumping along and reports `PCRE2_ERROR_NOMATCH` unless a later
position matches. A **negative** answer abandons the whole attempt with that
number as `pcre2_match_N`'s return. Three outcomes, one signed integer.

**Fix.** Document the sign, and keep the sample returning zero with the reason
next to it. Two lifetime rules ride along: the callback and its `data` are
**not copied** into the context — PCRE2 holds the two pointers — so both outlive
every attempt made through it; and a callout and the three ceilings share one
context, so installing one and then borrowing the context elsewhere is the
caller's ordering to get right.

**Bound to.** Any callback whose return upstream reads by sign.

**Status.** `OBSERVED` — the callout test returns zero and asserts that the
block which reached the matcher was this pattern's own and pointed at this
caller's subject.

---

## 34. A NULL that means "this build cannot" is not an allocation failure

**Condition.** JIT is disabled because `deps/sljit` is an empty submodule and
`SUPPORT_JIT` is 0, so every JIT entry point compiles its
`#ifndef SUPPORT_JIT` fallback. One of them answers NULL.

**Symptom.** `pcre2_jit_stack_create_N` returns NULL for "no SLJIT here"
(`src/pcre2_jit_misc_inc.h:125-134`) and for "the allocation failed", and the
caller cannot tell them apart from the value alone. The tempting repair is a
substitute — fall back to the interpreter and report a match as though JIT had
run.

**Fix.** Name it for what was seen: `error.JitUnsupported`, alongside
`OutOfMemory`, because only the caller's knowledge of the configuration tells
the two apart and this package says which one it saw. The compile side is a
**value**, not an error, for the opposite reason: `pcre2_jit_compile_N`
answering -45 is exactly what a caller that *does* have JIT would not get, so
the tag has to survive. **No fallback interpreter wearing JIT's name**: the
interpreter is what runs a match, and it is reached through `Regex.match`.

**Bound to.** A build with a feature compiled out, where the symbols still
link. The general rule: **"disabled" and "absent" are two different claims, and
neither is a third one that pretends to be the feature.**

**Status.** `OBSERVED` at all three widths.

---

## 35. A numeric range belongs to one width, and inheriting it is not inheriting the condition

**Condition.** A wrapper classifies `pcre2_match_N`'s negative returns into a
closed set of tags, and one of the tags is "the subject is not valid UTF".

**Symptom.** The range that gets mapped was the one that holds at width 8:
`-3…-23` and `-36`. Those are `PCRE2_ERROR_UTF8_ERR1`…`_ERR21` plus
`PCRE2_ERROR_BADUTFOFFSET`. At width 16 the validity codes are **-24…-26** and
at width 32 **-27…-28** (`src/pcre2.h.generic:355-400`). The same condition
therefore arrived with the right number and the **wrong tag** — `.failed`
instead of `.invalid_utf` — which is exactly the failure a caller cannot detect
from the number, because they branch on the tag.

**Fix.** Widen the mapped range to `-28…-3` and `-36`, and record why one range
spans three widths: the codes are width-specific and the *condition* is not.
The repair is in the return mapping, **not** in a fixture. The test that caught
it stays and still asserts the category and the state transition; the
tautological fixture arithmetic and the non-empty-diagnostic assertions beside
it were removed, not relaxed.

**Bound to.** A header whose numeric constants vary per build configuration.
The general rule: **a range copied from one configuration's reading of a header
is a claim about that configuration.**

**Status.** `OBSERVED`. The two wide runs that reported `23 pass, 1 fail (24
total)` are superseded by runs reporting `21/21 steps succeeded; 24/24 tests
passed` at both widths.

---

## 36. "This configuration is refused" is a claim about the graph, and the graph moves

**Condition.** A build graph refuses a configuration — here, the 16- and 32-bit
widths — and the documentation says so in several places at once.

**Symptom.** The graph stops refusing: `zig/root.zig` begins resolving its
surface from the compiled width, so `test`, `smoke` and `check` run at every
width. Every sentence that said otherwise is now false, and they are false in
the places a reader trusts most — the import section, the build modes, the ABI
boundaries, and the sample program, which passed `[]const u8` where a
code-unit slice is required and so could not compile at the widths it claimed
to describe.

**Fix.** State the width facts once and make them true everywhere: the artifact
carries all three closures whatever `-Dcode-unit-width` names, the **facade** is
the selected width's own, and what a width changes is the name the artifact is
installed under and which non-core tools exist. Make the sample widen its
text, so it compiles at all three widths. Write offsets as **code-unit**
offsets throughout, because at width 8 they coincide with bytes and that
coincidence is what let the 8-bit reading spread.

**Bound to.** A document that describes a graph rather than a fixed artifact.

**Status.** `OBSERVED` for the three widths; the runtime route, the static
linkage, the other optimize modes, the 16- and 32-bit **install**, the
six-target `check`, the 53-platform matrix, the Nix outputs and `devenv` all
remain without a receipt, and the gate table says so.

---

## 37. "Documented" is a state, and it is not the same state as "read"

**Condition.** Four documents are written against a facade that wraps more than
compile and match, and the parts that were not written down are the parts a
caller gets wrong.

**Symptom.** The gap is invisible from inside the work. The DFA matcher's
result location, the four library-allocated blocks and their four frees, the
POSIX wrapper's own unset marker, the callout's sign, JIT's two refusal shapes
and the converted pattern's excluded NUL were all in the code and in none of the
documents. A census of symbols would not have found any of it: every declaration
was present, every symbol resolved, and every sentence already written was true.

**Fix.** Document from the **sources**, not from the previous draft: read
`pcre2_dfa_match.c`, `pcre2_convert.c`, `pcre2_context.c`, `pcre2posix.c` and
`pcre2_match.c` for the behaviour each table row claims, and let a row that
cannot be sourced be left out rather than softened. Then make the count honest:
the error set has thirteen members, not seven, and the suite has 24 tests.

**Bound to.** Any document whose subject is a wrapper rather than a fixed
artifact.

**Status.** `OBSERVED` for the behaviour each entry records. The documents
themselves are covered by the driver-owned filtered-package proof, which runs
after they settle — a package identity is a digest over what the package ships,
and these documents are part of what it ships.

---

## 38. A manifest that pins a fork file fails when the fork file changes, and that is the job

**Condition.** A byte-integrity record pins what upstream shipped. This one
also pins **one file the fork wrote**: `testdata/foundation-fixtures.zig`, the
module holding every expected answer the tests compare against. The manifest's
own header says so and gives the reason (`UPSTREAM.sha256:27-31`) — a silent
edit to the oracle would move it rather than break a build, so hashing it makes
such an edit fail loudly.

**Symptom.** The wave that fixed the oracle edited the oracle, and the record
went red on the one line that is not upstream's. The result reads like a
native-byte finding and is not one: 59 records, **58 matching, one not**, and
the 58 are every upstream byte this package compiles, installs, reads as an
oracle or publishes terms for. The pressure that follows is the real risk — a
red line invites the fastest way to green, and the fastest ways here are all
wrong.

**Fix.** Re-derive that one digest, and change nothing else. Not re-pin an
upstream record; not delete the failing line; not move the file out of the
record, which would drop exactly the protection that was added; not suppress
the check. A red record for a fork-owned file is **information**, and silencing
it discards the reason the record existed. Then say the scope out loud wherever
the count appears, because "59 records" and "59 upstream files" are different
claims and only the second one bears on whether upstream bytes are intact.

**Bound to.** Any integrity record that mixes upstream bytes with fork-owned
files. The general rule: **when a manifest's own header declares an exception,
the exception is part of the contract — read a red line against the header, not
against the filename.**

**Status.** `OBSERVED`, and red. The manifest was written 2026-10-02 and the
fixture module was modified 2026-10-04; that is the whole difference. **This does
not complete the native-byte criterion** — it bounds what the red line is about.
The full filtered-package replay is driver-owned.

---

## 39. One struct field means two things to two entry points, and the second one reads it as a count

**Condition.** A `pcre2_match_data` is a block a caller owns, and it carries
both an offset vector and a field `rc`. `pcre2_match_N` leaves `rc` holding
the pair count. `pcre2_substitute_N` matches **into the same block**
(`src/pcre2_substitute.c:984`) and leaves `rc` holding the **number of
substitutions it made** (`:1762`, `:1768`).

**Symptom.** Every native substring entry point reads `rc` as a pair count —
`pcre2_substring_length_bynumber_N` and `_list_get_N` among them
(`src/pcre2_substring.c:317`, `:390`). So after a substitution the block says it
holds five pairs and the vector beside it holds two, and both failures are
silent. `group()` resolved offsets computed against the substitution's subject
against whatever subject the caller had matched before, which is an
out-of-bounds read the moment that subject was shorter; `list()` walked five
entries out of a two-entry vector. Neither is a crash on the first call, so a
test that only checks "the substitution happened" never sees either.

**Fix.** Move the block into the "nothing readable" state **before** the call —
whichever way the attempt ends — and report the substitution count as a return
value rather than leaving it in the block. `SubstituteOptions.matched` is the
one case where the block is left alone, and the reason is in upstream, not
here: it copies the caller's block into one of its own, matches into that and
frees it (`src/pcre2_substitute.c:898-917`, `:1767`).

**Bound to.** Any wrapper over a C API whose result block has fields more than
one entry point writes. The general rule: **before handing a caller-owned result
block to a different entry point, ask what that entry point leaves in it.**

---

## 40. "Keeps the pointer" and "copies the bytes" look identical from the call site

**Condition.** A context setter takes a pointer to caller-owned tables, and the
compiled block is supposed to be self-contained afterwards.

**Symptom.** It is not. `pcre2_set_character_tables_N` stores the address as it
was given (`src/pcre2_context.c:326-329`); `pcre2_compile_N` stores **that same
pointer** in the block it builds (`src/pcre2_compile.c:10451`, `:10960`) with no
`PCRE2_DEREF_TABLES` flag; and `pcre2_code_free` does not free it
(`:1146`). A wrapper that documents "PCRE2 copies them into the compiled block,
so this is yours to release afterwards" sends a caller down a use-after-free
that fails at **match** time, not at compile time — the worst moment to find
out, and the one place the fault will not point back at the real mistake.

**Fix.** Read the three sites rather than the setter's name, and document the
true lifetime: the caller's 256 bytes must stay alive for as long as every
pattern compiled through that context, and nothing in the library releases
them. The related trap rides along — `PCRE2_ERROR_MIXEDTABLES` compares these
**pointers**, not the table contents (`src/pcre2_serialize.c:99-102`), so two
blocks built from two identical tables at two different addresses are refused.

**Bound to.** Any API that accepts caller-owned memory by pointer. The general
rule: **a setter whose name does not say "copy" does not copy.**

---

## 41. An optional callback parameter is a promise the callee never made

**Condition.** A wrapper types a callback parameter as `?*const fn`, which
reads as "null is allowed".

**Symptom.** `pcre2_callout_enumerate_N` calls the function for every
`OP_CALLOUT` and `OP_CALLOUT_STR` it walks and **never tests it for null**
(`src/pcre2_pattern_info.c:405`, `:418`). So the optional is not a permitted
value; it is a crash waiting for a pattern that has a callout. The type is
saying something upstream does not.

**Fix.** Type it as the plain `*const fn` it is, exported as
`pcre2.CalloutEnumerate`. A caller that wants "are there any" counts with its
own state, which is the answer the optional never actually gave them.

**Bound to.** Any wrapper over a C callback parameter. The general rule: **make
the optional exactly as wide as the callee's own null checks.**

---

## 42. A cross-check cell inherited the host build's linkage, and one target cannot carry it at all

**Condition.** `zig build check` configures six targets from one host. The main
build resolved `-Dlinkage`'s default from its own `target.result`, and the
cross-check function received that *resolved value* as a parameter and handed it
to every cell.

**Symptom.** Two of the six cells were handed an answer they never asked for,
and both failed in a way that looked like a source defect rather than a
configuration one. `wasm32-wasi` has no dynamic linker, so the shared artifact it
was told to build could not exist: the link died with **18**
`relocation R_WASM_MEMORY_ADDR_LEB cannot be used against symbol ...; recompile
with -fPIC` errors against `crt1-command.o` and `libzigc.a`
(`OBSERVED`,
`local://foundation-contract-pcre2-current-cross-target-check.log:19-37`).
`x86_64-windows-gnu` inherited `.dynamic` too, which reached the separate
Windows problem in entry 43.

**Fix.** Hand the cells the **option**, not the value: `defaultLinkage` resolves
the default from each cell's own `target.result`, and an explicit `-Dlinkage`
still reaches every cell unchanged. `linkageSupported` and
`unsupportedSharedMessage` then apply one rule to a cell that was *asked* for
shared and cannot have it: the cell becomes a named failing step rather than a
build attempt that cannot succeed or a target quietly dropped from the matrix.
`wasm32-wasi` therefore compiles a static archive by default, and
`-Dlinkage=dynamic` reaches it as an explicit, attributed refusal.

**Bound to.** Zig 0.16.0 and any build graph that resolves a per-target default
once and hands the answer to a second target. The general rule: **a value
derived from a target is re-derived for every target it is handed to.** A value
named on a command line is not re-derived — that is the difference between a
default and an instruction.

**Status.** `PENDING-VERIFICATION`. No build, check or linker was run here: the
role that wrote this runs no gates. The receipt above is the failure being
corrected, not a result of the correction.

---

## 43. `dllimport` for a symbol the same DLL defines is an import from yourself

**Condition.** This fork compiles `src/pcre2posix.c` **into** the core artifact
as well as into upstream's separate `pcre2-posix`, so one file a `load` names
answers for the width library and the POSIX names. On COFF that makes every core
entry point the wrapper calls a **local definition**.

**Symptom.** A shared `x86_64-windows-gnu` build failed with seven LNK4217
`locally defined symbol imported` lines, all of them `pcre2posix.obj` importing
`pcre2_compile_8`, `pcre2_match_8`, `pcre2_code_free_8`, `pcre2_pattern_info_8`,
`pcre2_match_data_create_8`, `pcre2_match_data_free_8` and
`pcre2_get_ovector_pointer_8` from the very DLL that defines them (`OBSERVED`,
`local://foundation-contract-pcre2-current-cross-target-check.log:3-11`).

The cause is one header rule meeting one file layout. `pcre2.h` chooses
`extern __declspec(dllimport)` when `_WIN32` is defined and `PCRE2_STATIC` is not
(`src/pcre2.h.generic:56-63`), and a shared core defines neither. The core's own
sources never see that, because they include `pcre2_internal.h`, which overrides
the same macro to `dllexport` before it includes `pcre2.h`
(`src/pcre2_internal.h:154-160`, `:173`). `pcre2posix.c` includes `pcre2.h`
(`:112`) and deliberately not `pcre2_internal.h` (`:49-52`), and the one file it
does include from that family skips it too under `PCRE2_PCRE2POSIX`
(`src/pcre2_tables.c:50-52`), so nothing in that translation unit ever overrode
the header. Upstream is unaffected because there the wrapper is a *separate*
DLL and the import is real.

**Fix.** Define `PCRE2_EXP_DECL=extern` on that one compile line — upstream's own
override, which `pcre2.h` explicitly leaves alone when it is already defined
(`src/pcre2.h.generic:51-52`) — and only there: on COFF only, where one file is
one object, and in the shared case only, because a static core already gets
`extern` from `PCRE2_STATIC`. Defining it on a shared module instead would strip
the export off every core entry point, since that is what the core's own sources
mean by it. The separate `pcre2-posix` artifact keeps the header's `dllimport`,
which is the correct decoration for it and what upstream's CMake does
(`CMakeLists.txt:1011-1013`). No diagnostic is suppressed and no native byte is
edited.

**Bound to.** COFF shared builds, and any library that compiles one upstream
source into more than one artifact. The general rule: **a translation unit's
decoration is a property of the artifact it is being compiled into, not of the
source file.** The same file in two artifacts can need two different answers, and
the header cannot know which one it is in.

**Status.** `PENDING-VERIFICATION`. No build ran here. The receipt above is the
failure being corrected.

## 44. The published module's search path must be the one a *dependent* needs

**Condition.** A Zig package publishes a module that a dependent imports into its
own executable. When the library is shared and the dependent's executable is
built out of a build cache — which is where `Module.linkLibrary` recorded that the
shared object was really emitted — the install tree's `$ORIGIN/../lib` resolves
nothing.

**Symptom.** `cd consumer && zig build run -Druntime=false -Dlinkage=dynamic`
exited **0**, `Build Summary: 17/17 steps succeeded`, and every hand-worked
capture offset was still correct. The loader printed
`/lib64/libpcre2-8.so.0: no version information available` and the program
answered `linked against 10.45 2025-02-05` — the host's installed PCRE2, not this
build's 10.49 (`OBSERVED`,
`local://foundation-resumed-pcre2-standalone-linked-dynamic.json`). The static
row of the same pair resolved correctly
(`local://foundation-resumed-pcre2-standalone-linked-static.json`), so nothing
about the library or the consumer was wrong; only the resolution was.

**Why it is invisible from the inside.** A green `test`, `smoke` and
`RunTest` here all run out of the build cache, and each of those programs was
compiled from a **second, private** facade carrying the build-cache entry. The
package's own gates therefore exercised the private answer while the *published*
one — the only answer any dependent can reach — carried `$ORIGIN/../lib`. Two
facades, one policy, and the one the package tests is not the one it ships.

**Fix.** The published module is the build-cache flavour; the private cache
facade is deleted and `test`/`smoke` import the published module directly.
Nothing installed is built from that module — every installed program here is a C
translation unit with a module of its own, compiled with `.install_tree` — so
the installed and Nix routes still carry `$ORIGIN/../lib` alone. This is the
arrangement `gmp`, `htscodecs`, `inchi` and `luajit` already use; this package
had it backwards.

**Bound to.** Any published Zig module in a shared build whose consumers build
their own executables. The general rule: **the entry a package publishes must
be the entry the largest uncontrolled set of its consumers needs**, which is
almost never the one the package's own installed programs need. A package that
needs the other answer builds that program from its own module rather than
publishing it.

**Status.** `PENDING-VERIFICATION`. No build, test or run happened here. The two
receipts above are the failure, not a result.

## 45. A return value read backwards, and a bound the caller was assumed to hold

**Condition.** Two entry points in `zig/widthed.zig`, neither with a caller
inside this repository, so the package's own gates could not see either.

**Symptom 1.** `pcre2_next_match_N` answers `TRUE` for "attempt again" and
`FALSE` at the end of the subject, and never a negative
(`src/pcre2_match_next.c:96-169`; `doc/pcre2.txt:3433-3439`).
`MatchData.next` mapped 0 to `true`, an unreachable -1 to `false` and 1 to
`error.SubstringUnavailable`, so the two answers were swapped: a resumed loop was
refused on its first step and told to continue at the end. Observed from an
independent consumer outside this repository (`OBSERVED`, parent run): the first
resume answered `error.SubstringUnavailable`.

**Symptom 2.** `pcre2_serialize_decode_N` writes one `pcre2_code *` per block it
decodes and cannot see the length of the caller's array
(`src/pcre2_serialize.c:204`, `:243`), so a one-slot destination asked to hold
three blocks was written two pointers past its end. Observed from the same
consumer with two canary words immediately after the destination: both were
overwritten (`OBSERVED`, parent run, `DestinationOverrun`).

**Why nothing here caught either.** `MatchData.next` had no caller at all, so a
green suite proved only that its body compiles. `Regex.decode` had two callers
and both happened to pass `count` equal to the destination's length, so the
missing comparison was never exercised. The asymmetry is the lesson: an entry
point with no caller is untested by definition, and an entry point whose callers
all agree with it is tested only for the case they agree on.

**Fix.** `next(self, start_offset: *usize, options: *u32) bool` — the two
out-parameters upstream actually writes (`src/pcre2.h.generic:775`) and the
upstream polarity, with no error arm because no error is reachable. `decode`
compares `count` against `all.len` before anything runs and answers
`error.OvectorTooSmall`, the name `serialize` already used for the same fact
about a caller's array; the `error.NoSuchGroup` that stood in its place named a
group-number condition and described nothing about a block-pointer array.
`Raw.next_match`'s parameters in `zig/raw.zig` were renamed from `ovector` and
`oveccount`, which were never its parameters — `ovector` is a local at
`src/pcre2_match_next.c:102` — with types and dispatch untouched. No alias and no
second spelling anywhere.

**Bound to.** Any wrapper whose upstream function cannot fail, where this file
adds an error arm because the return was assumed to be a code: the arm is
unreachable and the polarity is the thing that matters. And any wrapper taking a
caller-owned output array beside a caller-supplied count: the count is a *request*
and the array is a *capacity*, upstream will clamp the first and never see the
second, so the wrapper owns the comparison — the same rule `serialize` already
followed for its scratch array.

**A third bound, on which allocator a decoded block answers to — and how this note
got it wrong first.** `decode` answers the first block as a `Regex` and the rest as
bare pointers, and the split invites "one is the facade's, two are the caller's, so
the caller's `general` governs all three". That reading happens to be correct, but
the first draft of this note reached it by the wrong road: it claimed
`pcre2_serialize_decode_N` copies the serialized header over the new block's own
memctl (`src/pcre2_serialize.c:225-228`), and therefore that the pair behind the
bytes is the pair that frees them. The copy starts one `pcre2_memctl` past **both**
ends — it carries everything except the allocator — so it preserves the *new*
allocator and discards the serialized one, which is what the two comments above it
say (`:215` "The allocator provided by gcontext replaces the original one", `:225`
"The new allocator must be preserved"). A reader who has only seen the tail of a
long copy can splice those lines into a claim that reads well and is not.

The contract is: a decoded block is allocated through the `general` handed to
`decode` (`:215-218`), and `pcre2_code_free_N` releases the block, and its shared
tables, through that block's own memctl (`src/pcre2_compile.c:1212-1227`). So the
decode regression passes this file's counting allocator pair to `decode`, and it
releases all three exactly once — the `Regex` through `deinit`, the other two
through `pcre2.c.pcre2_code_free_N` selected at compile time from
`pcre2.compiled_width`. The pair is asked about each of the three addresses
before any of them is released, and all three must be among the blocks it handed
out. That order matters: `allocations` is already positive from the general
context, the compile context and the character tables, so a conservation check
alone is satisfied by a decoder that quietly used upstream's default allocator
for every block and merely released it correctly. Conservation then follows — every
block handed out came back, none came back that was never handed out, none was
handed out that could not be tracked — and how many blocks a decode makes is not
pinned, because that is upstream's business and not a property a caller can rely
on.

**And this one is bound to reading an upstream contract from a spliced view of its
own source.** Two line ranges printed side by side with a gap between them will
happily produce an argument, and the gap is exactly where the `memcpy` offsets live.

**Status.** `PENDING-VERIFICATION`. No build, test or run was executed by the role
that wrote these files; the two observations above are the parent's, on the
disposable consumer. The first compile that has since looked at `tests.zig`
rejected the iteration test at `span.start`, which had read capture offsets off
`MatchData.group(0)` — that answers the captured code units, not a range.
`MatchData.groupRange(0)` is the accessor for the offsets, and the test now reads
them there, with `group(0)` left checking the captured text. The tempting repair
was the wrong one: reshaping the facade so a test that had guessed wrong would
compile. The published shape was right and the test was wrong, and neither
correction has been executed since.

## 46. A relative path in a generated entry is a claim about the caller's directory

**Condition.** A development environment whose entries are not run by a person
standing in the repository: a driver evaluates them through
`--from path:<sdk>` from a scratch project directory beside the SDK, and a CI
runner may do the same from anywhere at all. The entries are generated shell
programs, not functions, so they have no working directory of their own to
inherit — they have the caller's.

**Symptom.** `sdk.integrity` answered `sha256sum: UPSTREAM.sha256: No such file
or directory` and `sdk.consumer` answered `cd: consumer: No such file or
directory` then `error: no build.zig file found, in the current directory or any
parent directories`, both prefixed `/nix/store/…-sdk-<name>:` — the prefix is
the diagnosis. Those lines ran; they ran in a directory that has neither
`UPSTREAM.sha256` nor `consumer/`. `DEVENV_ROOT` in that run is the project
directory, not the SDK, and the project directory holds `.devenv/` and
`devenv.lock` and nothing else. **Observed** in the driver's canonical
environment run of `2026-10-04T175328Z`; the entry bodies were
`sha256sum -c UPSTREAM.sha256` and `cd consumer && zig build run`, both correct
in a directory they did not establish for themselves.

**Fix, three parts, and each one is load-bearing.** (1) Every entry names the
SDK's own directory before it does anything: `./.` in an expression is relative
to the file containing it, so this is true of the entry rather than of whoever
ran it. (2) It is rendered `builtins.toString ./.` and quoted with
`lib.escapeShellArg`. `builtins.toString` because a bare `${./.}` interpolates a
**path**, which asks Nix for that path's store copy — a read-only copy of the
whole working tree, obtained by copying the tree to get the directory you were
already in. `escapeShellArg` because the rendered string is shell text now, and
the one convention that quotes it correctly is the library's. (3) A second
directory the entries need — `consumer/` — is named the same way rather than
reached by a second relative `cd`, so there is one place that knows what "this
repository" means.

**And the prefix leaves the repository.** A `zig build` entry that delivers an
install prefix is writing a *delivery tree*, and `zig-out` beside the build root
is a delivery tree inside a source repository — which on a volume mount is also
the slowest place on the host to write one. `--prefix` now points beneath
`ZIG_LOCAL_CACHE_DIR`, the cache `enterShell` already exports from
`HOST_SCRATCH_ROOT` when the caller has not chosen one and leaves alone when the
caller has. `${ZIG_LOCAL_CACHE_DIR:?}` and not a default: the honest failure for
"there is no approved place to write" is the shell naming the variable, and any
substitute would be a fallback invented by a committed file to paper over a
caller's environment. Entries that run steps which install nothing name no
prefix — in this build graph `test`, `smoke` and `check` do not install, and the
consumer installs no file at all (`consumer/build.zig:145-149`).

**Bound to.** Any devenv/Nix task or script body that names a repository-relative
path, evaluated from a directory the module did not choose. Two narrower bounds
worth keeping apart:

* A per-entry `cwd` option covers **tasks** only. devenv materialises scripts as
  generated shell programs too, and those inherit the caller's directory, so a
  cwd that fixed the task half leaves the script half failing. The directory
  belongs in the body, which both halves share.
* `${./.}` and `builtins.toString ./.` are not the same value. The first
  interpolates a path and copies the SDK into the read-only store to do it; the
  second renders the directory you were already in. Both satisfy a checker that
  only needs `UPSTREAM.sha256` to be readable, which is exactly why the wrong
  one can pass a gate and still be wrong.

**Bound to the name rule, which is a different rule.** These seven entries are
devenv **scripts** and keep their dotted spelling. `namespace:name` is
devenv's rule for **task** names: in the same wave a `sdk.build` *task* was
rejected with `Invalid task name: sdk.build` while every dotted *script* here
was catalogued and executed. Renaming a script to satisfy a rule about tasks
would have broken the catalogue that had just proved the names were fine.

**Status: `PENDING-VERIFICATION`.** The two failures above are the driver's
observed receipts for the bytes that were in `devenv.nix` before this change. No
Nix, devenv, build, test or smoke command was run by the role that wrote it, so
nothing here claims an entry passes now.

## 47. Two interpolations on one Nix source line are one shell line

**Condition.** An entry assembled from named fragments rather than written out:
`${inSdk}` to establish the directory, `${requireExternalCache}` to settle the
build cache, then the command. Each fragment is its own Nix indented string,
each is correct as a value, and each is alone on its own line in its own
definition — so reading the definitions tells you nothing about how they compose.

**Symptom.** `sdk.consumer` exited **2** with
``syntax error near unexpected token `then'`` on line 1 of
`/nix/store/…-sdk.consumer-script`, which the shell then echoed:

    cd …/pcre2/consumer || exit 1if [ -z "${ZIG_LOCAL_CACHE_DIR:-}" ] || [ -z "${ZIG_GLOBAL_CACHE_DIR:-}" ]; then

The `1if` is the whole diagnosis — `exit` was handed the argument `1if`.
**Observed** in the canonical environment run of `2026-10-04T212645Z`, whose
other seven gates passed.

**Why the source reads as correct.** An indented string is line-oriented and an
interpolation splices its text into the line it is written on, contributing no
separator. `''` drops the newline that immediately follows it and the common
indentation is stripped from what remains, so a fragment defined as

    requireExternalCache = ''
      if [ -z … ]; then

has the value `if [ -z … ]; then\n…`: it **begins with a character**. That is
right for a command fragment and wrong for a line fragment, and the two are
indistinguishable at the definition. On one source line,
`${inSdk}${requireExternalCache}` is one shell line in which `exit 1` and `if`
share a word boundary, and `|| exit 1if [ … ]; then` is not shell in any
dialect. The error names a store path, not the `.nix` line that produced it.

**Fix.** One interpolation per source line, at all six sites
(`devenv.nix:139-140`, `:162-163`, `:174-175`, `:183-184`, `:192-193`,
`:212-213`), which is the only change to the file. The alternatives were worse:
a `\n` inside one fragment trades a syntax error for a script whose line
structure depends on a hand-inserted invisible character, and a space between
the interpolations produces `exit 1 if [ … ]; then`, which *runs* — the
preamble becomes a separate command that never executes because the first one
already exited.

**Bound to.**

* **It fails at run time, never at evaluation time.** The store path evaluated,
  the shell was configured, the tasks ran, and the defect surfaced as `/bin/sh`
  on line 1 of a generated program. Nothing that stops at evaluation or
  cataloguing can see it.
* **A gate that only catalogues cannot see it.** `devenv info` and
  `devenv tasks list` read the names and the sections, and both passed in the
  run where `sdk.consumer` failed, because the defect is in the *text* of a
  wrapper. Only a gate that executes a wrapper under `--from path:<sdk>` finds
  it — which is the same route entry 46 exists for, for a different reason.
* **Entry 46's `|| exit 1` is what made the failure legible.** Without it the
  bad fragment would still have run, but as part of a body continuing in the
  caller's directory; the one-line syntax error at least said which generated
  program was wrong.
* **`sdk.integrity` was never at risk**, because it runs `sha256sum` and has no
  preamble (`devenv.nix:204-205`). A fragment is only exposed to this when
  something is composed after it.

**Status: `observed`.** Before: `2026-10-04T212645Z`, `sdk.consumer` exit 2.
After: `2026-10-04T214134Z`, a devenv-only run — `gates_not_run: ["nix:build"]`,
so no Nix output was built — with eight of eight gates pass and
`gates_failed: []`; `pcre2-devenv-consumer.log` answers `run success` and
`Build Summary: 18/18 steps succeeded`, and `pcre2-devenv-shell-zig-version.log`
answers `0.16.0`. The bytes that run evaluated are the bytes on disk: the run
recorded `devenv.nix` identical before and after itself, and that is what ties
this note to those eight gates rather than to a file that changed afterwards.
