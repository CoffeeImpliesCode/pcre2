# pcre2 — Perl-compatible regular expressions in Zig, over upstream's C

This package compiles **PCRE2Project/pcre2 at tag `pcre2-10.49`, commit
`6f9d7c1373262c541324a16a358785b33ef116cf`** — upstream's own C sources, byte
for byte, from the `src/` directory in this repository — into a C library,
translates upstream's public `pcre2.h` for the 8-bit width, and publishes a Zig
facade over that translation.

The library it builds is upstream's **full 8-bit core with Unicode support, JIT
off**: 31 translation units including the interpreter (`pcre2_match.c`), the DFA
matcher (`pcre2_dfa_match.c`), the whole Unicode property machinery
(`pcre2_ucd.c`, `pcre2_extuni.c`, `pcre2_script_run.c`, `pcre2_xclass.c`,
`pcre2_valid_utf.c`, `pcre2_ord2utf.c`), the compiled-in UCP table
(`pcre2_tables.c`) and the generated character tables
(`pcre2_chartables.c.dist`, compiled as `pcre2_chartables.c`). The list is
explicit in `build.zig:90-121` rather than globbed, so a new upstream unit
cannot enter the archive without a decision. Two further artifacts are built
from the same tree: `pcre2-posix` from `src/pcre2posix.c` and `pcre2test` from
`src/pcre2test.c`.

Nothing here reimplements the engine. Every capture this package reports is
produced by a call into a compiled upstream translation unit, and the raw C
surface is reachable directly through `pub const c`.

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
| `zig build` | compiles the 31 core units, installs the `pcre2-8` library (dynamic by default on a GNU-libc target, static otherwise), the `pcre2.h` header, `pcre2-posix` with `pcre2posix.h`, and `pcre2test` into `zig-out/`, and compiles the smoke program |
| `zig build test` | runs `tests.zig`: the 15 known answers from the fixture table, the bounds the facade owns, the version-buffer contract, and the capture-lifetime cases |
| `zig build test -Doptimize=ReleaseSafe` | the same suite with the optimizer on, which is where a bounds mistake that Debug catches can hide |
| `zig build smoke` | runs `smoke.zig`, which prints each capture, compares it with a byte offset worked out by hand, and exits non-zero on any mismatch |
| `zig build check` | compiles the C core, the translated interface, `tests.zig` and `smoke.zig` for **all six** required targets, running nothing |
| `zig build check -Dtarget=<triple>` | the same for exactly one target |
| `cross-test` | compiles **and runs** this package's `test` step over the full published 53-platform Zig 0.16.0 matrix, one `zig build test -Dtarget=…` per target. Settings come from `cross-test.profile.sh`; see [The full 53-platform matrix](#the-full-53-platform-matrix-cross-test) |
| `zig build test -fsys=pcre2-8` | the same tests against an **installed** libpcre2-8 and the **installed** `<pcre2.h>` |
| `zig build smoke -fsys=pcre2-8` | the smoke program against an installed library |
| `cd consumer && zig build run` | the same library, consumed by a package that did not write it |
| `sha256sum -c UPSTREAM.sha256` | replays the immutable-source, licence and oracle-byte record |

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

The raw C surface is the same module: `pcre2.c.pcre2_dfa_match_8`,
`pcre2.c.pcre2_substitute_8`, the serialization calls, and the 16- and 32-bit
declarations are all present, because `src/pcre2.h.generic:1021-1028` emits all
three widths. The typed facade deliberately does not wrap them.

## Using it

```zig
const std = @import("std");
const pcre2 = @import("pcre2");

pub fn main() !void {
    // Which release this binary is linked against. The buffer is yours and
    // the answer is a window on it, so nothing is allocated and the string
    // is still valid at the next line. Ask for the capacity first if you
    // want to size it from the answer rather than guess.
    var version_buffer: [64]u8 = undefined;
    const version = try pcre2.version(&version_buffer);
    std.debug.print("linked against {s}\n", .{version});

    // A compile rejection is a value, not an error: you usually want the code
    // and the byte offset to show the user.
    var regex = switch (try pcre2.Regex.compile(
        "^(?<scheme>[a-z][a-z0-9+.-]*)://(?<host>[^/:]+):(?<port>[0-9]{1,5})$",
        .{},
    )) {
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
    var match_data = try pcre2.MatchData.create(&regex);
    defer match_data.deinit();
    var context = try pcre2.MatchContext.init();
    defer context.deinit();
    context.setMatchLimit(1_000_000);

    const subject = "https://example.org:8443";
    switch (try regex.match(subject, 0, .{}, &match_data, &context)) {
        .matched => {},
        // A resource refusal is not a non-match, and a caller who chose the
        // subject needs to be able to tell them apart.
        .match_limit, .depth_limit, .heap_limit => return error.MatchRefused,
        else => return error.NoMatch,
    }

    // Captures are byte ranges into *your* subject. Nothing is copied.
    const host_group = regex.numberForName("host") orelse return error.NoSuchName;
    const range = (try match_data.groupRange(host_group)) orelse return error.Unset;
    const host = (try match_data.group(host_group)).?;
    std.debug.print("host is {s} at bytes {d}..{d}\n", .{ host, range.start, range.end });

    // A group that did not take part, and a failed attempt, are both "no
    // range" — never stale offsets describing an earlier subject.
    for (0..regex.captureCount() + 1) |i| {
        const n: u32 = @intCast(i);
        if (try match_data.group(n)) |text| std.debug.print("  {d}: {s}\n", .{ n, text });
    }
}
```

`smoke.zig` is the runnable version of this with every expected byte offset
checked rather than merely printed, and `consumer/src/main.zig` is a structured
log reader across a package boundary.

## The API

Everything the facade names is read out of upstream's own declarations, and each
declaration's comment in `zig/root.zig` cites the header line it came from.

### Compiling and matching

| Declaration | What it is |
|---|---|
| `Regex.compile(pattern, CompileOptions) Error!CompileOutcome` | `pcre2_compile_8`. A malformed pattern is a value (`.rejected`), not an error; only a failed allocation is |
| `Rejection{ code, offset, text }` | upstream's compile error number (100 + an index, `src/pcre2_compile.h:53-54`), the byte offset in the pattern, and upstream's own sentence |
| `Regex.captureCount() u32` | `PCRE2_INFO_CAPTURECOUNT`, the **highest** group number, so a pattern with no groups answers 0 and there are `captureCount() + 1` groups counting group 0 |
| `Regex.nameCount() u32` | `PCRE2_INFO_NAMECOUNT` — how many names the pattern declared. A count, not a group number |
| `Regex.nameAt(index) ?Name` | one entry of the compiled name table, **in alphabetical (name) order**, or null past the end. The index is a table position, not a group number; the `Name.name` slice borrows the compiled block |
| `Regex.nameForNumber(number) ?[]const u8` | the name bound to a group number, or null. A scan, because the table is in alphabetical order rather than group order, so the answer is not at a position `number` can index into |
| `Regex.numberForName(name) ?u32` | the group number a name is bound to, or null when the pattern has no such name. A name longer than `max_name_length` is refused without a lookup, because no pattern this fork accepted can have one |
| `Regex.raw() *const c.pcre2_code_8` | the compiled block itself, for an entry point this facade does not wrap. Still owned by the `Regex` |
| `Regex.match(subject, start_offset, MatchOptions, *MatchData, ?*MatchContext) Error!MatchOutcome` | `pcre2_match_8`. The subject is borrowed; the offsets are byte offsets into it |
| `CompileOptions`, `MatchOptions` | packed structs of `bool` with `= false` defaults, so `.{ .{} }` is upstream's default and a partial literal is valid. `toBits()` is the only conversion direction, so a bit this file does not name cannot be set |

### Reading a result

| Declaration | What it is |
|---|---|
| `MatchOutcome.matched` | `pcre2_match_8` returned zero or more; the captures may be read |
| `MatchOutcome.no_match` | `PCRE2_ERROR_NOMATCH`, -1 (`src/pcre2.h.generic:350`). An ordinary negative answer, not a failure and not an error |
| `MatchOutcome.match_limit` / `.depth_limit` / `.heap_limit` | -47, -53, -63: the ceilings were reached. The pattern may well match; the work was refused |
| `MatchOutcome.invalid_utf{ code, text }` | -3…-23 and -36: a UTF validity failure, with upstream's own number and sentence |
| `MatchOutcome.failed{ code, text }` | any other negative return, with its number. Nothing is flattened into a generic failure |
| `MatchData.groupRange(n) Error!?Group` | `{ start, end }` byte offsets into the subject, or null when there is no range |
| `MatchData.group(n) Error!?[]const u8` | the captured bytes, or null on the same two conditions. A window on your subject, not a copy |
| `MatchData.startOffset() usize` | where the match started, or the offset of the first malformed code unit after a validity failure. **Not** meaningful after `no_match` or a ceiling |
| `MatchData.subject` | the subject the most recent attempt used, borrow |
| `MatchData.captureCount() u32` | how many groups the block can report, one more than the pattern's highest |
| `Text{ bytes, len }`, `Text.slice()` | upstream's own message, without the terminating NUL |

### Resource ceilings, and the library's own identity

| Declaration | What it is |
|---|---|
| `MatchContext.init() Error!MatchContext` | a context holding upstream's current defaults |
| `MatchContext.setMatchLimit / setDepthLimit / setHeapLimit` | the three ceilings; reaching one is a `MatchOutcome` case, not an error |
| `version(buffer: []u8) Error![:0]const u8` | the version string the **linked** library reports, written into your buffer and returned as a window on it |
| `pub const c` | the complete translated `pcre2.h` for this build — all three widths, DFA, substitute, serialization |
| `pub const Error` | the closed set below |
| `pub const unset: usize` | `PCRE2_UNSET`, `src/pcre2.h.generic:539` |
| `diagnostic_buffer_size = 128` | how much message is kept; a longer one is truncated and `Text.len` says so |
| `max_name_length = 128` | `MAX_NAME_SIZE`; `pcre2_compile.c:2671` refuses a longer name, so no accepted pattern has one |

### The error set

`Error` has seven members and each is a comparison this package actually made:

| Error | When |
|---|---|
| `OutOfMemory` | a PCRE2 entry point that can only fail by failing to allocate returned NULL: `pcre2_compile` with error 121, `pcre2_match_data_create_from_pattern_8`, `pcre2_match_context_create_8` |
| `PatternInfoUnavailable` | `pcre2_pattern_info_8` refused one of the four queries this package makes once, at compile time. The block is released rather than leaked |
| `StartOffsetOutOfRange` | the start offset is past the end of the subject. Checked before any C runs, because PCRE2 would answer the same condition with `PCRE2_ERROR_BADOFFSET` from inside the matcher |
| `NoSuchGroup` | the group number is not below `MatchData.captureCount()`. PCRE2's own substring helpers would index its offset vector past the end |
| `OvectorTooSmall` | the pattern's capture count does not fit the vector the block was given. `pcre2_match_data_create_from_pattern_8` clamps the pair count to `UINT16_MAX` and says nothing (`src/pcre2_match_data.c:57-58`), so the clamp is compared against what the pattern needs instead |
| `VersionBufferTooSmall` | your buffer is shorter than the size the library says it needs. Checked **before** the call that writes, because `pcre2_config_8` takes a `void *` and cannot know the capacity |
| `VersionUnavailable` | the library declined the `PCRE2_CONFIG_VERSION` query instead of answering it. There is no placeholder string: substituting one would report a release the archive was never built with |

## Ownership and lifetimes

* **`Regex` owns the `pcre2_code`** and releases it in `deinit`. A second call
  does nothing. Copying the struct copies the pointer, so there is exactly one
  owner; `deinit` takes a mutable pointer and clears it.
* **`MatchData` and `MatchContext` are owned separately** and released by their
  own `deinit`. `Regex.match` never frees your `MatchData`.
* **No Zig allocator is handed to PCRE2, no general context is created, and no
  global allocator hook is installed.** PCRE2 allocates these blocks with
  `malloc` and frees them with its own `free`; the Zig test framework therefore
  cannot supply a leak oracle for them, and the ownership test in `tests.zig`
  checks the transition (each owner holds null, a second `deinit` is the same
  no-op) rather than pretending to observe a free.
* **Capture ranges are byte offsets into the subject you passed.** `MatchData`
  borrows that slice and never copies it, so a capture is a window on your own
  buffer: writing through it is visible through the capture, and a capture must
  not outlive its subject.
* **A failed or refused attempt leaves the block describing nothing at all.**
  PCRE2 keeps the offset vector of the previous match across a failed attempt
  (`doc/html/pcre2api.html:3330-3334`), and those offsets describe a subject you
  may no longer be holding. `Regex.match` therefore clears its own validity
  state for **every** attempt and sets it only when `pcre2_match_8` returned
  zero or more, so `groupRange` and `group` answer null until one of them
  matches. Group 0 is no more readable than a capture. The raw C escape hatch
  is still there for a caller who wants upstream's own behaviour.
* **`startOffset()` is the one field that outlives a failed attempt.** Every
  negative return other than a validity failure leaves it untouched, including
  the two early returns at `src/pcre2_match.c:7270-7279`, so do not read it
  after `no_match`, `match_limit`, `depth_limit` or `heap_limit`.
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
  **longest** name in the pattern, plus the two group-number bytes and a
  terminator (`src/pcre2_compile.c:5713-5716`,
  `src/pcre2_compile_cgroup.c:167-175`), so a short name is followed by NUL
  padding rather than by the next entry. The `Name.name` slice is a borrow
  from that block: valid only while the `Regex` lives, and not NUL-terminated
  in the returned slice. Use `nameForNumber` or `numberForName` rather than
  depending on the table's order.

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

**Which front end reads that header.** `zig translate-c` parses with Aro, and
Aro preprocesses as well as parses, so the aggregate can be read either way
round. `aggregateRoute` picks per target (`build.zig:698-700`):

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
  the archive that was produced are one fact. In system mode `-Dlinkage` names
  the *kind of installed library to bind to* instead, and the `PCRE2_STATIC`
  macro follows it; it defaults to dynamic there, because system mode builds no
  artifact of its own.
* **`-Dcode-unit-width`, default 8.** 16 and 32 build and install upstream's
  library of that width, and the facade steps then **fail with that stated**
  rather than passing empty. `PCRE2_SUFFIX` pastes the width into every exported
  name (`src/pcre2.h.generic:1064`), so a facade over the 16-bit build would be
  a different set of functions, not a different configuration of the same ones.
* **`-Dsanitize_c`, default off.** Upstream's own option, passed through.
* **JIT is off and cannot be turned on.** Upstream's `-Dsupport_jit` resolved
  its source either from the `deps/sljit` git submodule — which is an empty
  directory in this checkout — or from a network `lazyDependency`, neither of
  which a no-download contract can use. The option and the dependency are gone
  rather than left to fail later, `SUPPORT_JIT` is 0 in the generated
  `config.h`, and `src/pcre2_jit_compile.c` contributes nothing to the archive.
  The raw JIT symbols are not in the facade because they are not in the library.

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
| integrity | `sha256sum -c UPSTREAM.sha256` | **pass, exit 0**, 2026-10-01: 59 records, every line `OK` | `local://foundation-expansion-pcre2-immutable-source-integrity-168.log` |

**The integrity row is the one row here that predates this wave's graph
change.** `UPSTREAM.sha256` covers upstream's own bytes and this fork's fixture
module, none of which the graph change touched, so the record still describes
the same 59 files — but the replay itself has not been re-run since 2026-10-01,
and the current filtered-package replay belongs to the driver-owned proof
below.

**Earlier rounds of these gates are history.** The 2026-10-01 receipts
`local://foundation-expansion-pcre2-capture-debug-155.log`,
`…-capture-safe-158.log`, `…-capture-smoke-159.log`, `…-capture-install-160.log`,
`…-capture-consumer-161.log` and `…-installed-C-surface-198.log` describe the
tree **before** `build.zig` grew the aggregate route and `translate.h` grew the
two guarded typedefs. Their counts (`9/9`, `14/14` and `10/10` tests) were
true of that tree and are kept because entries in
[`FORK-NOTES.md`](FORK-NOTES.md) cite them; they are not the current rows.

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
artifact (`build.zig:341-342`), so a cell with a runner executes all ten tests
and a cell without one still compiles them. When the harness declines to run a
foreign binary it replaces that run step's action with a skip and leaves its
compile dependencies in place (`run_policy.zig:55-57`, `:103-105`), so the cell
is `build_only` — compile evidence, never a pass.

`cross-test.profile.sh` sets `CROSS_BUILD_STEP=test`, `CROSS_BUILD_JOBS=2`,
`CROSS_BUILD_TIMEOUT=1800` and `CROSS_TIMEOUT=600`. It defines no hooks, no
matrix and no host path, every value is a default the command line overrides,
and `CROSS_LIBC_RUNTIMES` is deliberately left to the environment: it names
foreign libc loaders on the machine running the harness, not something this
package knows.

**How to read a count.** A cell that runs reports `10/10 tests passed`: the
default **8-bit** build and the whole of the ten — the fifteen-case fixture
table replay, the facade's own bounds, the name-table order and padding
contract, the version-buffer contract, the ownership transitions and the
capture-lifetime cases. No cell may run a subset. The width cannot drift either:
the harness passes `-Dtarget` and nothing else, `-Dcode-unit-width` keeps its
default of 8, and the graph refuses `test`, `smoke` and `check` outright for
16 or 32 rather than running an empty step (`build.zig:326-342`).

**What is target-dependent here, and how it is resolved.** Everything is
derived from `target.result`, never from the machine configuring the build
(`build.zig:862-925`): `SUPPORT_PCRE2_8` and `SUPPORT_UNICODE` on,
`SUPPORT_JIT` off, `PCRE2_EXPORT` as a visibility attribute, and the limits
and `MAX_NAME_SIZE` from upstream's own CMake template. `linkage` defaults to
dynamic only where the target is a GNU-libc one — `isGnuLibC()` is true only for
`.linux` and `.hurd` with a GNU ABI (`std/Target.zig:2139-2143`) — and static
everywhere else, so the MinGW cells build a static archive and the `PCRE2_STATIC`
declaration macro follows on both the C compile line and the translate-c line
(`build.zig:475-484`, `:557-572`). `HAVE_MEMFD_CREATE`, `HAVE_SECURE_GETENV` and
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

**Status: `OBSERVED`, 2026-10-02. Run id `20261002-071302-33056-11212`,
generated 07:13:02Z, 53 targets, exit 0, `bookkeeping_failure: false`.**

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
| `final` | `20261002-062101-65281-7993` | **20 pass, 0 fail, 33 build_only, exit 0** | the current graph |
| `final-current` — the current state | `20261002-071302-33056-11212` | **20 pass, 0 fail, 33 build_only, exit 0** | the current graph |

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


### Not run

| Gate | Why it is not in a table above |
|---|---|
| `zig build test -fsys=pcre2-8 -Doptimize=ReleaseSafe` | system mode was exercised in Debug only; no ReleaseSafe system-mode receipt exists |
| `.github/workflows/verify.yml` | this repository's CI has never been executed here, so nothing about it is claimed |
| a **new** installed-C-surface, installed-C or `-fsys=pcre2-8` run | this wave changed the **bundled** translation route only. The installed-C program and the three system-mode rows above are the 2026-10-01 receipts; they were not re-run, so nothing new is claimed about an installed 10.45 or about an installed C artifact |
| **runtime** behaviour on the 33 foreign cells | each compiled and was not executed — the harness reported `runtime_unavailable` for every one — so compile-only is all that exists |
| the current filtered-package proof | it runs after these documents settle; its result and identity are driver-owned. See [The package proof](#the-package-proof-and-where-its-current-result-lives) |

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
* **Which rows share which tree state.** The current rows — the three native
  runs of 2026-10-02 07:04Z–07:05Z, the corrected six-target `check` baseline
  finished at 08:30:17Z, and the `final` and `final-current` sweeps of the
  53-target matrix — all describe the graph as it stands now, with
  `aggregateRoute` and the guarded `__int128_t` typedefs in it. The 2026-10-01
  receipts (155 through 200, 328, 337, 344, 453, 467, 468), the 2026-10-02
  system-mode receipts and the `matrix`-stage receipts of 04:02Z describe
  **earlier** trees and are cited as history wherever they appear.
* **A receipt describes the files as they stood when it was produced.**
  Receipt 117's `9 total` is a historical count: the suite has **10** tests, and
  every current row reports `10/10`. The eleven earliest receipts from
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

* [`UPSTREAM.md`](UPSTREAM.md) — the pin, what is compiled and with which
  switches, what was removed and why, the archive receipt, and the sync
  procedure.
* [`UPSTREAM.sha256`](UPSTREAM.sha256) — 59 replayable digests of the native
  sources, the headers, the licence texts, the oracle bytes and the fixture
  module.
* [`NOTICE.md`](NOTICE.md) — attribution, the licence/data split, every file
  this fork adds or edits.
* [`CHANGELOG.md`](CHANGELOG.md) — numbered fork-only divergences.
* [`FORK-NOTES.md`](FORK-NOTES.md) — the problems met, in the shape a later
  wave can reuse.
