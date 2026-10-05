# pcre2 — Perl-compatible regular expressions in Zig, over upstream's C

This package compiles **PCRE2Project/pcre2 at tag `pcre2-10.49`, commit
`6f9d7c1373262c541324a16a358785b33ef116cf`** — upstream's own C sources, byte
for byte, from the `src/` directory in this repository — into a C library,
translates upstream's public `pcre2.h`, and publishes a Zig facade over that
translation.

**One artifact, three widths, one facade.** The library it builds is upstream's
**full Unicode core with JIT off**, compiled from the same explicit source list
**three times**, once per code-unit width, and the three closures go into one
artifact with one name, one soname and one version. `-Dcode-unit-width` selects
which width that artifact is *called* and which width the typed facade speaks;
it does not select what the artifact contains, so `pcre2.c.pcre2_match_8`,
`_16` and `_32` all resolve in a width-8 build. The facade itself is
width-parameterised: `pcre2.Surface` resolves to the typed surface of the
compiled width (`zig/root.zig`), so the names below are the width's own.

Each width's closure is upstream's **full Unicode core with JIT off**: 31
translation units including the interpreter (`pcre2_match.c`), the DFA
matcher (`pcre2_dfa_match.c`), the whole Unicode property machinery
(`pcre2_ucd.c`, `pcre2_extuni.c`, `pcre2_script_run.c`, `pcre2_xclass.c`,
`pcre2_valid_utf.c`, `pcre2_ord2utf.c`), the compiled-in UCP table
(`pcre2_tables.c`) and the generated character tables
(`pcre2_chartables.c.dist`, compiled as `pcre2_chartables.c`). The list is
explicit in `build.zig:91-132` rather than globbed, so a new upstream unit
cannot enter the archive without a decision. Two further artifacts are built
from the same tree: `pcre2-posix` from `src/pcre2posix.c` and `pcre2test` from
`src/pcre2test.c`.

Nothing here reimplements the engine. Every capture this package reports is
produced by a call into a compiled upstream translation unit, and the raw C
surface is reachable directly through `pub const c`.

**This is the Zig-interface document.** The fork's canonical entry point is
[`README.md`](README.md), which carries the native-source and native-build
deviations, the build/run/test matrix and consumption for every audience —
Zig, C against an installed prefix, the Nix outputs and `devenv`. Upstream's own
README is preserved byte for byte as [`README.upstream.md`](README.upstream.md).

## Requirements

Zig **0.16.0**, the real compiler. In this workspace the bare `zig` on `PATH` is
a version dispatcher that needs a version-bearing `build.zig`, so every gate in
[Verification status](#verification-status) below names an absolute compiler.
The current receipts were produced with

```
/home/tmp2/gertullj/cache/zig/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig
```

and the earlier ones with the same compiler under
`/home/tmp/gertullj/zig-global-cache/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig`
— the trailing hash is the compiler's own and is identical in both, so those two
paths are two locations for one toolchain, not two versions.

Nothing is downloaded, no host `configure` value is read, and no installed
library is used unless you ask for `-fsys=pcre2-8`. `build.zig.zon` has no
`.dependencies`, so there is nothing for Zig to fetch.

## Commands

| Command | What it does |
|---|---|
| `zig build` | compiles the 31 core units, installs the `pcre2-8` library (dynamic by default on a GNU-libc target, static otherwise), the `pcre2.h` header, `pcre2-posix` with `pcre2posix.h`, and `pcre2test` into `zig-out/`, and **compiles** the smoke program without running it. The install step depends on the smoke program's compile step only (`build.zig:363` gives it `&smoke.step`, the `Compile` step, not the `Run` step that `smoke_step` gets at `:362`), so the default build never executes a target binary and a `-Dtarget` pointing at another machine's triple costs a cross-compile and nothing more |
| `zig build test` | runs `tests.zig`, which is **24 tests**: the 15 known answers from the fixture table, the bounds the facade owns, the version-buffer contract, the capture-lifetime cases, and one test per capability the facade wraps beyond a plain match — MARK, substring copy and list, a caller's own allocator, the newline convention, glob conversion, a callout, JIT refusal, substitution, the DFA matcher, serialization and the POSIX wrapper |
| `zig build test -Dcode-unit-width=16\|32` | the same 24 tests against the 16- or 32-bit library, with the fixtures widened or decoded into that width's code units. The graph refuses no width; see [Build modes](#build-modes) |
| `zig build test -Doptimize=ReleaseSafe` | the same suite with the optimizer on, which is where a bounds mistake that Debug catches can hide |
| `zig build smoke` | runs `smoke.zig`, which prints each capture, compares it with a code-unit offset worked out by hand, and exits non-zero on any mismatch. It runs at width 8, 16 and 32 alike |
| `zig build check` | compiles the C core, the translated interface, `tests.zig` and `smoke.zig` for **all six** required targets, running nothing |
| `zig build check -Dtarget=<triple>` | the same for exactly one target |
| `cross-test` | compiles **and runs** this package's `test` step over the full published 53-platform Zig 0.16.0 matrix, one `zig build test -Dtarget=…` per target. Settings come from `cross-test.profile.sh`; see [The full 53-platform matrix](#the-full-53-platform-matrix-cross-test) |
| `zig build test -fsys=pcre2-8` | the same tests against an **installed** libpcre2-8 and the **installed** `<pcre2.h>` |
| `zig build smoke -fsys=pcre2-8` | the smoke program against an installed library |
| `cd consumer && zig build run` | the same library, consumed by a package that did not write it. The program runs out of **the consumer's** build cache, so in a shared build it is the one entry that resolves anything — the directory this build emitted `libpcre2-8.so.0.16.1` into — and it prints the version the library reports about itself, so a run that resolved some other `libpcre2-8` on the machine would say so. `zig build` in that directory compiles the program and installs nothing: an installed copy would carry the cache directory in its `DT_RUNPATH` |
| `sha256sum -c UPSTREAM.sha256` | replays the immutable-source, licence and oracle-byte record. 59 records: 58 upstream files, plus this fork's own fixture module, which the file's own header pins deliberately so an edit to the oracle fails loudly |

**`install` compiles, `smoke` runs.** The two are different obligations and
only the named step runs anything. `zig build` and `zig build install` produce
the artifacts and prove that the smoke program builds against them; `zig build
smoke` is what executes it, and `zig build test` is what executes the test
binary. A gate that wants a runtime answer on the host asks for `smoke` or
`test` by name; a gate that wants a foreign target compiled asks for `check
-Dtarget=…` or `install -Dtarget=…`, and neither executes a target binary.

Add `-j8 --summary all` and `--cache-dir /home/tmp/gertullj/foundation-libs-cache/pcre2/native-debug`
as your workspace does.

**The six target commands.** `check` with no `-Dtarget` builds all six; these
are the six, one command each, and each is also a complete gate on its own:

```
zig build check -Dtarget=x86_64-linux-gnu
zig build check -Dtarget=aarch64-linux-gnu
zig build check -Dtarget=aarch64-macos-none
zig build check -Dtarget=x86_64-windows-gnu
zig build check -Dtarget=riscv64-linux-gnu
zig build check -Dtarget=wasm32-wasi
```

**Why `check` compiles the test and example roots.** Zig analyses a function
body only when something calls it, so compiling the C archive proves nothing
about the facade, and `std.testing.refAllDeclsRecursive` proves nothing either.
`tests.zig` and `smoke.zig` are this package's only callers of the public
surface, which is what makes them what `check` compiles: every public
declaration in `zig/root.zig` must be called from one of those two files or
`check` stops covering it. Compiling the test root for a target is what forces
every facade body to be instantiated for that target. A passing `check` is
compile evidence; nothing runs for a foreign target.

## Importing it

In your `build.zig.zon`:

```zig
.dependencies = .{
    .pcre2 = .{ .path = "../pcre2" },
},
```

In your `build.zig`:

```zig
const dep = b.dependency("pcre2", .{
    .target = target,
    .optimize = optimize,
});

const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});
exe_mod.addImport("pcre2", dep.module("pcre2"));
```

`dep.module("pcre2")` carries the compiled archive and the generated
`pcre2.h` include path with it, so the module alone is enough; nothing else has
to be linked and no path reaches into this repository. The library's C
requirement comes with it, so a dependent does not repeat `link_libc`.

In a shared build the module also carries the loader entry that resolves **this**
build's `libpcre2-8.so.0`: `Module.linkLibrary` records the directory the shared
object was emitted into, and every compilation that imports the module — a
dependent's own executable among them — gets an `-rpath` for it. That is the
entry a dependent needs, because its program is built out of a build cache where
no `lib/` sits beside it. The install tree's `$ORIGIN/../lib` is carried by the
programs this package installs and by nothing else: `pcre2test`, `pcre2grep`,
`pcre2posix_test` and the `libpcre2-posix` installed beside them are each a C
translation unit with a module of its own, and one binary cannot carry both
entries. So no installed artifact of this package names a build-cache
directory, and a dependent's program resolves this package's library rather
than a same-named system one.

The scope of that choice: `dep.module("pcre2")` is the entry for a program that
is built and run in a build cache, which is what a dependent's own build
produces. A consumer that *installs* its own executable beside its own copy of
the library needs the other entry and has to put it on its own link line — the
same `addObjectFile` + `$ORIGIN/../lib` shape `addProgram` uses here — because
`Module.linkLibrary` would add the build cache's directory back. This package
cannot hand out both entries in one module and does not try; that is the same
reason it compiles its own installed programs separately.

The raw C surface is the same module: `pcre2.c.pcre2_dfa_match_8`,
`pcre2.c.pcre2_substitute_8`, the serialization calls, and the 16- and 32-bit
declarations are all present, because `src/pcre2.h.generic:1021-1030` emits all
three widths. The typed facade wraps the DFA matcher, substitution, the
substring helpers, MARK, the callout and enumeration entry points, the convert
context and serialization; the table above is not the whole surface.

**A declaration is not a symbol, and this package makes the two agree.** The
header publishes all three widths (`src/pcre2.h.generic:1021-1030`), and
`PCRE2_SUFFIX` pastes the width into every exported name (`:1064`), so a width-8
call is not a width-16 call. Upstream ships one file per width, which would
leave two thirds of the declared surface unresolved from any one of them; this
package's primary artifact is the **union of all three genuine width closures**,
so `pcre2.c.pcre2_match_8`, `_16` and `_32` all resolve in a width-8 build. That
is a fact about *this* artifact and not a claim about PCRE2: against an
installed single-width `libpcre2-8`, which is what `-fsys=pcre2-8` binds, the
other two are link failures, and a runtime provider for this build has to be a
file that exports all three.

**`-Dcode-unit-width` selects the facade, not the archive's contents.** The
typed surface below is the selected width's own: `pcre2.Surface` resolves from
the compiled width, `test`, `smoke` and `check` run at **every** width, and
`pcre2.compiled_width` / `pcre2.compiled_unit` name what was compiled. Nothing
in this graph refuses a width, and nothing about the 16- or 32-bit facade is a
guess: it is the same file instantiated over `u16` and `u32`.

JIT is the exception to "a declaration is not a symbol", and all six public JIT
entry points **do** link: see [Build modes](#build-modes) for what each one
answers when JIT is off.

## Using it

```zig
const std = @import("std");
const pcre2 = @import("pcre2");

// Patterns and subjects are slices of **this build's code unit**. At width 8
// that is `u8` and a string literal is already the right type; at width 16 and
// 32 it is not, so a program that compiles at more than one width has to
// convert its text. `pcre2.compiled_unit` names the type.
const Unit = pcre2.compiled_unit;

/// One ASCII code point per code unit, exact for the ASCII text below and
/// refusing rather than truncating anything this width cannot hold.
fn widen(ascii: []const u8, out: []Unit) ![]const Unit {
    if (out.len < ascii.len) return error.TooSmall;
    for (ascii, 0..) |byte, i| {
        if (byte > std.math.maxInt(Unit)) return error.TooWide;
        out[i] = byte;
    }
    return out[0..ascii.len];
}

pub fn main() !void {
    // Which release this binary is linked against. The buffer is yours and
    // the answer is a window on it, so nothing is allocated and the string
    // is still valid at the next line. Ask for the capacity first if you
    // want to size it from the answer rather than guess.
    var version_buffer: [64]Unit = undefined;
    const version = try pcre2.version(&version_buffer);
    std.debug.print("linked against {s}\n", .{version});

    var pattern_units: [128]Unit = undefined;
    const pattern = try widen(
        "^(?<scheme>[a-z][a-z0-9+.-]*)://(?<host>[^/:]+):(?<port>[0-9]{1,5})$",
        &pattern_units,
    );

    // A compile rejection is a value, not an error: you usually want the code
    // and the code-unit offset to show the user.
    var regex = switch (try pcre2.Regex.compile(pattern, .{})) {
        .compiled => |compiled| compiled,
        .rejected => |rejection| {
            std.debug.print("bad pattern: error {d} at offset {d}: {s}\n", .{
                rejection.code, rejection.offset, rejection.text.slice(),
            });
            return error.BadPattern;
        },
    };
    defer regex.deinit();

    // Three owned blocks, each freed by its own `deinit`. `Regex.match` never
    // frees your `MatchData`, so a `defer` around one cannot double free.
    // The block is sized for *this* pattern; it may be reused with another
    // only while that one fits, and `match` refuses the pairing with
    // `error.OvectorTooSmall` before matching.
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();
    var context = try pcre2.MatchContext.init();
    defer context.deinit();
    context.setMatchLimit(1_000_000);

    var subject_units: [128]Unit = undefined;
    const subject = try widen("https://example.org:8443", &subject_units);
    switch (try regex.match(subject, 0, .{}, &match_data, &context)) {
        .matched => {},
        // A resource refusal is not a non-match, and a caller who chose the
        // subject needs to be able to tell them apart.
        .match_limit, .depth_limit, .heap_limit => return error.MatchRefused,
        else => return error.NoMatch,
    }

    // Captures are code-unit ranges into *your* subject. Nothing is copied.
    const host_group = regex.numberForName("host") orelse return error.NoSuchName;
    const range = (try match_data.groupRange(host_group)) orelse return error.Unset;
    const host = (try match_data.group(host_group)).?;
    std.debug.print("host is {s} at code units {d}..{d}\n", .{ host, range.start, range.end });

    // A group that did not take part, and a failed attempt, are both "no
    // range" — never stale offsets describing an earlier subject.
    for (0..regex.captureCount() + 1) |i| {
        const n: u32 = @intCast(i);
        if (try match_data.group(n)) |text| std.debug.print("  {d}: {s}\n", .{ n, text });
    }
}
```

**The offsets in that program are code-unit offsets, not bytes and not
characters.** At width 8 they coincide with bytes, which is why the 8-bit
transcripts read `units 8..19`; at width 16 and 32 the same subject is one code
unit per character, and the same numbers come back. For a `PCRE2_UTF` pattern
a three-code-unit character still advances `end` by three.

`smoke.zig` is the runnable version of this with every expected code-unit offset
checked rather than merely printed, and `consumer/src/main.zig` is a structured
log reader across a package boundary.

## The API

Everything the facade names is read out of upstream's own declarations, and each
declaration's comment in `zig/root.zig` cites the line it came from — the header
for a constant, the implementing translation unit for a behaviour.

### Compiling and matching

| Declaration | What it is |
|---|---|
| `Regex.compile(pattern, CompileOptions) Error!CompileOutcome` | `pcre2_compile_N`. A malformed pattern is a value (`.rejected`), not an error; only a failed allocation is |
| `Rejection{ code, offset, text }` | upstream's compile error number (100 + an index, `src/pcre2_compile.h:53-54`), the code-unit offset in the pattern, and upstream's own sentence |
| `Regex.captureCount() u32` | `PCRE2_INFO_CAPTURECOUNT`, the **highest** group number, so a pattern with no groups answers 0 and there are `captureCount() + 1` groups counting group 0 |
| `Regex.nameCount() u32` | `PCRE2_INFO_NAMECOUNT` — how many names the pattern declared. A count, not a group number |
| `Regex.nameAt(index) ?Name` | one entry of the compiled name table, **in alphabetical (name) order**, or null past the end. The index is a table position, not a group number; the `Name.name` slice borrows the compiled block |
| `Regex.nameForNumber(number) ?[]const u8` | the name bound to a group number, or null. A scan, because the table is in alphabetical order rather than group order, so the answer is not at a position `number` can index into |
| `Regex.numberForName(name) ?u32` | the group number a name is bound to, or null when the pattern has no such name. A name longer than `max_name_length` is refused without a lookup, because no pattern this fork accepted can have one |
| `Regex.raw() *const c.pcre2_code_N` | the compiled block itself, for an entry point this facade does not wrap. Still owned by the `Regex` |
| `Regex.match(subject, start_offset, MatchOptions, *MatchData, ?*MatchContext) Error!MatchOutcome` | `pcre2_match_N`. The subject is borrowed; offsets are **code-unit** offsets into it. Two bounds are checked before matching, capacity first: the block must hold all capture groups plus group 0 (`OvectorTooSmall`) and the start offset must be in the subject (`StartOffsetOutOfRange`) |
| `CompileOptions`, `MatchOptions` | packed structs of `bool` with `= false` defaults, so `.{ .{} }` is upstream's default and a partial literal is valid. `toBits()` is the only conversion direction, so a bit this file does not name cannot be set |
| `MatchOptions.partial_soft` / `.partial_hard` | ask for the best partial match. The answer is `MatchOutcome.failed` with code `PCRE2_ERROR_PARTIAL`, **-2**, not a typed partial result: upstream wrote the partially matched part into `ovector[0]`/`ovector[1]` and the start into `startOffset()` (`src/pcre2_match.c:8204-8209`) and the facade reports the code and leaves `matched` false. Match `code` against -2 rather than guessing from the tag, and read the end through `MatchData.ovector()` — which needs `matched` true, so on this path it is the raw `c.pcre2_get_ovector_pointer_N` |
| `MatchOptions.copy_matched_subject` | PCRE2 keeps its own copy of the subject in the match block. That is a **native** allocation PCRE2 frees at the start of the next `match` on the block or when the block is freed (`:7110-7115`), so no Zig leak checker sees it. `MatchData.subject` stays the borrow of your slice either way |
| `MatchOptions.no_jit` | accepted and ignored: this fork builds with JIT off, so there is no compiled JIT code for it to turn off |

### Reading a result

| Declaration | What it is |
|---|---|
| `MatchOutcome.matched` | `pcre2_match_8` returned one or more and `MatchData.matched` is true. The two are the same fact — the tag is never returned without it, so reaching this arm means every capture is readable. A return of **zero** is upstream's truncated answer and is reported as `error.OvectorTooSmall`, never as this tag |
| `MatchOutcome.no_match` | `PCRE2_ERROR_NOMATCH`, -1 (`src/pcre2.h.generic:350`). An ordinary negative answer, not a failure and not an error |
| `MatchOutcome.match_limit` / `.depth_limit` / `.heap_limit` | -47, -53, -63: the ceilings were reached. The pattern may well match; the work was refused |
| `MatchOutcome.invalid_utf{ code, text }` | a UTF validity failure, with upstream's own number and sentence. The mapped range is **`-28…-3` and `-36`**, and it is one range across the widths because the codes are width-specific: `PCRE2_ERROR_UTF8_ERR1`…`_ERR21` are **-3…-23** in the 8-bit library, `PCRE2_ERROR_UTF16_ERR1`…`_ERR3` are **-24…-26**, `PCRE2_ERROR_UTF32_ERR1`…`_ERR2` are **-27…-28**, and `PCRE2_ERROR_BADUTFOFFSET` is **-36** (`src/pcre2.h.generic:355-400`). Classifying only the 8-bit ones left a 16- or 32-bit validity failure arriving as `.failed`, which is the wrong tag for the same condition |
| `MatchOutcome.failed{ code, text }` | any other negative return, with its number. Nothing is flattened into a generic failure. `code == -2` is `PCRE2_ERROR_PARTIAL` and means a partial match, not a plain failure |
| `MatchData.groupRange(n) Error!?Group` | `{ start, end }` **code-unit** offsets into the subject, or null when there is no range |
| `MatchData.group(n) Error!?[]const code_unit` | the captured code units, or null on the same two conditions. A window on your subject, not a copy, resolved against `MatchData.subject` |
| `MatchData.startOffset() usize` | match start; malformed code-unit offset after a UTF validity failure; partial start after `PCRE2_ERROR_PARTIAL`. The native matcher resets it to zero before the other documented outcomes (`src/pcre2_match.c:7120`). A facade refusal does not run the matcher or reset this field, so it can retain the previous attempt's value. Interpret it with the outcome, not as proof of a readable capture |
| `MatchData.subject` | the subject the most recent attempt used, borrow, valid until the next `match`, `dfa` **or `substitute`** on this block. It is set even when that attempt was refused or did not match, and it is what `group` resolves a range against — do not write it |
| `MatchData.matched` | whether the offset vector was written by the most recent attempt. `false` means nothing is readable, whatever the vector still holds |
| `MatchData.raw`, `MatchContext.raw`, `Regex.code` | PCRE2's own blocks, published for entry points this facade does not wrap. `null` once `deinit` has run. Writing a different block into a live `MatchData` is not detectable here: `matched` and `subject` describe the attempt that filled the block being replaced |
| `MatchData.captureCount() u32` | how many offset-vector pairs the block holds, one more than the capture count of the pattern `create` was given |
| `Text{ bytes, len }`, `Text.slice()` | upstream's own message, without the terminating NUL |
| Width-agnostic spelling | every `pcre2_*_8` in these tables is `pcre2_*_N` for the compiled width; the facade is one file instantiated over `u8`, `u16` or `u32`, and `pcre2.compiled_width` / `pcre2.compiled_unit` name which. Only where a table says `_8` literally does it mean the 8-bit library |

### Beyond the interpreter

`Regex.match` is one of the entry points this facade wraps, not the whole of
it. These are the rest, with the parts a caller gets wrong most easily.

| Declaration | What it is |
|---|---|
| `Regex.dfa(subject, start_offset, DfaOptions, *MatchData, ?*MatchContext, *DfaWorkspace) Error!DfaOutcome` | `pcre2_dfa_match_N`. **The matched ranges land in `match_data`, never in `workspace`**: the matcher is handed the block's own offset vector as its output (`src/pcre2_dfa_match.c:4062-4063`), and upstream's own substring helpers read a DFA result out of that block (`src/pcre2_substring.c:334-341`) |
| `DfaOutcome.matched{ pairs }` | `pairs` is **upstream's return value**: how many offset-vector entries it wrote, two per match. The pairs are read from `MatchData.ovector()`, and they are matched substrings and **not** capture groups — this matcher has no groups (`doc/pcre2.txt:4340-4343`) — ordered **longest first** (`:4352-4360`) |
| `DfaOutcome.truncated` | a return of **zero** (`src/pcre2_dfa_match.c:905-911`): more substrings were found than the block's vector could hold, and it holds the longest ones (`doc/pcre2.txt:4359-4360`). `MatchData.matched` is **true** and `ovector()` is readable — this is a truncated result, not a failure and not an empty one, and the pairs that did not fit are simply not there |
| `DfaOutcome.no_match` | `PCRE2_ERROR_NOMATCH`, -1. Anything else negative is `.failed` with upstream's number, `-43` (`PCRE2_ERROR_DFA_WSSIZE`) included, because a workspace below upstream's own floor is refused before the matcher runs rather than reported after |
| `DfaWorkspace{ offsets: []c_int }` | the caller's scratch buffer, and the only place `DfaOptions.restart`'s state can live: PCRE2 reads its own bookkeeping out of the first two entries and refuses a restart whose state it did not write (`src/pcre2_dfa_match.c:3486-3489`). **It carries no result and has no pair accessor** — what is left in it after a run is the matcher's own |
| `minimum_workspace = 20` | upstream's floor (`src/pcre2_dfa_match.c:3437`), the size upstream's own worked example passes (`doc/pcre2.txt:4279-4288`). `DfaWorkspace.wscount(subject_len)` is `max(subject_len, minimum_workspace)`: it floors the **count** and cannot floor the caller's storage, which is why `dfa` checks the buffer separately and answers `error.DfaWorkspaceTooSmall` |
| Sizing a block for DFA | `MatchData.create(&regex)` sizes the vector for this pattern's **capture groups**, which is the wrong number for this matcher: the vector has to hold every simultaneous match, so size it with `MatchData.createWithOvector(pairs, …)` (`doc/pcre2_dfa_match.3:33-35`) |
| `Regex.substitute(subject, start_offset, SubstituteOptions, replacement, *MatchData, ?*MatchContext, buffer) Error!Substitution` | `pcre2_substitute_N`. Nothing is allocated: `Substitution.written.text` is a window on **your** buffer. A buffer that does not fit is `error.SubstituteBufferTooSmall` and **nothing is written**. **It also invalidates your captures**: see the next row |
| What `substitute` leaves in `match_data` | nothing readable, unless `SubstituteOptions.matched` is set. Upstream matches **into your block** (`src/pcre2_substitute.c:984`), so the vector holds the *last internal match's* pairs while the block's `rc` field holds the **number of substitutions it made** (`:1762`, `:1768`) — and every native substring entry point reads that field as a *pair count* (`src/pcre2_substring.c:317`, `:390`). So the block is moved into the "nothing readable" state before the call runs, whichever way the attempt ends, and the substitution count is reported as `Substitution.written.substitutions` rather than left in the block. Without this, a `group()` call resolved substitute-subject offsets against an earlier, shorter subject, and `list()` walked a pair count larger than the vector it was reading |
| `SubstituteOptions.matched` is the exception | upstream copies your block into one of its own, matches into that, and frees it (`src/pcre2_substitute.c:898-917`, `:1767`), so the captures that were in the block are still the ones in it and this facade leaves them alone. It substitutes the match **already in the block**, so it is also the only substitution whose result depends on what was there before |
| `Substitution.overflow: usize` | `SubstituteOptions.overflow_length` turns the same too-small condition into the length the result needs, **including its terminating NUL** (`src/pcre2_substitute.c:1746-1755`), without writing. Size a buffer to it and call again without the option |
| `ConvertContext.create / setGlobEscape / setGlobSeparator` | the two settings a glob conversion has: which character escapes the next one, and which character separates path components. `create` produces upstream's own defaults. **Both setters can refuse**: `pcre2_set_glob_escape_N` takes anything up to 255 that is either zero or one of the glob punctuation characters (`src/pcre2_context.c:547-554`) and `pcre2_set_glob_separator_N` takes only `/`, `\` or `.` (`:528-535`); anything else is `PCRE2_ERROR_BADDATA`, -29, and this facade reports it as `error.SettingRefused` without classifying which value caused it |
| `ConvertContext.convert(pattern, kind, utf) Error!{ converted, rejected }` | one call per pattern **kind**, because the three glob values are cumulative rather than independent: upstream spells "no wildcard crosses a separator" as `PCRE2_CONVERT_GLOB` + `0x20`, so `convert_option.glob_no_wild_separator` **is** that sum and asking for it without also asking for a glob is not expressible. A rejection is a value (`.rejected`), not an error |
| `Converted{ bytes, len }`, `.slice()`, `.deinit()` | **owned, and the slice excludes the terminating NUL.** `pcre2_pattern_convert_N` writes the pattern into a buffer this library allocated, writes the NUL itself, and then answers `out.output_size - 1` (`src/pcre2_convert.c:381-382`, `:1080`, `:1092`), so the reported length is the text and not the terminator. That is why `Regex.compile`, which takes an explicit length, is the right consumer. **This is not a compiled block:** the block carries a hidden header for the allocator that produced it, so it is released with `pcre2_converted_pattern_free_N` and by nothing else — not `pcre2_code_free`, not a Zig allocator |
| `convert_option.glob` / `.glob_no_wild_separator` / `.glob_no_starstar` | `0x0010`, `0x0030`, `0x0050` (`src/pcre2.h.generic:205-207`). Pass exactly one |
| `CompileContext.setCharacterTables(tables)`, `GeneralContext.tables()` | **PCRE2 keeps the pointer, not a copy of the bytes.** `pcre2_set_character_tables_N` stores the address exactly as it was given (`src/pcre2_context.c:326-329`) and `pcre2_compile_N` stores that same pointer in the block it builds (`src/pcre2_compile.c:10451`, `:10960`) with no `PCRE2_DEREF_TABLES` flag, so `pcre2_code_free` does not free them either (`:1146`). Those 256 bytes must therefore **stay alive for as long as every pattern compiled through that context**, and nothing here releases them — that is the caller's storage, not PCRE2's. Two blocks built from two different table addresses are what `PCRE2_ERROR_MIXEDTABLES` is about, because upstream compares the pointers rather than their contents (`src/pcre2_serialize.c:99-102`) |
| `MatchData.ovector() Error![*c]usize` | the block's own offset vector, valid **only** while `matched` is true; otherwise `error.SubstringUnavailable`. It is the escape hatch for the two cases the typed accessors deliberately do not model — the end of a `PCRE2_ERROR_PARTIAL`, and a DFA result, whose pairs are substrings and not groups. Read two entries per pair |
| `MatchData.get(n) Error!Owned` | `pcre2_substring_get_bynumber_N`: a **library-allocated copy**, released by `Owned.deinit` with `pcre2_substring_free_N` and by nothing else. It copies out of the block's own record of the subject, which is your slice unless the match was made with `copy_matched_subject`, in which case it is PCRE2's copy and that is the one being read. A group that did not take part is `error.SubstringUnavailable`, which is upstream's `PCRE2_ERROR_UNSET`, -55, and not a zero-length copy |
| `MatchData.copy(n, buffer) Error!usize` | `pcre2_substring_copy_bynumber_N`: into **your** buffer, no allocation, and the return is the code units written **including** the NUL PCRE2 writes after the last one (`src/pcre2_substring.c:117-130`, `:127`). A buffer exactly the capture's length is therefore one short: `error.SubstringBufferTooSmall`, answered before anything is written |
| `MatchData.list() Error!SubstringList` | `pcre2_substring_list_get_N`: **one native block**, holding the null-terminated array of capture pointers at its head and the array of lengths beside the strings (`src/pcre2_substring.c:379-438`). `SubstringList.bytes` is that **array**, not the first string, because `pcre2_substring_list_free_N` frees the block from the array (`:451-459`); `deinit` hands it that address. A group that did not take part is an **empty** string here (`:421-434`), which is upstream's answer and not this facade's `unset` |
| `MatchData.next(start_offset: *usize, options: *u32) bool` | `pcre2_next_match_N`: whether another attempt should be made from this block, which a caller iterating over every match in a subject calls after each successful attempt. **`true` resumes, `false` is the end of the subject**, and those are the only two answers upstream can give (`src/pcre2_match_next.c:109`, `:134`, `:152` write `FALSE`, `:138-140`, `:157-159`, `:166-168` write `TRUE`), so **there is nothing here to refuse and no error union** — a plain `bool`. Both arguments are **single-value out-parameters** (`src/pcre2.h.generic:775`), each written at most once and only on the paths that answer `true` (`src/pcre2_match_next.c:138-139`, `:157-158`, `:166-167`); the three `false` returns write neither. Hand `start_offset` to the next attempt as it stands, and combine `options` with the application's own match options (`doc/pcre2.txt:3433-3444`). The start offset advances on every `true`, which is what makes such a loop terminate (`:3465-3470`) |
| `MatchData.mark() Error!?[]const code_unit` | the last MARK label of a successful attempt, `pcre2_get_mark_N`. It is the **compiled** label, so it borrows the `Regex` and not the subject, and `copy_matched_subject` does not affect it. `null` for an attempt that did not match and for a pattern with no MARK |
| `MatchContext.setCallout(cb, data) Error!void` | the callback and `data` are **yours and are not copied**: PCRE2 holds the two pointers and calls them for the life of the context (`pcre2_set_callout`). A callback and the ceilings share one context, so installing one and then borrowing the context elsewhere is your ordering to get right. **Zero continues**; the matcher branches on the answer's **sign** (`src/pcre2_match.c:5989-5994`) — a **positive** answer declines this start position and the matcher keeps looking, a **negative** one abandons the whole attempt with that number as the return. "Non-zero means keep going" is backwards |
| `Regex.enumerateCallouts(cb, data) Error!u32` | `pcre2_callout_enumerate_N`, a compile-time walk of the pattern's callout blocks. **The callback is required, not optional**: upstream calls it for every `OP_CALLOUT`/`OP_CALLOUT_STR` and never tests it for null (`src/pcre2_pattern_info.c:405`, `:418`), so passing null on a pattern that has a callout is a crash rather than a refusal. The type is `pcre2.CalloutEnumerate`, a plain `*const fn` — an optional pointer would be a shape upstream never produces. Its negatives are `error.PatternInfoUnavailable`: `PCRE2_ERROR_NULL` for a block that is not there, `PCRE2_ERROR_BADMAGIC` and `PCRE2_ERROR_BADMODE` for one that is not this width's mode |
| `Regex.jitCompile(options) Error!JitOutcome` | `pcre2_jit_compile_N`. **In this build the answer is always `JitOutcome.refused` with `PCRE2_ERROR_JIT_BADOPTION`, -45**, because `SUPPORT_JIT` is 0: `deps/sljit` is an empty submodule, there is no SLJIT, and `pcre2_jit_compile.c` compiles its `#ifndef SUPPORT_JIT` fallback. The refusal is a **value carrying upstream's number**, not an error, precisely because the same call against a provider that does have JIT would answer `compiled` |
| `JitStack.create(…) Error!JitStack` | `pcre2_jit_stack_create_N` answers **NULL**, and a failed allocation also arrives as NULL (`src/pcre2_jit_misc_inc.h:125-134`), so this one entry point is named for what it saw: `error.JitUnsupported` here. Only the caller's knowledge of the configuration tells the two apart, and this package says which one it saw. **There is no fallback interpreter wearing JIT's name** — the interpreter is what runs a match, and it is reached through `Regex.match` |
| `Regex.serialize`, `Regex.decode`, `Regex.serializedCodeCount`, `Serialized` | `pcre2_serialize_encode_N` / `pcre2_serialize_decode_N`. The encoded form is **owned**, released with `pcre2_serialize_free`, and the blocks named in `extra` are **not** released by it and outlive the call. **A refusal is not an allocation failure**: only `PCRE2_ERROR_NOMEMORY` is `error.OutOfMemory`, and everything else those three can refuse is `error.SerializationRefused`. **The pointer arrays are yours and are bounded here**: each entry point writes one block pointer per block it handles and cannot see the length of the array it was handed (`src/pcre2_serialize.c:94-96`, `:204`, `:243`), so `serialize` compares its `scratch` against this pattern plus every entry of `extra`, and `decode` requires **`count <= all.len`** — a destination shorter than the `count` it was asked for, **an empty one included**, is `error.OvectorTooSmall` before anything is decoded, rather than an overrun the caller finds out about later. Upstream caps `count` at what the stream holds and answers it (`:183-184`, `:248`) |
| `Posix.compile(pattern, flags)`, `Posix.exec(compiled, subject, pmatch, flags)`, `Posix.capture(subject, match)`, `Posix.message(buffer, err, compiled)` | the POSIX `regcomp`/`regexec` emulation, width 8 only. `Posix.unset` is **`-1`**, not `PCRE2_UNSET`: the wrapper writes that literal into both ends of a `regmatch_t` and into every slot past the ones the match filled. `REG_NOSUB` is a **compile-time** bit — the wrapper remembers it in the block and zeroes its own match count from that record, which is why `exec` reports `matched_without_reporting` from the compiled flags and not from its own argument. `REG_STARTEND` and `REG_PEND` are `error.UnsupportedOption`: both make the wrapper read a pointer-sized value out of a `const char *` argument rather than a string |

### Resource ceilings, and the library's own identity

| Declaration | What it is |
|---|---|
| `MatchContext.init() Error!MatchContext` | a context holding upstream's current defaults |
| `MatchContext.setMatchLimit / setDepthLimit / setHeapLimit` | the three ceilings; reaching one is a `MatchOutcome` case, not an error |
| `version(buffer: []u8) Error![:0]const u8` | the version string the **linked** library reports, written into your buffer and returned as a window on it |
| `pub const c` | complete translated `pcre2.h` for this build — all three widths, DFA, substitute, serialization. All three widths are **declared**, and this package's primary artifact **defines** all three, because it is the union of the three upstream width closures. Six JIT fallback entry points are defined and refuse. See [Importing it](#importing-it) |
| `pub const Error` | the closed set below |
| `pub const unset: usize` | `PCRE2_UNSET`, `src/pcre2.h.generic:539` |
| `diagnostic_buffer_size = 128` | how much message is kept; a longer one is truncated and `Text.len` says so |
| `max_name_length = 128` | `MAX_NAME_SIZE`; `pcre2_compile.c:2671` refuses a longer name, so no accepted pattern has one |

### The error set

`Error` has **fourteen** members and each is a comparison this package actually
made. None of them is a catch-all: anything this facade does not classify comes
back as a `MatchOutcome.failed` with upstream's own number rather than as an
error.

| Error | When |
|---|---|
| `OutOfMemory` | a PCRE2 entry point failed to allocate. Three answer NULL and are reached that way — `pcre2_compile` with error 121, `pcre2_match_data_create_from_pattern_N`, `pcre2_match_context_create_N` — and two answer the code `PCRE2_ERROR_NOMEMORY`, -48, which arrives here the same way: `pcre2_serialize_encode_N` and `pcre2_decode_N` each allocate with `memctl->malloc` and check the result themselves (`src/pcre2_serialize.c:108`, `:192`, `:221`). **Only that code is this name**; every other refusal those entry points can give is `SerializationRefused` |
| `PatternInfoUnavailable` | `pcre2_pattern_info_8` refused one of the four queries this package makes once, at compile time. The block is released rather than leaked |
| `StartOffsetOutOfRange` | the start offset is past the end of the subject. Checked before matching, which would return `PCRE2_ERROR_BADOFFSET`. Capacity is checked first, so a call that also has an undersized block returns `OvectorTooSmall` |
| `NoSuchGroup` | the group number is not below `MatchData.captureCount()`. PCRE2's own substring helpers would index its offset vector past the end. Answered before the match state is looked at, so it is a statement about the index whatever the block last did |
| `OvectorTooSmall` | `Regex.match`: the block cannot hold this pattern's capture groups plus group 0. The facade clears readable capture state and refuses before matching. Upstream would fill what fits and return zero (`doc/html/pcre2api.html:3308-3312`, `src/pcre2_match.c:8157-8158`). `MatchData.create`: the native pair count was clamped below this pattern's requirement (`src/pcre2_match_data.c:57-58`); the newly allocated block is released before returning the error. `Regex.serialize` and `Regex.decode`: a third and fourth site, and one bound rather than the same one — each takes a caller-owned array of block pointers and neither can see its length (`src/pcre2_serialize.c:94-96`, `:204`, `:243`), so `serialize` compares its `scratch` against the blocks it is about to hand upstream and `decode` compares its `all` against the `count` it was asked for |
| `VersionBufferTooSmall` | your buffer is shorter than the size the library says it needs. Checked **before** the call that writes, because `pcre2_config_8` takes a `void *` and cannot know the capacity |
| `VersionUnavailable` | the library declined the `PCRE2_CONFIG_VERSION` query instead of answering it. There is no placeholder string: substituting one would report a release the archive was never built with |
| `SettingRefused` | one of the `pcre2_set_*` setters was given a value it does not accept: `PCRE2_ERROR_BADDATA`, -29. The name is for the refusal, not for the value — this package does not classify which argument caused it |
| `SubstituteBufferTooSmall` | `Regex.substitute`'s buffer could not hold the result. `pcre2_substitute_N` checks the room before every fragment and gives up with `PCRE2_ERROR_NOMEMORY`, -48, without writing (`src/pcre2_substitute.c:638-656`, `:1771-1773`). `SubstituteOptions.overflow_length` turns the same condition into the needed length instead |
| `DfaWorkspaceTooSmall` | `Regex.dfa`'s buffer is below `minimum_workspace`. `wscount` floors the **count** it passes and cannot floor the caller's **storage**, so the bound is checked here, before the matcher runs |
| `JitUnsupported` | this build has no SLJIT, so `pcre2_jit_stack_create_N` refused (`src/pcre2_jit_misc_inc.h:125-134`). That NULL is a refusal rather than a failed allocation and the two arrive the same way, which is why both this name and `OutOfMemory` exist |
| `SubstringUnavailable` | the block has no readable capture: the last attempt did not match, the group did not take part (`PCRE2_ERROR_UNSET`, -55), the block's vector is too small to index it (`PCRE2_ERROR_UNAVAILABLE`, -54), or the pattern does not declare it (`PCRE2_ERROR_NOSUBSTRING`, -49). One name for the condition, and the code is not reported rather than guessed |
| `SubstringBufferTooSmall` | `MatchData.copy`'s buffer was too small: `pcre2_substring_copy_bynumber_N` needs `size + 1`, because it writes the terminating NUL after the last code unit (`src/pcre2_substring.c:117-130`), and answers before writing anything |
| `SerializationRefused` | the serialization entry points refused the stream itself, not the allocation. `PCRE2_ERROR_MIXEDTABLES`, -30, is two blocks whose character tables sit at **different addresses** — upstream compares the pointers, not the contents (`src/pcre2_serialize.c:99-102`). `PCRE2_ERROR_BADMAGIC`, -31, and `PCRE2_ERROR_BADMODE`, -32, are a header that is not this stream's (`:176-181`). `PCRE2_ERROR_BADSERIALIZEDDATA`, -62, is a header or block that does not describe what it must, including one whose `name_entry_size` or `name_count` exceeds the maxima (`:178`, `:209-213`, `:229-235`). `PCRE2_ERROR_BADDATA`, -29, is a count of zero or less (`:88`, `:272-275`). `PCRE2_ERROR_NULL`, -51, is a null block. **One name for the condition, and the number is not reported rather than guessed** — none of these is an allocation failure |

## Ownership and lifetimes

* **`Regex` owns the `pcre2_code`** and releases it in `deinit`. A second call
  on the same value does nothing; `deinit` takes a mutable pointer and clears
  it. **Copying the struct copies the pointer, and that copy is not made safe
  by the one being cleared** — one owner, released once.
* **`MatchData` and `MatchContext` are owned separately** and released by their
  own `deinit`. `Regex.match` never frees your `MatchData`. The same
  single-owner rule applies to both: a copy taken before `deinit` names the
  same PCRE2 block, and releasing both frees it twice. A `MatchContext` may be
  shared across many attempts and many patterns; `subject`, by contrast, is
  not a caller's to overwrite, because `group` resolves a range against it.
* **No Zig allocator is handed to PCRE2, no general context is created, and no
  global allocator hook is installed.** PCRE2 allocates these blocks with
  `malloc` and frees them with its own `free`; the Zig test framework therefore
  cannot supply a leak oracle for them, and the ownership test in `tests.zig`
  checks the transition (each owner holds null, a second `deinit` is the same
  no-op) rather than pretending to observe a free.
* **Capture ranges are code-unit offsets into the subject you passed.** `MatchData`
  borrows that slice and never copies it, so a capture is a window on your own
  buffer: writing through it is visible through the capture, and a capture must
  not outlive its subject.
* **A capture is valid until the next `match`, `dfa` or `substitute` on that
  block — three writers, not one.** `match` and `dfa` overwrite the vector
  deliberately and the facade marks it unreadable when they do not;
  `substitute` does the same for a different reason, because upstream matches
  into the caller's block and then leaves its `rc` field holding the
  substitution count rather than a pair count. The exception is
  `SubstituteOptions.matched`, which matches into an internal copy of the block
  and so leaves the captures that were there intact. Reading a capture after
  any of the three, without re-reading `MatchData.matched`, is the mistake this
  rule exists to prevent.
* **A failed or refused attempt leaves the block describing nothing at all.**
  PCRE2 keeps the offset vector of the previous match across a failed attempt
  (`doc/html/pcre2api.html:3330-3334`), and those offsets describe a subject you
  may no longer be holding. `Regex.match` therefore clears its own validity
  state for **every** attempt — including one it refuses for a too-small
  vector — and sets it only when `pcre2_match_8` returned one or more, so
  `groupRange` and `group` answer null until one of them matches. Group 0 is
  no more readable than a capture, and `.matched` is never returned while the
  flag is false. The raw C escape hatch is still there for a caller who wants
  upstream's own behaviour.
* **`startOffset()` must be read with the attempt's outcome.** After a match,
  it is the match start. It also carries the malformed code-unit offset after
  a UTF validity failure (`src/pcre2_match.c:7334`) and the partial start after
  `PCRE2_ERROR_PARTIAL` (`:8206`). Native `no_match`, ceiling and invalid UTF
  boundary outcomes leave it at zero after the reset at `:7120`.
  `OvectorTooSmall` and `StartOffsetOutOfRange` are facade refusals that do
  not enter the matcher. They clear readable capture state, but leave this
  native field untouched. It can retain the previous attempt's value.
* **A partial match is reported, not modelled.** With
  `MatchOptions.partial_soft` or `.partial_hard`, upstream writes the partially
  matched part into `ovector[0]` and `ovector[1]` and returns
  `PCRE2_ERROR_PARTIAL` (`src/pcre2_match.c:8204-8209`). The facade has no tag
  for that, so it arrives as `.failed` with `code == -2` and no readable
  capture: the start is available through `startOffset()` and the end only
  through `MatchData.ovector()`. Nothing about the attempt is recoverable by
  guessing from the tag.
* **A group the pattern skipped is `PCRE2_UNSET` in the vector, which is null
  here** — not a zero-length range. A group that did not take part and a group
  that matched an empty string are different answers, and the second is
  `{ .start = k, .end = k }`.
* **`version` is caller-owned.** The buffer belongs to you and so does the
  answer: `buffer[0..len]` is the string, `buffer[len]` is the NUL, both written
  by the library, and the returned slice borrows that storage. There is no
  static cache, no global and no allocation. A buffer shorter than the size the
  library asks for is `error.VersionBufferTooSmall` and **nothing is written**.
* **Offsets are code-unit offsets, not character indices.** For a `PCRE2_UTF`
  pattern, a three-byte character advances `end` by three.
* **The name table is PCRE2's own, in PCRE2's own order, and PCRE2 owns it.**
  The compiler keeps the table in **alphabetical (name) order** — that is what
  `pcre2_substring_number_from_name` binary-searches
  (`src/pcre2_substring.c:495-523`), and the insert routine's own header says
  it is "maintaining alphabetical order"
  (`src/pcre2_compile_cgroup.c:106-108`). It is **not** group order and not
  the order the names were written in, so `nameAt(index)`'s index is a
  position in the table, not a group number, and the group numbers it yields
  need not ascend. The table lives between the fixed part of the compiled block
  and the compiled code (`src/pcre2_pattern_info.c:230-232`,
  `src/pcre2_compile.c:10985-10990`), and every entry is sized to the
  **longest** name in the pattern, plus `IMM2_SIZE` code units for the group
  number and one for a terminator (`src/pcre2_compile.c:5713-5716`,
  `src/pcre2_compile_cgroup.c:167-175`), so a short name is followed by NUL
  padding rather than by the next entry. **`IMM2_SIZE` is two code units at
  width 8 and one at width 16 or 32** (`src/pcre2_intmodedep.h:212-221`): in the
  8-bit library the group number is a big-endian pair, in the other two it is a
  single code unit. `Name.name` is a slice of **code units**, one per name
  character of this width, and the `Name.number` in front of it is read with
  `GET2`. Reading a 16- or 32-bit table as bytes lands inside a code unit and
  names a different group every time. The `Name.name` slice is a borrow from
  that block: valid only while the `Regex` lives, and not NUL-terminated
  in the returned slice. Use `nameForNumber` or `numberForName` rather than
  depending on the table's order.
* **Four values own a block PCRE2 allocated, and each has exactly one correct
  free.** `Owned` (`MatchData.get`) → `pcre2_substring_free_N`;
  `SubstringList` (`MatchData.list`) → `pcre2_substring_list_free_N`;
  `Converted` (`ConvertContext.convert`) → `pcre2_converted_pattern_free_N`;
  `Serialized` (`Regex.serialize`) → `pcre2_serialize_free`. **Each block
  carries a hidden header naming the allocator that produced it**, which is why
  none of them may be released with `pcre2_code_free`, with a Zig allocator, or
  by indexing into it — and why the free has to come from the same library
  instance that made the block. Every one of these `deinit`s clears its handle,
  so a second call is the same no-op rather than a second free. `SubstringList`
  is the sharpest of the four: `pcre2_substring_list_free_N` frees the block
  **from the array of pointers** (`src/pcre2_substring.c:451-459`), so
  `SubstringList.bytes` is that array and not the first string in it.
* **`Converted.slice()` excludes the terminating NUL, on purpose.**
  `pcre2_pattern_convert_N` writes the NUL into its own output
  (`src/pcre2_convert.c:382`, `:1080`) and then answers `out.output_size - 1`
  (`:381`, `:1092`), so the reported length is the text. Hand it to
  `Regex.compile`, which takes an explicit length; the only way to see the
  terminator is a C call that wants one.
* **A `DfaWorkspace` is yours for the whole job, including a restart.** It is
  the matcher's own working storage, and with `DfaOptions.restart` it is the
  **only** place the resumable state can live: PCRE2 reads its bookkeeping out
  of the first two entries and refuses a restart whose state it did not write
  (`src/pcre2_dfa_match.c:3486-3489`). So the same buffer must be handed back
  on the next call, which is why `DfaWorkspace` holds a slice rather than
  taking it by value. Nothing is allocated and PCRE2 neither keeps nor frees
  it. The **result** is elsewhere — in the `MatchData` block's offset vector,
  read through `MatchData.ovector()` — and a `truncated` answer means it is
  readable but incomplete, not that it is empty.
* **A callout's callback and `data` are borrowed, not copied.**
  `pcre2_set_callout_N` stores the two pointers in the context and calls them
  for as long as the context lives, so both must outlive every attempt made
  through it. The same holds for `setSubstituteCallout` and
  `setSubstituteCaseCallout`. A callout and the three ceilings share one
  context, so installing one and then borrowing the context into something else
  is the caller's ordering to get right.
* **The POSIX wrapper's block is held by value, and that is the lifetime
  rule.** `Posix.Compiled.raw` is a `regex_t` **inline**, not a pointer to one,
  because `pcre2_regcomp` fills the struct the caller hands it
  (`src/pcre2posix.c:277-301`) and `pcre2_regfree` is the one that reads it
  back — a pointer into `compile`'s frame would name a slot that is gone by the
  time anything could free it. Two PCRE2 blocks live inside it, a compiled
  pattern and a match-data block, and `pcre2_regfree` frees **both**
  (`:254-259`, allocated at `:301` and `:325`), so nothing escapes and there is
  nothing to release twice. `Posix.capture` holds no pointer back to the
  subject, which is why it is a free function taking the subject: pass the
  same slice `exec` was given.
* **`Posix.unset` is `-1`, and it is not `pcre2.unset`.** The wrapper writes
  that literal into both ends of a `regmatch_t` for every group `pcre2_match`
  left unset **and into every slot past the ones the match filled**
  (`src/pcre2posix.c:403-408`), so a `regmatch_t` array shorter than the
  pattern's capture count is a smaller answer rather than an overrun. `-1` and
  `PCRE2_UNSET` are different values and a POSIX capture compared against the
  width surface's marker never matches. `REG_BADPAT` is the wrapper's default,
  not its answer for every bad pattern (`src/pcre2posix.c:312-319`): `a(b` is
  `REG_EPAREN`.
* **JIT has no fallback to own.** `deps/sljit` is an empty submodule and
  `SUPPORT_JIT` is 0, so `Regex.jitCompile` answers `JitOutcome.refused` with
  upstream's own -45 and `JitStack.create` answers `error.JitUnsupported`.
  Neither is dressed up as a match: the interpreter is reached through
  `Regex.match` and nothing pretends to be compiled code.

## How the header is translated

The facade is not written against a hand-written description of PCRE2's API.
`pub const c` is whatever `zig translate-c` made of **upstream's own
`pcre2.h`** — the `addWriteFiles` copy of `src/pcre2.h.generic` this graph just
made, which is the same copy every C translation unit of the core compiles
against — so the declarations the facade calls and the symbols the archive
defines are one revision by construction. No prototype is copied into a Zig
file, no declaration is written down by hand, and no feature is published that
the header does not declare.

Three things are configured around that header rather than inside it:

* **`PCRE2_CODE_UNIT_WIDTH`** is defined on whichever line reads the header for
  the target, and it is the width the core was compiled with:
  `src/pcre2.h.generic:1057-1059` hard-errors without it, and
  `PCRE2_SUFFIX` pastes it into every exported name
  (`src/pcre2.h.generic:1064`).
* **`PCRE2_STATIC`** follows the linkage this build produced, on that same one
  of the two lines, so a Windows static archive is never bound through the
  `extern __declspec(dllimport)` declarations the header writes when it is not
  defined (`src/pcre2.h.generic:56-63`).
* **`__int128_t` and `__uint128_t`** are restated in `translate.h` under
  `#if defined(__SIZEOF_INT128__)`. They are the **compiler's** typedefs, no
  header declares them, and the guard is the compiler's own statement that this
  target has the `__int128` extension, so a target without it declares neither.
  C permits a typedef to be restated for the type it already denotes.
* **`PCRE2_EXP_DECL`** is defined on exactly one compile line: `src/pcre2posix.c`
  compiled **into** the core artifact, on COFF, as `extern`. `pcre2.h` reads
  `_WIN32` and `PCRE2_STATIC` and nothing else, and that file includes
  `pcre2.h` but not `pcre2_internal.h` — the header that gives the core's own
  sources a decoration of their own (`src/pcre2_internal.h:154-160`;
  `src/pcre2_tables.c:50-52` skips it under `PCRE2_PCRE2POSIX`). So inside the
  DLL the wrapper's calls to `pcre2_compile_8` and its neighbours would arrive
  `extern __declspec(dllimport)`: an import from the DLL that defines them,
  which LLD reports as `locally defined symbol imported` and the build turns
  into a failure. `PCRE2_EXP_DECL` is upstream's own override for exactly this
  (`src/pcre2.h.generic:51-52`). In the separate `pcre2-posix` artifact the same
  calls really do cross into another DLL, and there they stay `dllimport`; that
  is upstream's arrangement (`CMakeLists.txt:1011-1013`), and this package keeps
  both answers because both are correct for the artifact they are in.

**Which front end reads that header.** `zig translate-c` parses with Aro, and
Aro preprocesses as well as parses, so the aggregate can be read either way
round. `aggregateRoute` picks per target (`build.zig:712-714`):

| The target's C library | Front end | What happens |
|---|---|---|
| GNU libc — `target.result.isGnuLibC()` | **Aro alone** | `translate.h` goes to `zig translate-c` as it stands; Aro preprocesses and parses it, and the declaration macros are on the translation line |
| every other target | **the target's own C preprocessor, then Aro** | `zig cc -E -dD -fno-blocks -x c` expands `translate.h` first, with the same `-target`, the same `-I` header directory, the same `-DPCRE2_CODE_UNIT_WIDTH` and the same `-DPCRE2_STATIC` as the C core's own compile line, and Aro parses what that produced |

Why the split exists, and why neither half of it is a repair to the header, is
in [`FORK-NOTES.md`](FORK-NOTES.md) § 17-20. Both routes read the same header
copy on the same include path with the same two macros; the choice is only
about **which preprocessor has to understand the target's C library**. `-dD`
keeps the `#define` lines in the file Aro parses, so `pcre2.c.PCRE2_INFO_CAPTURECOUNT`
and `pcre2.c.PCRE2_CONFIG_VERSION` still reach Zig as constants, and `-fno-blocks`
puts the two front ends in one dialect — which is what keeps the Darwin C
library's six block-pointer declarations out of a translator that has no block
pointers.

## Build modes

* **Bundled, the default.** Upstream's C is compiled from this repository for
  whatever target is being built. No download, no system include path, no
  installed library behind your back.
* **System mode, `-fsys=pcre2-8`.** Nothing in this tree is compiled. The facade
  links an installed `libpcre2-8` and translates the **installed** `<pcre2.h>`
  by angle brackets, so the declarations come from the header that ships with
  the library being linked rather than from the 10.49 copy under `src/`.
  `use_pkg_config = .no`: the linker name `libpcre2-8` is what `-l` resolves,
  and the `.pc` file is named after the library, not the project. The mode
  refuses a foreign `-Dtarget` and a non-8-bit width. The fixtures are pinned to
  10.49 by construction, so a test run against a different installed release
  can legitimately differ on a compile error code, an offset or a message; read
  such a difference against the version the machine reports, and never fix it by
  loosening a fixture. It **has** now been run here, against an installed
  **10.45**; [Verification status](#verification-status) reports what it answered,
  including the single fixture case that differs and why.
* **`-Dlinkage`, default dynamic on a GNU-libc target and static everywhere
  else.** The same value drives the `PCRE2_STATIC` declaration macro on the C
  compile line and on the translation line, so the declaration decoration and
  the archive that was produced are one fact. It is resolved for the target
  **being built**, so every `zig build check` cell takes its own answer rather
  than the host build's: `wasm32-wasi` is a static archive, not a shared object
  a format with no dynamic loader cannot carry. A value named on the command
  line reaches every cell unchanged, and a cell whose OS has no dynamic linker
  is **refused by name** — it is not compiled as static instead, and it is not
  dropped from the matrix. In system mode `-Dlinkage` names the *kind of
  installed library to bind to* instead, and the `PCRE2_STATIC` macro follows
  it; it defaults to dynamic there, because system mode builds no artifact of
  its own.
* **`-Dcode-unit-width`, default 8.** 16 and 32 build, install, test and smoke
  like 8 does; **nothing in this graph refuses a width**. `zig/root.zig`
  resolves `Surface` from the compiled width, so the facade at width 16 is the
  same declarations instantiated over `u16`, not a set of names that do not
  exist, and `tests.zig` widens or decodes its fixtures into that width's code
  units. Two things the width does change: the primary is **named**
  `libpcre2-16` / `libpcre2-32`, and the POSIX wrapper, `pcre2grep`,
  `pcre2posix_test` and `libpcre2-posix.pc` are absent there — the wrapper is
  8-bit by construction, because `regexec` takes a `char *` subject and
  `rm_so` counts bytes (`src/pcre2posix.h:104-119`). The **translated header
  declares all three widths** in every mode (`src/pcre2.h.generic:1021-1030`),
  and this package's artifact **defines** all three, so the declaration and the
  symbol are the same fact here and not only against upstream's own per-width
  files.
* **`-Dsanitize_c`, default off.** Upstream's own option, passed through.
* **What the default build does and does not execute.** The default install
  step installs the artifacts and **compiles** the smoke program; it does not
  run it. `build.zig:363` hangs the install step on `&smoke.step`, the
  `Compile` step, while the named `smoke` step gets the `Run` step that
  `addRunArtifact` returns at `:362`. So `zig build` and `zig build install`
  execute nothing at all, for any target, and asking for a foreign `-Dtarget`
  costs a cross-compile and no execution. A runtime answer on the host comes
  from `zig build smoke` or `zig build test`, by name; `zig build check`
  compiles the C core, the facade, the tests and the smoke for its six targets
  and runs nothing there either. [Commands](#commands) has the rest.
* **JIT is off and cannot be turned on — and that is not the same claim as
  "the JIT symbols are absent".** Upstream's `-Dsupport_jit` resolved its source
  either from the `deps/sljit` git submodule — which is an empty directory in
  this checkout — or from a network `lazyDependency`, neither of which a
  no-download contract can use. The option and the dependency are gone rather
  than left to fail later, and `SUPPORT_JIT` is 0 in the generated `config.h`.
  `src/pcre2_jit_compile.c` **is** still compiled (`build.zig:114`), and the
  unit is **not** empty after preprocessing: `pcre2_jit_compile` is defined
  outside the `#ifdef SUPPORT_JIT`
  (`src/pcre2_jit_compile.c:14303-14432`), and the all-in-one includes of
  `pcre2_jit_match_inc.h` and `pcre2_jit_misc_inc.h` are at **file scope**
  (`:14439-14440`, after the guard closes at `:14431`), not inside it. Both
  files open an `#ifndef SUPPORT_JIT` arm for their exported definitions, so
  every entry point `src/pcre2.h.generic:846-859` declares is defined in this
  archive and every one of them refuses:

  | Entry point | Defined at | What it answers with JIT off |
  |---|---|---|
  | `pcre2_jit_compile_8` | `src/pcre2_jit_compile.c:14303-14432` | `PCRE2_ERROR_JIT_BADOPTION`, -45, for an ordinary request (`:14391-14392`) and for an option outside `PUBLIC_JIT_COMPILE_OPTIONS` (`:14342-14343`); `PCRE2_ERROR_JIT_UNSUPPORTED`, -68, for `PCRE2_JIT_TEST_ALLOC` (`:14329-14335`) |
  | `pcre2_jit_match_8` | `src/pcre2_jit_match_inc.h:90-96` | `PCRE2_ERROR_JIT_BADOPTION` (`:103`) |
  | `pcre2_jit_free_unused_memory_8` | `src/pcre2_jit_misc_inc.h:106-117` | nothing; it does no work (`:109-110`) |
  | `pcre2_jit_stack_create_8` | `src/pcre2_jit_misc_inc.h:125-134` | `NULL` (`:134`) |
  | `pcre2_jit_stack_assign_8` | `src/pcre2_jit_misc_inc.h:165` | nothing; it does no work (`:169-172`) |
  | `pcre2_jit_stack_free_8` | `src/pcre2_jit_misc_inc.h:187` | nothing; it does no work (`:190-192`) |

  The interpreter is still what runs a match, and `PCRE2_NO_JIT` has nothing to
  turn off. The earlier sentence in this document that claimed the source
  "contributes nothing" and that the raw symbols "are not in the library" was
  wrong on both counts and is replaced here; the claim this package makes is
  only that JIT functionality is disabled, not that its entry points are
  missing.

## Native delivery and packaging

The canonical entry point is [`README.md`](README.md), which carries the
deviations, the matrix and the consumption recipes for Zig, C, the Nix outputs
and `devenv`. What belongs here is the part of that a Zig reader needs:

* **`zig build install --prefix <p>` writes** `<p>/include/pcre2.h`,
  `<p>/include/pcre2posix.h` (width 8 only), `<p>/lib/libpcre2-8.a|.so`,
  `<p>/lib/libpcre2-posix.a|.so` (width 8 only) and `<p>/bin/pcre2test`, plus the
  pkg-config files the build graph generates. It compiles the smoke program and
  runs nothing. At width 16 or 32 the same steps run: the primary is named
  `libpcre2-16` / `libpcre2-32`, and the POSIX wrapper, `pcre2grep`,
  `pcre2posix_test` and `libpcre2-posix.pc` are not installed there.
* **The build graph owns the installed closure** — C flags, source list,
  per-target `config.h`, artifacts, headers, tools, data, licence records and
  pkg-config metadata. `package.nix` names the variant, the width, the CPU
  baseline, the optimization mode and the prefix, and installs nothing of its
  own, so there is one writer per path.
* **`package.nix` is one injected derivation** with `linkage` and
  `codeUnitWidth` as arguments. `flake.nix` exposes `packages.<system>.default`,
  `.static` and `.shared`; `.#default` passes no `-Dlinkage`, so the SDK's own
  policy — dynamic on GNU libc, static elsewhere — applies unforced. The 16-
  and 32-bit widths are the same derivation with `codeUnitWidth` set; neither is
  a named output.
* **`devenv.nix` is the canonical environment**: tools in `packages`, the SDK
  never in it, its variants as lazy `outputs` built by
  `devenv build outputs.static`. Scratch locations follow `HOST_SCRATCH_ROOT`
  only where the caller has not already chosen one, so no committed file names
  a host path and a caller's own scratch is not overridden.
* **Every entry names this repository for itself.** `sdk.build`, `sdk.test`,
  `sdk.test-release-safe`, `sdk.smoke`, `sdk.check`, `sdk.integrity` and
  `sdk.consumer` are devenv **scripts** and keep their dotted spelling —
  `namespace:name` is a rule about task names. Each body changes to this
  directory first, rendered `builtins.toString ./.` and quoted with
  `lib.escapeShellArg`, because `devenv shell -- <name>` runs the entry in the
  *caller's* directory and a `--from path:<sdk>` run's caller is a project
  directory beside the SDK that holds no `build.zig` and no `UPSTREAM.sha256`.
  `sdk.consumer` names `<sdk>/consumer` directly, and a `cd` that fails stops
  the entry instead of leaving it building in the caller's directory. Every
  entry that reaches `zig build` carries the workspace's gate recipe — `-j8`, an
  explicit external `--cache-dir` and `--summary all` — before `"$@"`, which
  still comes last, and each of those is read last-wins, so a caller's own `-j`,
  `--cache-dir`, `--summary` or `-D…` wins over it.
* **`sdk.build` installs off this repository.** It is the one entry that
  delivers an install prefix, and `zig build`'s own default for that is
  `zig-out` beside the build root — inside the source tree, on a volume mount.
  It passes `--prefix "$ZIG_LOCAL_CACHE_DIR/pcre2-install"`, and every entry
  that reaches `zig build` first settles the caches itself, in its own body and
  not only in `enterShell`: the caller's `ZIG_LOCAL_CACHE_DIR` and
  `ZIG_GLOBAL_CACHE_DIR` win untouched, a missing one is filled from
  `XDG_CACHE_HOME`, else from `TMPDIR`, and with the local cache still unnamed
  the entry names the variable that is missing instead of choosing a directory
  of its own. `${…:?}` stays under that as a second refusal, not as a fallback.
  Each command then passes `--cache-dir "$ZIG_LOCAL_CACHE_DIR"`, so Zig never
  falls back to the `.zig-cache` it writes beside `build.zig`: inside this
  checkout for the five SDK-root entries, and a second one inside
  `<sdk>/consumer` for `sdk.consumer`. `sdk.test`,
  `sdk.test-release-safe`, `sdk.smoke` and `sdk.check` run steps that install
  nothing; `sdk.consumer` installs no file either
  (`consumer/build.zig:145-149`). A plain `zig build` run by hand still writes
  `zig-out/`, which stays ignored and out of the package paths.
* **An installed shared program finds this prefix's library and nothing else.**
  `bin/pcre2test`, `bin/pcre2grep`, `bin/pcre2posix_test` and
  `lib/libpcre2-posix.so` carry `$ORIGIN/../lib` (`@loader_path/../lib` on
  Mach-O) as their single search entry and a `DT_NEEDED` naming a soname rather
  than a path, so the tree relocates and Nix will package it. **No installed file
  carries a build-cache directory.** The published module carries the *other*
  entry — the one a dependent's own build cache needs — and is what the test
  binary, the smoke example and `RunTest`'s copy of `pcre2test` are built from;
  see [Importing it](#importing-it).


## External ABI boundaries

These are the conditions under which a consumer's declarations and this
library's definitions describe the same ABI. They are read out of the sources
and the generated `config.h`, not assumed.

* **The header and the library are one revision, and in system mode they are the
  installed pair.** The translated declarations come from the header the core was
  compiled against; `-fsys=pcre2-8` translates the *installed* `<pcre2.h>` by
  angle brackets so the declarations cannot be from a different release than
  the library being linked. Bundled translation of this tree's 10.49 header
  against an older installed library — the thing this mode exists to prevent —
  is exactly what it declines to do.
* **The code-unit width is part of the ABI.** `PCRE2_CODE_UNIT_WIDTH` selects the
  symbol set: `PCRE2_SUFFIX` pastes it into every exported name
  (`src/pcre2.h.generic:1064`), so 8, 16 and 32 are three distinct libraries that
  share one header. A declaration at the wrong width is a link error, not a
  runtime answer. **The typed facade is the selected width's own**, at 8, 16 or
  32, and `test`, `smoke` and `check` run at each; what a width changes is the
  name the artifact is installed under and which non-core tools exist.
* **Static and shared differ in one declaration macro, and only where the header
  reads it.** `PCRE2_STATIC` follows the linkage this build produced. The header
  reads it only under `defined(_WIN32)` (`src/pcre2.h.generic:56-63`), so on ELF
  and macOS the decoration is a fact about the build graph rather than something
  a consumer must pass. `pcre2.h` declares all three widths in every mode, and
  **this package's artifact defines all three**, because it is the union of the
  three upstream width closures; against upstream's own single-width files, or
  against an installed `libpcre2-8`, only that one has symbols behind it.
* **Inside a shared library, "imported" is the wrong answer even on Windows.**
  `dllimport` on a symbol the same DLL defines is what `PCRE2_STATIC` avoids for
  a static archive, and this package has one more place it has to be avoided:
  `src/pcre2posix.c`, which is compiled into the core artifact as well as into
  `pcre2-posix`. It gets `PCRE2_EXP_DECL=extern` there and the header's
  `dllimport` in the separate library, because that is what each one is. A
  consumer that links the **static** library on Windows still has to define
  `PCRE2_STATIC` itself; that part never changed.
* **A DFA result is in the match block; the workspace is scratch.** This is the
  boundary a C consumer of `pcre2_dfa_match` gets wrong first.
  `pcre2_dfa_match_N` passes the `pcre2_match_data`'s own offset vector to its
  matcher as the output (`src/pcre2_dfa_match.c:4062-4063`), and upstream's own
  substring helpers read the result back out of that block
  (`src/pcre2_substring.c:334-341`). The `wscount`-sized buffer is the
  matcher's own working storage and the resumable restart state
  (`:605-606`, `:3486-3489`), and upstream refuses it below 20 with
  `PCRE2_ERROR_DFA_WSSIZE`, -43 (`:3437`). Three consequences: the vector must
  be sized for **every simultaneous match**, not one pair per parenthesis
  (`doc/pcre2_dfa_match.3:33-35`); the pairs are matched substrings and **not**
  capture groups, because this matcher has none (`doc/pcre2.txt:4340-4343`),
  and they arrive **longest first** (`:4352-4360`); and a return of **zero**
  means more were found than fitted, so the vector holds the longest ones and
  the answer is truncated — readable, not complete, and not a failure
  (`:4359-4360`).
* **The name table's layout is width-dependent: `IMM2_SIZE` is not always
  two.** `src/pcre2_intmodedep.h:212-221` defines it as **two** code units at
  width 8, where `GET2` is a big-endian pair, and **one** at width 16 and 32.
  Upstream reaches the name by adding `IMM2_SIZE` to a code-unit pointer
  (`src/pcre2_compile_cgroup.c:142-144`, `:167-175`;
  `src/pcre2_substring.c:498-518`), and entries are sized to the longest name
  plus `IMM2_SIZE` plus one (`src/pcre2_compile.c:5713-5716`) and NUL-padded to
  that size. A consumer that reads a 16- or 32-bit table as bytes lands inside
  a code unit and names a different group every time.
* **Two different "this group did not participate" markers exist, and they are
  not the same value.** In the width surface it is `PCRE2_UNSET` in the offset
  vector (`src/pcre2.h.generic:539`), which is `SIZE_MAX`; in the POSIX wrapper
  it is the literal `-1`, written into **both** ends of the `regmatch_t` and
  into every slot past the ones the match filled (`src/pcre2posix.c:403-408`).
  `-1` is not `PCRE2_UNSET` narrowed. `REG_BADPAT` is likewise the POSIX
  wrapper's fallback rather than its answer for every bad pattern
  (`src/pcre2posix.c:312-319`): `a(b` is `REG_EPAREN`.
* **JIT: the entry points exist and refuse.** With `SUPPORT_JIT` 0 the JIT
  functions are still defined and linked and answer `PCRE2_ERROR_JIT_BADOPTION`
  / `PCRE2_ERROR_JIT_UNSUPPORTED`; a consumer that probes for JIT support must
  call `pcre2_jit_compile` and read the error, not look for an absent symbol. The
  per-entry-point table is in [Build modes](#build-modes).
* **The allocator enters at one place, and memory returns the way it came.**
  10.49's public header declares no `pcre2_set_malloc`-style setter; a custom
  allocator is supplied once to
  `pcre2_general_context_create(malloc_fn, free_fn, memory_data)`
  (`src/pcre2.h.generic:643`, default wiring in `src/pcre2_context.c:110-123`
  and `PRIV(memctl_malloc)` at `:81-97`) and reaches the compile, match and
  convert contexts through the general context. Everything the library returns —
  match data, ovector copies, substring lists, converted patterns — is freed
  with the matching `*_free` **from the same library instance**. This is the one
  boundary that matters most if a consumer ever links this library as a
  separately-loaded image rather than a static archive in its own binary: the
  free has to happen where the allocation happened.
* **A shared build exports the declared API and nothing else.** `PCRE2_EXPORT` is
  `__attribute__((visibility("default")))` and the core is compiled
  `-fvisibility=hidden`, so internals stay internal even in a static archive a
  user links into their own shared library. The six public JIT entry points are
  part of that exported set and are the documented exception to "JIT is off".

## Verification status

**This section is the one current gate table for this package.** Every other
document links here instead of keeping a list of its own, so a state is stated
exactly once. Every state below is read out of the named receipt; **nothing here
is predicted**, and a gate with no receipt is listed as not run rather than
assumed either way.

### The default build, against this tree's own library

These are the bundled configuration — upstream's C compiled from the `src/` in
this repository — on the host target `x86_64-linux-gnu`. No row in this table
involves an installed PCRE2. Each row is one driver run on 2026-10-02 with
`-j8 --summary all --color off`; the machine-readable record of all three is
`local://foundation-cross-test-native-pcre2.json`.

| Gate | Command | State | Receipt |
|---|---|---|---|
| tests (Debug), smoke **and** install — one run | `zig build test smoke install -Doptimize=Debug …` | **pass, exit 0**, 07:04:35Z → 07:04:45Z (10.1 s): `Build Summary: 19/19 steps succeeded; 10/10 tests passed`, then the smoke program's four captures at the hand-worked offsets (`group 2 host: bytes 8..19 = example.org`), `subject without a port: no match, as expected`, `and no capture from the failed attempt is readable`, then `install pcre2-8`, `install pcre2-posix` and `install pcre2test` | `local://foundation-cross-test-pcre2-native-Debug.log` |
| tests (ReleaseSafe) **and** smoke — one run | `zig build test smoke -Doptimize=ReleaseSafe …` | **pass, exit 0**, 07:04:45Z → 07:05:34Z (48.6 s): `Build Summary: 12/12 steps succeeded; 10/10 tests passed`, with the same smoke output | `local://foundation-cross-test-pcre2-native-ReleaseSafe.log` |
| consumer | `cd consumer && zig build run …` | **pass, exit 0**, 07:05:34Z → 07:05:41Z (7.0 s): `pcre2 consumer, linked against 10.49 2026-09-28`, `ERROR[4171] disk full on /dev/sda1 -> ERROR/4171/disk full on /dev/sda1`, `WARN disk nearly full -> WARN/-/disk nearly full` — the `-` is the group that did not take part — and `every line matched with the offsets worked out by hand`; `Build Summary: 9/9 steps succeeded` | `local://foundation-cross-test-pcre2-native-consumer.log` |
| integrity, as of 2026-10-01 | `sha256sum -c UPSTREAM.sha256` | **pass, exit 0**: 59 records, every line `OK` | `local://foundation-expansion-pcre2-immutable-source-integrity-168.log` |
| integrity, driver's current sweep | `sha256sum -c UPSTREAM.sha256` | **red, one line: 58 `OK`, one failing record.** `testdata/foundation-fixtures.zig` no longer matches its digest. **All 58 upstream records verify** | driver sweep; see the note below |

**Read the failing integrity record before calling it a native-byte finding.**
The one record that fails is **this fork's own fixture module**, not an
upstream file, and `UPSTREAM.sha256:27-31` says so in the file's own header and
gives the reason it is pinned at all: the module holds every expected answer the
tests compare against, so a silent edit to it would move the oracle rather than
break a build, and hashing it makes such an edit fail loudly. That is a change
detector for a fork-owned file working as designed.

It fired because this wave edited that module **after** the digest was taken —
the manifest was written 2026-10-02 and the file was modified 2026-10-04 — and
the earlier note here, which said the graph change "touched none of" the files
the record covers, was wrong on exactly that file. Comparing every recorded
digest against the file it names gives 59 records, **58 matching and one not**,
and the one is the fork's own. `src/pcre2_match.c`, `LICENCE.md`, the headers
and the eight `testdata/` oracle files all still verify.

**The fix is to re-derive that single digest, and nothing else.** Not to
re-pin an upstream record, not to delete the failing line, not to widen or
narrow the record's scope, and not to suppress the check — a red record for a
fork-owned file is information, and silencing it would throw away the one thing
the record was added for. The current filtered-package replay belongs to the
driver-owned proof below and would carry the same result.

**Earlier rounds of these gates are history.** The 2026-10-01 receipts
`local://foundation-expansion-pcre2-capture-debug-155.log`,
`…-capture-safe-158.log`, `…-capture-smoke-159.log`, `…-capture-install-160.log`,
`…-capture-consumer-161.log` and `…-installed-C-surface-198.log` describe the
tree **before** `build.zig` grew the aggregate route and `translate.h` grew the
two guarded typedefs. Their counts (`9/9`, `14/14` and `10/10` tests) were
true of that tree and are kept because entries in
[`FORK-NOTES.md`](FORK-NOTES.md) cite them; they are not the current rows.

### The standalone linked consumer, 2026-10-04

The driver ran the consumer package out of tree in both linkages on 2026-10-04,
one command each, with `--prefix` pointed at its own scratch directory and
`PCRE2_TEST_PROVIDER` set for the runtime route. The static run resolved this
build's library. **The shared run did not**, and it exited 0.

| Gate | Command | State | Receipt |
|---|---|---|---|
| consumer, linked static | `cd consumer && zig build run -Druntime=false -Dlinkage=static …` | **pass, exit 0**, 13:20:03Z → 13:20:08Z (5.4 s): `pcre2 consumer, linked library, 8-bit code units`, `pcre2 consumer, linked against 10.49 2026-09-28`, the three captures at the hand-worked offsets, `every line matched with the offsets worked out by hand`, `Build Summary: 17/17 steps succeeded`, and **no loader line at all** | `local://foundation-resumed-pcre2-standalone-linked-static.json` |
| consumer, linked shared | `cd consumer && zig build run -Druntime=false -Dlinkage=dynamic …` | **red, and the exit code does not show it**: exit 0, `Build Summary: 17/17 steps succeeded`, and every hand-worked offset still matched — but the loader printed `…/pcre2-consumer: /lib64/libpcre2-8.so.0: no version information available (required by …/pcre2-consumer)` and the program's own version line answered `linked against 10.45 2025-02-05` | `local://foundation-resumed-pcre2-standalone-linked-dynamic.json` |

**What that is.** The shared run loaded the host's installed PCRE2 instead of
this build's, and every behavioural check still passed, because a 10.45 and a
10.49 agree on the patterns this consumer compiles. The two rows differ only in
`-Dlinkage`, and only the shared one is affected, so the resolution — not the
library and not the program — is what was wrong.

**The cause, and it is one line of policy.** A dependent's program is built out
of a build cache and no `lib/` sits beside it, so it needs the directory the
shared object was really emitted into; the install tree's `$ORIGIN/../lib`
resolves nothing there, and the loader then falls through to the default search
path, where this machine has a `libpcre2-8.so.0` under the same soname. The
published `pcre2` module was built with the install-tree entry
(`Pcre2Options.loader` defaulted to `.install_tree`), so every out-of-tree
linked consumer inherited it. This package's own `test`, `smoke` and
`RunTest` copies never saw it, because each of them was compiled from a
**second, private** facade carrying the build-cache entry — which is why the
library's gates were green and the package's were not.

**The correction.** The published module is now the build-cache flavour, the
private cache facade is gone, and `test`/`smoke` use the published module
directly. Nothing installed is built from that module — `pcre2test`,
`pcre2grep`, `pcre2posix_test` and the `libpcre2-posix` beside them are each a C
translation unit with a module of its own, compiled with `.install_tree` — so
the installed and Nix routes still carry `$ORIGIN/../lib` and nothing else.
This is the arrangement `gmp`, `htscodecs`, `inchi` and `luajit` already use in
this workspace.

**Status: `PENDING-VERIFICATION`.** No gate has run since the change landed, so
the two rows above describe the tree as it was. The re-run the driver owes is in
the pending table below.

### The full gates, all three widths, 2026-10-04

These are the most recent per-width `test` and `smoke` runs, one per code-unit
width, each against that width's own compiled core. `install` is **not** part
of them: `zig build smoke test -Dcode-unit-width=… --prefix <p>` compiles and
links the library and runs both binaries, and the installed closure has its own
pending row below.

**These three ran before the last round of source changes, so read them as the
most recent evidence rather than as a description of the present bytes.**
Afterwards, four API changes landed in `zig/**`: the new
`error.SerializationRefused` and the reshaped `OutOfMemory`, the
non-optional `enumerateCallouts` callback, `substitute` invalidating the
captures it leaves behind, and the corrected character-tables ownership. None of
them changes what these rows measured, and all four change what a **new** run
would exercise. Until a fresh per-width run exists, the honest description of
the current tree is: **the last green at all three widths, and sources that
moved afterwards.**

| Width | Command | State | Receipt |
|---|---|---|---|
| 8 | `zig build smoke test -Dcode-unit-width=8 …` | **pass, exit 0**: `Build Summary: 21/21 steps succeeded; 24/24 tests passed`, then `smoke success` and the same four captures at the hand-worked offsets, plus `subject without a port: no match, as expected` and `and no capture from the failed attempt is readable` | `local://foundation-contract-pcre2-real-UTF8-bytes-and-unset-optional-capture-full-gate.log` |
| 16 | `zig build smoke test -Dcode-unit-width=16 …` | **pass, exit 0**: `Build Summary: 21/21 steps succeeded; 24/24 tests passed`, `smoke success`, and the same four captures reported as `group 2 host: units 8..19 = example.org` — code units, not bytes | `local://foundation-contract-pcre2-real-native-width-16-UTF-validity-category-full-gate.log` |
| 32 | `zig build smoke test -Dcode-unit-width=32 …` | **pass, exit 0**: `Build Summary: 21/21 steps succeeded; 24/24 tests passed`, `smoke success`, with the same four captures | `local://foundation-contract-pcre2-real-native-width-32-UTF-validity-category-full-gate.log` |

**What the two wide rows were before, and what changed.** Two earlier runs of
those same commands reported `23 pass, 1 fail (24 total)` at both widths, with
the failure at `tests.zig:400` in
`a subject this width's validator cannot read is a validity failure`
(`local://foundation-contract-pcre2-real-code-unit-safe-consumer-width-16-full-gate.log`,
`…-32-full-gate.log`). The condition was real; the **classification** was not.
This facade's return mapping covered only the 8-bit UTF codes, so a UTF-16 or
UTF-32 validity failure arrived as `MatchOutcome.failed` instead of
`MatchOutcome.invalid_utf`. That was a defect in the facade, not in a fixture,
and it is fixed by widening the mapped range to `-28…-3` and `-36` — UTF-8
`-3…-23`, UTF-16 `-24…-26`, UTF-32 `-27…-28`, and `PCRE2_ERROR_BADUTFOFFSET`
`-36` (`src/pcre2.h.generic:355-400`). **Nothing was loosened to get there**:
the assertion that made it fail is still in the suite, and the tautological
fixture arithmetic and the non-empty-diagnostic assertions that stood beside it
were removed rather than relaxed.

**What these rows are not.** They are three widths on one host, in one
optimize mode, with the **default** linkage. Nothing here is a claim about
static linkage, about the other three optimize modes, about the six-target
`check`, about the 53-platform matrix, about any Nix output, about
`devenv`, or about the **runtime** route — `-Druntime=true` has still never
been executed in this repository, and no runtime-loaded build of the current
tree has a receipt.

### The package proof, and where its current result lives

The current filtered-package result and identity are **driver-owned** and are
deliberately not written here:

* the root ledger `FORKS.json`, `cross_test_wave.materialized_packages.pcre2`;
* `local://foundation-cross-test-package-regression.json`.

That proof runs **after** these documents settle — a package identity is a
digest over what the package ships, and this documentation is part of what it
ships, so a result recorded here would describe a package that no longer
exists. No result and no identity is asserted in this repository; read the two
places above.

The earlier rounds are history, not the current state. Three receipts from
2026-10-01 fetched this tree from an external approved scratch build root,
replayed all 59 records inside the filtered copy and ran its copied consumer
against 10.49 —
`local://foundation-expansion-pcre2-external-driver-package-fetch-328.log`,
`local://foundation-expansion-pcre2-materialized-package-integrity-337.log`,
`local://foundation-expansion-pcre2-materialized-package-consumer-344.log` —
and a later delivery round recorded
`local://foundation-expansion-pcre2-delivery-settled-filtered-package-fetch-453.log`,
`…-delivery-final-package-integrity-467.log` and
`…-delivery-final-package-consumer-468.log`. They prove that source, fixtures
and legal records survived `.paths` at the time they ran, and they are not the
current package identity.


**The cross-target `check` matrix — six commands, six receipts, every one exit
0**, each compiling the C core, `tests.zig` and `smoke.zig` for its target and
running nothing. These are the **corrected** baseline of 2026-10-02 (created
07:23:23Z, finished 08:30:17Z), one target at a time, each cell
`zig build check -Dtarget=<triple> -Doptimize=Debug -j8 --summary all --color off`:

| Target | `Build Summary` | Receipt |
|---|---|---|
| `x86_64-linux-gnu` | 9/9 steps succeeded | `local://foundation-cross-test-final-baseline-pcre2-x86_64-linux-gnu.log` |
| `aarch64-linux-gnu` | 9/9 steps succeeded | `local://foundation-cross-test-final-baseline-pcre2-aarch64-linux-gnu.log` |
| `aarch64-macos-none` | 10/10 steps succeeded | `local://foundation-cross-test-final-baseline-pcre2-aarch64-macos-none.log` |
| `x86_64-windows-gnu` | 10/10 steps succeeded | `local://foundation-cross-test-final-baseline-pcre2-x86_64-windows-gnu.log` |
| `riscv64-linux-gnu` | 9/9 steps succeeded | `local://foundation-cross-test-final-baseline-pcre2-riscv64-linux-gnu.log` |
| `wasm32-wasi` | 10/10 steps succeeded | `local://foundation-cross-test-final-baseline-pcre2-wasm32-wasi.log` |

The same driver run measured **48 cells** — the six targets above for each of
the eight expansion SDKs — and reports **45 success, 2 failed, 0 timeout, 1
refused**; the three non-success cells belong to other SDKs, and all six of
this package's are `success` (`local://foundation-cross-test-final-baseline.json`).

**The three GNU-libc cells were red in the baseline taken before these
corrections. That regression is closed.**
`local://foundation-cross-test-baseline-before-sdk-corrections.json` (created
06:20:42Z, finished 06:32:06Z; **42 success, 5 failed, 0 timeout, 1 refused**
over the same 48 cells) reports `x86_64-linux-gnu`, `aarch64-linux-gnu` and
`riscv64-linux-gnu` **failed**, each `Build Summary: 6/10 steps succeeded` and
each `translate-c 11 errors` on glibc's own `typedef float _Float32`,
`typedef double _Float64`, `typedef double _Float32x`, `typedef long double
_Float64x` and `typedef __float128 _Float128` — `cannot combine with previous
'float' specifier`, eleven errors on `x86_64-linux-gnu` by itself
(`local://foundation-cross-test-baseline-pcre2-x86_64-linux-gnu.log:3-35`, and
the same on the other two). Those three cells are the `isGnuLibC()` route,
where Aro reads the header for itself. Each corrected log now shows
`translate-c success` with nothing but `WriteFile pcre2.h (reused)` beneath it
and **no `preprocess pcre2.h` step at all**
(`local://foundation-cross-test-final-baseline-pcre2-x86_64-linux-gnu.log:11-12`).
The 2026-10-01 receipts `local://foundation-expansion-pcre2-matrix-*-162…167.log`
are the same six targets from the tree before this wave; they are history.

`check` runs nothing, so those six are **compile** evidence: types, symbols,
widths, `link_libc` and the target's own header assumptions. They are not
evidence about a platform's runtime limits — locking, threads, absent syscalls,
an SDK — so this file claims neither that any target works nor that any target is
unsupported.


### System mode, against an installed 10.45

`-fsys=pcre2-8` binds an **installed** library. On this machine that library is
**10.45 2025-02-05**, older than the 10.49 this tree is a fork of. That is the
whole point of the mode, and it is also why its test row is not the bundled one.

| Gate | Command | State | Receipt |
|---|---|---|---|
| tests (Debug) | `zig build test -fsys=pcre2-8 -Doptimize=Debug` | **red, exit 1**: `9 pass, 1 fail (10 total)`. The translation and the link both succeeded against the installed library, the test binary ran, and exactly one fixture case disagreed | `local://foundation-expansion-pcre2-system-10.45-Debug-194.log` |
| smoke | `zig build smoke -fsys=pcre2-8` | **pass, exit 0**: `pcre2 smoke, linked against 10.45 2025-02-05`, the same four captures at the same offsets | `local://foundation-expansion-pcre2-system-10.45-smoke-199.log` |
| consumer | `cd consumer && zig build run -fsys=pcre2-8` | **pass, exit 0**: `pcre2 consumer, linked against 10.45 2025-02-05` | `local://foundation-expansion-pcre2-system-10.45-consumer-200.log` |

### The full 53-platform matrix (`cross-test`)

`zig build check` answers six compile-only questions. `cross-test` answers the
published 53-platform one, and it answers it by running this package's real
test step rather than by compiling it: with no artifact hooks it runs
`zig build test -Dtarget=TARGET` once per target (`cross-test:383-385`), over
the Zig 0.16.0 Tier 1/2 support table (`zig-targets.sh:36-67`). The matrix, the
native/QEMU/Wine/Wasmtime detection and the decision to skip a foreign run are
the harness's; this package contributes the `test` graph and a
`cross-test.profile.sh` of four ordinary Bash variable definitions.

The `test` step is what makes that meaningful here: it attaches a real **run**
artifact (`build.zig:355-356`), so a cell with a runner executes the whole suite — eleven tests at the time of that sweep — and a cell without one still compiles it. When the harness declines to run a
foreign binary it replaces that run step's action with a skip and leaves its
compile dependencies in place (`run_policy.zig:55-57`, `:103-105`), so the cell
is `build_only` — compile evidence, never a pass.

`cross-test.profile.sh` sets `CROSS_BUILD_STEP=test`, `CROSS_BUILD_JOBS=2`,
`CROSS_BUILD_TIMEOUT=1800` and `CROSS_TIMEOUT=600`. It defines no hooks, no
matrix and no host path, every value is a default the command line overrides,
and `CROSS_LIBC_RUNTIMES` is deliberately left to the environment: it names
foreign libc loaders on the machine running the harness, not something this
package knows.

**How to read a count.** The current suite reports `24/24 tests passed`: the
default **8-bit** build and all 24 tests. Historical receipt counts below refer
to the suite at the time of each run — 9, 10, 11 and 15 are all true of their
own trees and none of them is the current number. The suite includes the
fixture-table replay, the facade's own bounds, the name-table order and padding
contract, the version-buffer contract, the ownership transitions, the
capture-lifetime cases, and one test each for MARK, substring copy and list, a
caller's own allocator, the newline convention, glob conversion, a callout,
JIT refusal, substitution, the DFA matcher, serialization and the POSIX
wrapper. No cell may run a subset. The width cannot drift either: the harness
passes `-Dtarget` and nothing else, `-Dcode-unit-width` keeps its default of 8,
and the graph refuses no width at all.

**What is target-dependent here, and how it is resolved.** Everything is
derived from `target.result`, never from the machine configuring the build
(`build.zig:869-939`): `SUPPORT_PCRE2_8` and `SUPPORT_UNICODE` on,
`SUPPORT_JIT` off, `PCRE2_EXPORT` as a visibility attribute, and the limits
and `MAX_NAME_SIZE` from upstream's own CMake template. `linkage` defaults to
dynamic only where the target is a GNU-libc one — `isGnuLibC()` is true only for
`.linux` and `.hurd` with a GNU ABI (`std/Target.zig:2139-2143`) — and static
everywhere else, so the MinGW cells build a static archive and the `PCRE2_STATIC`
declaration macro follows on both the C compile line and the translate-c line
(`build.zig:488-498`, `:571-581`). `HAVE_MEMFD_CREATE`, `HAVE_SECURE_GETENV` and
`HAVE_SETRLIMIT` are read only by `pcre2test.c` and `pcre2grep.c`, neither of
which `test` builds. The interpreted core has no endianness branch: the only
`ENDIAN` test in `src/` is inside the JIT compile unit, and `SUPPORT_JIT` is 0.
`pcre2.unset` is `~@as(usize, 0)`, so it is `SIZE_MAX` on a 32-bit cell and on
a 64-bit one, which is what `PCRE2_SIZE` is in each.

**The 10.45 offset row does not move.** Every cell of this matrix builds this
tree's own bundled 10.49 — `-fsys=pcre2-8` is never passed — so the recorded
`unmatched_closing_parenthesis_is_rejected_at_its_offset` difference is a fact
about an *installed* 10.45 library and is not in scope here. Nothing was
re-pinned, loosened or skipped for it.

**The current cohort.** Epoch **`20261004T221720228710Z-45046`**, per-SDK
receipt **`pcre2-53-target-8.json`**, run at `jobs 8 / build-jobs 8`:
**53 targets — 20 runtime PASS, 33 `build_only`, 0 fail**, driver exit 0,
`source_unchanged: true`, `jobs_honoured: true`. **`build_only` is
compiled-but-not-run and is never a runtime pass.** The split this package
stands on is therefore **20 runtime passes and 33 compile-only cells** — never
"53 targets passed", never "the suite is green on all 53". What the cohort does
**not** prove: no BSD, Darwin, MacCatalyst, Windows or WASI binary from those 33
was executed on this host, so nothing here is a claim about runtime behaviour on
any of them.

The smaller current runs that sit beside that cohort, each read out of its own
receipt, none of them a re-run of another:

| Run | Command shape | State | Epoch / receipt |
|---|---|---|---|
| six-target compile-only baseline | whole-graph `zig build check` across the six `check` targets | **pass: exit 0, `failed: false`, and `runtime_pass_claimed: false`.** It is **compile-only**: a green row here proves this graph compiles for those six targets and says nothing about run time under any exit code | `20261005T014547Z-797a73f2`, `baseline-pcre2-check` |
| native 8-cell wave | `cross-test` over the workspace's eight-cell native set | **8 pass**, no failure recorded. Eight cells, not the published 53 | `20261004T233628757747Z-69351` |
| own-loaded 8-cell wave | the same eight cells with `-Druntime=true`, the provider reached through the platform loader | **8 pass**, on **this repository's own source-built provider** (`independence: own`) | `20261004T232823091897Z-23133` |
| independent external provider | an external PCRE2 provider exercised in place of this tree's own build | **none accepted — a boundary, not coverage.** The external-route wave records **no route carrying `counts_as_external_coverage: true`** (`20261004T232439Z`, `pcre2-index.json`). The only successful route is the own source-built provider above; every external candidate is an expected *refusal* — a library that does not export the surface this header declares. That is the ABI boundary [above](#external-abi-boundaries) rather than a defect | `20261004T232439Z` |
| translated-header generation ordering | `runtime/graph.zig` `generateDispatch` / `createModule`, reached from `build.zig:1381-1388` | **applied; not yet re-gated.** The host/target selection and the selected platform configuration are now established **before** `createModule` is called; an earlier staged arrangement was itself wrong and has been replaced by the correct one. It answers an earlier positive-system **case** that reported **28 undefined-symbol diagnostics from the compiler — one case, 28 diagnostics, not 28 separate cells**; a red result, not an all-PASS one. **No receipt re-runs pcre2 after this fix** | none; applied and unverified |

**Every count above predates that last row.** The fix is in `build.zig`'s
translated-header generation: `build.zig:1381-1388` is the seam — the runtime
branch takes `graph.createModule(b, translate_c, …)` and the linked branch
`translate_c.createModule()` — reached through `runtime/graph.zig:294`
(`createModule`) and `runtime/graph.zig:365-379` (`generateDispatch`, where the
generator's host target is chosen). **No native byte, header, test, fixture,
licence or upstream file changed with it**, and **no cell is promoted to PASS on
the strength of it.**

What follows is the **2026-10-02 sweep and its history**. It is kept because it
is true of its own tree; it is not the current count.

**Status: `OBSERVED`, 2026-10-02 — history, superseded by the cohort above. Run id
`20261002-071302-33056-11212`, generated 07:13:02Z, 53 targets, exit 0,
`bookkeeping_failure: false`.**

```
env -u CROSS_PROFILE \
  ZIG=/home/tmp2/gertullj/cache/zig/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig \
  CROSS_LIBC_RUNTIMES=/home/tmp2/gertullj/scratch/foundation-libs/cross-test-01a0f400/runtime-provision/runtimes \
  taskset -c 56-63 /vol/fob-vol7/mi19/gertullj/.local/bin/cross-test \
    --jobs 2 --build-jobs 4 --build-timeout 3600 \
    --output /home/tmp2/gertullj/scratch/foundation-libs/cross-test-01a0f400/final-current/pcre2
```

Each cell ran `zig build test -Dtarget=TARGET -j4 --summary all --color off
--test-timeout 600s` with the harness's own build runner and the provisioned
libc runtimes. The result is **`20 pass, 0 fail, 33 build_only, 0 partial`**,
and the machine-readable record is
`local://foundation-cross-test-final-current-pcre2.json`.

* **20 cells executed all ten tests**: `x86_64-linux`, `aarch64-linux`,
  `aarch64_be-linux`, `arm-linux`, `armeb-linux`, `hexagon-linux`,
  `loongarch64-linux`, `mips-linux`, `mipsel-linux`, `mips64-linux`,
  `mips64el-linux`, `powerpc-linux`, `powerpc64-linux`, `powerpc64le-linux`,
  `riscv32-linux`, `riscv64-linux`, `s390x-linux`, `thumb-linux`, `thumbeb-linux`
  and `x86-linux`. Every one reports `Build Summary: 10/10 steps succeeded; 10/10
  tests passed`. `local://foundation-cross-test-final-current-pcre2-x86_64-linux.log:1-19`
  is one of them in full, and its graph shows `translate-c success` over a
  `preprocess pcre2.h` step — the extra-front-end route `aggregateRoute` gives a
  target whose C library is not GNU libc, which is the route every cell of this
  sweep's `-Dtarget=<bare triple>` invocation took.
* **33 cells are `build_only`**: every FreeBSD, NetBSD, OpenBSD, Darwin,
  MacCatalyst, Windows and WASI cell. Build exit 0, run `status: unavailable`,
  `reason: runtime_unavailable`. Each log shows the whole graph complete and the
  run step skipped with its compile dependencies left in place, e.g.
  `local://foundation-cross-test-final-current-pcre2-aarch64-macos.log:3-18` —
  `Build Summary: 9/10 steps succeeded (1 skipped)` over `+- run test skipped`,
  with a `translate-c success` that itself ran `preprocess pcre2.h`. **That is
  compile evidence and nothing else**: no BSD, Darwin, Windows or WASM binary
  was executed on this host, and nothing here claims runtime behaviour for them.
* **All 53 targets compiled.** No cell failed at the build, so on every one the
  full 8-bit core was compiled and a translated interface reached Zig.

**The earlier sweeps of this matrix.** They are kept because the corrections are
only legible against them, and because the first one was run against **sources
this wave later changed**.

| Stage | Run id | Result | Tree it measured |
|---|---|---|---|
| `matrix` — the first full sweep | `20261002-040235-43000-5735` | **20 pass, 12 fail, 21 build_only, exit 1** | before the aggregate route existed |
| `corrected` — after the extra front end | `20261002-054414-46667-18828` | **20 pass, 6 fail, 27 build_only, exit 1** | before `-fno-blocks` and the guarded typedefs |
| `final` | `20261002-062101-65281-7993` | **20 pass, 0 fail, 33 build_only, exit 0** | that day's graph |
| `final-current` | `20261002-071302-33056-11212` | **20 pass, 0 fail, 33 build_only, exit 0** | that day's graph — **not** the current one, which has since gained the three-width closure and the width-parameterised facade. See [The current full gates](#the-current-full-gates-all-three-widths-2026-10-04) |

The twelve failures of the first sweep were the nine NetBSD cells,
`mips64-openbsd`, `mips64el-openbsd` and `x86-windows`, and every one was a
`translate-c` failure on the target's **own C library headers**: NetBSD defines
`__BEGIN_PUBLIC_DECLS` and `__END_PUBLIC_DECLS` with `_Pragma`, which Aro
leaves in the token stream, so the trailing `__END_DECLS` of `sys/endian.h`,
`<stdlib.h>` and `<inttypes.h>` stop parsing — `translate-c 25 errors`,
`unknown type name 'pragma'` at `generic-netbsd/sys/endian.h:74`
(`local://foundation-cross-test-matrix-pcre2-aarch64-netbsd.log:6-21`). The six
that survived the next sweep were the four Darwin and MacCatalyst cells, where
Clang's driver had left blocks enabled and the Darwin C library's six `*_b`
block-pointer declarations stop Aro with 23 `expected ')', found '^'` errors at
`any-darwin-any/_stdlib.h:298`
(`local://foundation-cross-test-corrected-pcre2-aarch64-macos.log:6-22`), and
`aarch64-netbsd` and `aarch64_be-netbsd`, where a NetBSD header spells
`__ALIGNBYTES` through `__int128_t` and the translated Zig named an identifier
nothing declared — `use of undeclared identifier '__int128_t'` at
`pcre2_preprocessed.zig:1817` (`local://foundation-cross-test-corrected-pcre2-aarch64-netbsd.log:6-9`).
[`FORK-NOTES.md`](FORK-NOTES.md) § 17-20 gives each of those in the
condition / symptom / fix / targets-bound shape, with its own receipt.


### The 2026-10-04 migration's rows still owed

`PENDING-VERIFICATION` throughout, and the commands stay commands: one row below
has since been answered by a driver receipt and says so in place. The packaging,
the relocated README and the fork licence grant landed with no gate behind them,
and the role that wrote them runs no build, test, smoke, cross-target, Nix or
devenv command. The ABI-boundary documentation has since been **corrected
against the source** — the DFA result path, the name-table width, the four native
frees and the two unset markers were all wrong or missing — but a corrected
document is not a gate. The observed rows are the ones in the sections above:
the three widths, the 2026-10-04 cohort, the 2026-10-05 compile-only baseline
and the two 8-cell waves. **Every one of them predates the applied ordering
fix.**

**Nothing in this table is a runtime result**, and it is written as the commands
the driver owes rather than as an expectation about what they will print.

| Gate | Command the driver owes | State |
|---|---|---|
| static native delivery | `zig build install -Dlinkage=static --prefix <out>` in Debug, ReleaseSafe, ReleaseFast, ReleaseSmall | `PENDING-VERIFICATION` |
| shared native delivery | `zig build install -Dlinkage=dynamic --prefix <out>`, same four modes | `PENDING-VERIFICATION` |
| tests and smoke in both linkages | `zig build test smoke install -Dlinkage=<static\|dynamic>` × four modes | `PENDING-VERIFICATION` |
| consumer, both linkages, after the loader-entry correction | `cd consumer && zig build run -Druntime=false -Dlinkage=<static\|dynamic> …` | `PENDING-VERIFICATION`. The shared row is the one that was red: it answered 10.45 from `/lib64/libpcre2-8.so.0` while exiting 0. See [The standalone linked consumer](#the-standalone-linked-consumer-2026-10-04) |
| installed shared closure's loader entry | after `zig build install -Dlinkage=dynamic --prefix <out>`, `readelf -d <out>/bin/pcre2test` — one `(RUNPATH)` of `$ORIGIN/../lib`, `DT_NEEDED libpcre2-8.so.0` and `libpcre2-posix.so.3`, and no build-cache directory in either — then run `<out>/bin/pcre2test` from a directory that is not the build tree | `PENDING-VERIFICATION`. The correction moved the *published* module to the build-cache entry; the installed programs are compiled from modules of their own and were not touched, which is a source reading and not an observation |
| 16- and 32-bit **install** | `zig build install -Dcode-unit-width=16 --prefix <out>`, then `=32` | `PENDING-VERIFICATION`. The `test` and `smoke` runs at both widths are observed above and are recorded there; `install` is a different command and has no receipt |
| runtime route, all four linkage × runtime combinations | `zig build -Druntime=true …` plus a program that calls `pcre2.load`, at each of the four linkages | `PENDING-VERIFICATION`, and narrower than it was. The driver's own-loaded 8-cell wave `20261004T232823091897Z-23133` recorded **8 pass** on this graph's runtime-loaded route, against this repository's own source-built provider (`independence: own`) — recorded in [the 53-platform section](#the-full-53-platform-matrix-cross-test). What still has no receipt is the **four linkages** and any **foreign** provider. A foreign provider would in any case have to be one file exporting all three widths, because the translated header declares all three |
| installed-C consumer | compile, link and run a C program against an **installed** prefix, both linkages, plus the POSIX wrapper's `REG_NOMATCH` | `PENDING-VERIFICATION`; the workflow that runs this has never executed here either |
| six-target `check` | `zig build check -Dtarget=<triple>` for each of the six, on the current tree | **answered as a compile-only row**, epoch `20261005T014547Z-797a73f2`, receipt `baseline-pcre2-check`: exit 0, `failed: false`, `runtime_pass_claimed: false`. It is recorded in [the 53-platform section](#the-full-53-platform-matrix-cross-test) and remains compile evidence; the 2026-10-02 baseline is the earlier tree |
| integrity, after re-deriving the fixture digest | `sha256sum -c UPSTREAM.sha256` | `PENDING-VERIFICATION` and **currently red**. The driver's sweep reports 58 `OK` and one failing record, `testdata/foundation-fixtures.zig`, because this wave edited that module after its digest was taken. All 58 upstream records verify. The fix is to re-derive that one digest; see the note above |
| Nix outputs | `nix build .#static`, `.#shared`, `.#default`; inspect each output's installed closure and `nix-store --query --references`; and evaluate the 16- and 32-bit widths through `package.nix` with `codeUnitWidth` set | `PENDING-VERIFICATION` |
| Nix pkg-config metadata | `pkg-config --cflags --libs libpcre2-8` and `libpcre2-posix` against a built output, static and shared | `PENDING-VERIFICATION` |
| devenv environment | `devenv shell`, then `devenv sdk.build`, `devenv sdk.test`, `devenv sdk.test-release-safe`, `devenv sdk.smoke`, `devenv sdk.check`, `devenv sdk.integrity`, `devenv sdk.consumer`, and `devenv build outputs.static` / `outputs.shared` | `PENDING-VERIFICATION` |
| `nix develop` parity | the same commands through the flake's dev shell | `PENDING-VERIFICATION`; devenv is canonical |
| fetched filtered Zig consumer | a `zig build` from a real build root against the fetched package | driver-owned; see [The package proof](#the-package-proof-and-where-its-current-result-lives) |

The `README.md` matrix is the same list in the fork's canonical order; this
table is the one place the commands are written out, so that a driver reading
either file sees the same pending set.

### Not run

| Gate | Why it is not in a table above |
|---|---|
| `zig build test -fsys=pcre2-8 -Doptimize=ReleaseSafe` | system mode was exercised in Debug only; no ReleaseSafe system-mode receipt exists |
| `.github/workflows/verify.yml` | this repository's CI has never been executed here, so nothing about it is claimed |
| a **new** installed-C-surface, installed-C or `-fsys=pcre2-8` run | this wave changed the **bundled** translation route only. The installed-C program and the three system-mode rows above are the 2026-10-01 receipts; they were not re-run, so nothing new is claimed about an installed 10.45 or about an installed C artifact |
| **runtime** behaviour on the 33 foreign cells | each compiled and was not executed — the harness reported `runtime_unavailable` for every one — so compile-only is all that exists |
| the current filtered-package proof | it runs after these documents settle; its result and identity are driver-owned. See [The package proof](#the-package-proof-and-where-its-current-result-lives) |
| any pcre2 run **after** the applied translated-header ordering fix | the same 53-target cohort, the six-target baseline and both 8-cell waves, re-run | **not run.** No receipt re-runs this package after the fix, so every count in this section is evidence about the tree as it stood before it. The applied fix is a source fact, not a gate result |

### The one system-mode failure, in full

`every known answer in the fixture table holds` failed at `tests.zig:69` —
`expectEqual(expected.offset, rejection.offset)` — **expected 1, found 0**. The
case is `unmatched_closing_parenthesis_is_rejected_at_its_offset`, pattern `)`.
Upstream's own `pcre2test` output for 10.49 prints *"Failed: error 122 at offset
1: unmatched closing parenthesis"* (`testdata/testoutput2:395-396`), and 122 is
`ERR22` (`src/pcre2_compile.h:53-60`). The **error number and the message
matched**; only the byte offset differed, 10.45 answering 0 where 10.49 answers
1. It is reported as it came out.

* **It is not an ABI or header-mixing fault.** The same receipt shows
  `translate-c success` and `compile test Debug native success`, so the
  installed `<pcre2.h>` was translated and the installed `libpcre2-8` was
  linked and run. A binding fault fails at the compile or the link; this one
  reached a single assertion about a single number.
* **Nothing was done to the fixture.** It was not re-pinned to 10.45, not
  loosened, not skipped and not hidden, and no result was invented for it. The
  fixture table is transcribed from upstream's 10.49 `testdata/` and is pinned
  to 10.49 by construction, which is exactly what makes a disagreement with
  another release a **behavioural difference between two versions** rather than
  a defect here.
* **What is known about the cause, and how far.** This repository carries
  upstream's `ChangeLog`, whose entry 13 of the **10.47** section
  (`ChangeLog:164`, `:220-221`) reads *"(#756) Improved error offsets and
  diagnostics for syntax errors during pattern compilation"*, while 10.46's
  only entry is a security fix (`ChangeLog:243-252`). A compile-error-offset
  change between 10.45 and 10.49 is therefore documented in this tree's own
  bytes, and 10.47 is the release that record names. The **precise** cause — the
  line of 10.45's `pcre2_compile.c` that put the offset of a one-byte pattern's
  unmatched `)` at 0 — is **not** identified here, because that source belongs to
  10.45 and this tree carries only 10.49's. Nothing stronger than that is
  available from this repository, so nothing stronger is claimed.
* **What is not claimed at all.** No assertion is made that every installed
  release produces identical outputs, or that this fixture would pass against
  some other release. The native **10.49** suite is green end to end; the 10.45
  run is a recorded cross-release observation, not a parity proof.

### Notes that apply to every row

* **Publication.** This package is **not published** — no registry entry, release
  or mirror. The earlier local filtered-package rounds exercise `.paths`,
  integrity and the copied consumer; they are not a registry-resolution or
  publication proof, and the current package result lives in the driver-owned
  places named above.
* **Which rows share which tree state.** **No current row describes the bytes as
  they stand now.** The one applied change — the translated-header generation
  ordering at `runtime/graph.zig` `generateDispatch` / `createModule`, reached
  from `build.zig:1381-1388` — postdates **every** receipt in this section: the
  2026-10-02 native runs and their `check` baseline, the `final` and
  `final-current` sweeps, the 2026-10-04 cohort `20261004T221720228710Z-45046`
  and the 2026-10-05 baseline `20261005T014547Z-797a73f2`. The 2026-10-01
  receipts (155 through 200, 328, 337, 344, 453, 467, 468), the 2026-10-02
  system-mode receipts and the `matrix`-stage receipts of 04:02Z describe **still
  earlier** trees and are cited as history wherever they appear.
* **A receipt describes the files as they stood when it was produced.**
  Receipt 117's `9 total` and the older `10/10` rows are historical counts.
  The current suite has **11** tests. The eleven earliest receipts from
  2026-10-01 are listed in [`FORK-NOTES.md`](FORK-NOTES.md) § 0 with what each
  one proved, including the five that failed at *configure* time and therefore
  say nothing at all about the library, the tests or the consumer.
* **The CI workflow is described, not exercised.** `verify.yml` is this fork's
  own file and has never run here. Its per-target `check` jobs are the same six
  compile-only cells the table above reports, run here by hand rather than by
  the workflow.


## See also

The gate states live in [Verification status](#verification-status) above and
nowhere else; each document below links there rather than restating them.

* [`README.md`](README.md) — **this fork's canonical entry point**: the
  native-source and native-build deviations, the build/run/test matrix in the
  contract's order, and consumption from Zig, from C against an installed
  prefix, through the Nix outputs, and through `devenv`.
* [`README.upstream.md`](README.upstream.md) — upstream's own README, byte for
  byte.
* [`FORK-LICENSE.md`](FORK-LICENSE.md) — the grant for the fork-authored files,
  the owner's authorization behind it, and the terms verbatim.
* [`NOTICE.md`](NOTICE.md) — attribution, the licence/data split, every file
  this fork adds or edits.
* [`UPSTREAM.md`](UPSTREAM.md) — the pin, what is compiled and with which
  switches, what was removed and why, the archive receipt, and the sync
  procedure.
* [`UPSTREAM.sha256`](UPSTREAM.sha256) — 59 replayable digests: the native
  sources, the headers, the licence texts, the oracle bytes, and this fork's own
  fixture module, which the file's own header pins on purpose.
* [`CHANGELOG.md`](CHANGELOG.md) — numbered fork-only divergences.
* [`FORK-NOTES.md`](FORK-NOTES.md) — the problems met, in the shape a later
  wave can reuse.
