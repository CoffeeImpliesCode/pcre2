# Zig facade API

The `pcre2` module exposes a typed facade over the translated C API. Its types use the code-unit width selected for this build.
Use `pcre2.c` for raw entry points that the facade does not wrap.

## Width and module names

| Name | Contract |
|---|---|
| `compiled_width`, `compiled_unit` | The selected width (`8`, `16` or `32`) and its code-unit type (`u8`, `u16` or `u32`). |
| `Surface`, `Width(T)` | Typed API for the selected code-unit type. `Width(T)` rejects a type that does not match the selected width at compile time. |
| `Width8`, `Width16`, `Width32` | Convenience aliases. Only the selected width is usable in a build. |
| `c` | Raw translated C declarations for native operations not represented by the typed facade. |
| `runtime_loaded`, `is_runtime_loaded` | Whether this module routes native calls through the runtime dispatcher. |
| `LoadSource`, `load(source)`, `loadedSource()` | Select and load a provider explicitly; `loadedSource` returns the successful request or null. A linked build has no provider to load. |
| `unset` | PCRE2's `PCRE2_UNSET` marker for a capture that did not participate. The POSIX wrapper uses a different marker. |
| `Error` | The facade's closed error set. Unclassified native match results remain `MatchOutcome.failed` with their PCRE2 code. |
| Option namespaces | `compile_option`, `match_option`, `convert_option`, `newline`, `bsr`, `optimization`, `jit_option` and `substitute_case` expose the named PCRE2 values. |
| `DfaOptions`, `SubstituteOptions` | Packed named flags for DFA matching and substitution; fields default to false. |
| `diagnostic_buffer_size`, `max_name_length` | Diagnostic buffer size and maximum accepted group-name length; both are 128 code units. |
| Callback types | `Callout`, `CalloutEnumerate`, `SubstituteCallout`, `SubstituteCaseCallout`, `RecursionGuard`, `JitCallback`, `Allocate` and `Deallocate`. |

## Compile and match

| API | Contract |
|---|---|
| `Regex.compile(pattern, options)` | Compiles a code-unit slice. A syntax refusal is `.rejected`; allocation and facade failures use `Error`. Pattern text is not retained. |
| `Regex.compileWith(pattern, options, context)` | Compiles with an optional `CompileContext`; the returned `Regex` owns the compiled block. |
| `CompileOutcome` | `.compiled: Regex` or `.rejected: Rejection`. A rejection carries the native error code, code-unit offset and diagnostic text. |
| `CompileOptions`, `MatchOptions` | Packed booleans, all defaulting to false; `toBits()` converts the named flags to PCRE2's bit word. Unnamed bits cannot be set through these structs. |
| `MatchOptions.copy_matched_subject` | PCRE2 keeps an internal subject copy until the next attempt or deinit; typed subject and capture slices still borrow caller storage. |
| `MatchOptions.no_jit` | Accepted, but has no effect in this JIT-disabled build. |
| `Regex.captureCount()` | Highest capture-group number. Include group 0 when sizing match data: required pair count is `captureCount() + 1`. |
| `Regex.nameCount()` | Number of named groups, not a group number. |
| `Regex.nameAt(index)` | Reads a name-table entry by table index, in alphabetical name order. `Name.name` borrows the compiled `Regex`; the index is not a group number. |
| `Regex.nameForNumber(number)`, `numberForName(name)` | Look up a name by group number or a group number by name. The returned name is borrowed from the compiled block. |
| `Regex.raw()` | Exposes the owned native compiled block for calls not wrapped here; do not free it separately. |
| `Regex.match(subject, start_offset, options, data, context)` | Matches a borrowed subject. Offsets count code units, not Unicode characters. The facade checks vector capacity and start range first, returning `OvectorTooSmall` or `StartOffsetOutOfRange`. |
| `MatchData.create(&regex)` | Allocates match data sized for that pattern's capture groups and group 0. |
| `MatchData.createWithOvector(pairs, general)` | Allocates an offset vector with a caller-selected pair count; use this for DFA results sized to simultaneous matches. |
| `MatchOutcome.matched`, `.no_match` | A match with readable captures, or an ordinary no-match answer. A zero return caused by insufficient capture capacity becomes `error.OvectorTooSmall`. |
| `MatchOutcome.match_limit`, `.depth_limit`, `.heap_limit` | PCRE2 reached a configured resource ceiling. These are outcomes, not facade errors, and the pattern may still match. |
| `MatchOutcome.invalid_utf` | Invalid UTF input or an invalid UTF start boundary, with the native code and diagnostic. |
| `MatchOutcome.failed` | Other negative PCRE2 results, with their code and diagnostic. Partial matching is `.failed` with code `-2`; it is not a separate tag. |
| `MatchData.groupRange(n)`, `group(n)` | Return a capture range in code units or a borrowed slice of `subject`; return null when there was no match or the group did not participate. An empty capture has equal start and end. |
| `MatchData.captureCount()`, `ovector()` | Pair capacity and the native offset vector. It is readable when `matched` is true after a backtracking or DFA result; partial-match offsets need raw C. |
| `MatchData.matched`, `subject`, `startOffset()` | `matched` says whether the latest attempt left the vector readable. `subject` borrows the last input. `startOffset` also reports invalid-UTF and partial offsets; a facade refusal may leave its previous value. |
| `unset` | `PCRE2_UNSET`, distinct from an empty capture and from `Posix.unset`. |

## Results and other operations

| API | Contract |
|---|---|
| `Text`, `diagnostic(code)` | `Text.slice()` returns PCRE2's diagnostic without its NUL. The fixed storage is `diagnostic_buffer_size` code units; long messages are truncated. |
| `version(buffer)` | Writes the linked library's version into caller-owned storage and returns a NUL-terminated borrowed slice. The buffer must include the NUL or the call returns `VersionBufferTooSmall` without writing. |
| `Regex.dfa(subject, offset, options, data, context, workspace)` | DFA matches are written to `MatchData`, not `DfaWorkspace`. Results are matching substrings, not capture groups, and are ordered longest first. |
| `DfaOutcome` | `.matched{ pairs }`, `.no_match`, `.truncated` or `.failed{ code, text }`. A truncated result has readable but incomplete pairs in `MatchData`. |
| `DfaWorkspace` | Caller-owned scratch storage. `minimum_workspace` is 20 and `wscount(subject_len)` returns `max(subject_len, minimum_workspace)`; the actual slice must meet that size. Reuse the same workspace for a restarted DFA match. |
| `Regex.substitute(subject, offset, options, replacement, data, context, buffer)` | Writes output into the caller's buffer; it does not allocate a separate result string. `Substitution.written.text` borrows that buffer. |
| `Substitution.overflow`, `.failed` | With `overflow_length`, reports required capacity including the NUL without writing. Other failures carry the native code and diagnostic. |
| `SubstituteOptions.matched` | Substitutes the match already in `MatchData`; this is the exception that preserves the existing captures. Other substitution calls invalidate their captures. |
| `MatchData.get(n)`, `copy(n, buffer)`, `list()` | `get` returns an owned native copy; `copy` writes into caller storage and counts the NUL; `list` returns an owned block with borrowed entries available through `list.get(index)` until `deinit`. |
| `MatchData.next(start_offset, options)` | Returns whether another match attempt should be made; true updates both arguments, while false leaves them unchanged. |
| `MatchData.mark()` | Returns the last MARK label from the compiled pattern, borrowed from `Regex`, or null. |
| `ConvertContext.create(general)`, `setGlobEscape`, `setGlobSeparator` | Configure pattern conversion. Setters can return `error.SettingRefused` for unsupported values. |
| `ConvertContext.convert(pattern, kind, utf)` | Converts glob or POSIX pattern text. It returns `.converted` with an owned `Converted` block or `.rejected` with code, offset and diagnostic. |
| `Converted.slice()`, `deinit()` | The slice excludes the terminating NUL. Release the native conversion block with `deinit`, not a Zig allocator or `Regex.deinit`. |
| `convert_option.glob_no_wild_separator`, `.glob_no_starstar` | These values include the `glob` flag; select one complete conversion kind rather than treating them as independent bits. |
| `Regex.serialize(extra, scratch)` | Encodes the pattern and optional compiled blocks into a PCRE2-owned `Serialized` stream that outlives the source `Regex`. The caller supplies sufficiently large pointer arrays; `extra` blocks remain caller-owned. |
| `Regex.decode(bytes, count, all, general)` | Decodes the first block into the returned owned `Regex` and writes all blocks to `all`, which must hold `count` pointers. Release remaining blocks through the raw code-free entry point; `serializedCodeCount` reads the stream's count. |
| `Regex.jitCompile(options)`, `JitStack.create(start, maximum)`, `MatchContext.setJitStack(callback, data)` | JIT compilation returns a refusal value and stack creation returns `error.JitUnsupported` in this build. |

## Contexts and callbacks

| API | Contract |
|---|---|
| `GeneralContext.init()` | Creates a PCRE2 allocation context using its default allocator. |
| `GeneralContext.create(allocate, deallocate, data)` | Supplies the allocator used by PCRE2; the deallocator receives no size. |
| `GeneralContext.tables()`, `freeTables(tables)` | Creates and releases character tables. A compile context stores the table pointer, not a copy; keep the tables alive for every compiled pattern that uses them. |
| `CompileContext.create(general)`, `copy()`, `deinit()` | Owns compile settings and may borrow a general context. Setters cover newline, `\R`, pattern limits, optimization, extra flags, recursion guard and character tables. |
| `ConvertContext` | Owns conversion settings and may borrow a general context. Keep the general context alive until the conversion context and its returned blocks are released. |
| `MatchContext.init()`, `create(general)`, `deinit()` | Owns match limits and callbacks. `setMatchLimit`, `setDepthLimit` and `setHeapLimit` configure the corresponding match outcomes. |
| `setCallout(callback, data)` | The callback and `data` are borrowed for the context lifetime. Return zero to continue, positive to reject this start position, or negative to abort the attempt. |
| `setSubstituteCallout`, `setSubstituteCaseCallout` | Install substitution callbacks; callback pointers and data remain borrowed. |
| `Regex.enumerateCallouts(callback, data)` | Walks callouts in the compiled pattern and returns the count. The callback is required, not optional. |
| `Regex.copy()`, `copyWithTables()` | Make a separately owned compiled block. `copyWithTables` copies character tables; each result needs its own `deinit`. Owning structs are not safe to copy. |

## POSIX wrapper

`Posix.routed` reports whether its calls use runtime dispatch. The wrapper also exposes its `option` bits and POSIX `code` values.

| API | Contract |
|---|---|
| `Posix.compile(pattern, flags)` | Takes a NUL-terminated byte pattern and returns `.compiled` or `.rejected` with a POSIX code. Release a compiled value with `Compiled.deinit()`. |
| `Posix.exec(compiled, subject, pmatch, flags)` | Takes a NUL-terminated subject and caller-owned match array. Outcomes include `.matched`, `.no_match`, `.matched_without_reporting` when `REG_NOSUB` was set at compile time, and `.failed`. |
| `Posix.capture(subject, match)` | Resolves offsets against the same subject passed to `exec`; the returned slice borrows it. |
| `Posix.message(buffer, err, compiled)` | Writes a NUL-terminated POSIX diagnostic into caller storage and returns a borrowed slice. |
| `Posix.unset` | POSIX's `-1` marker; it is not the core `PCRE2_UNSET` value. |
| `REG_STARTEND`, `REG_PEND` | The typed wrapper returns `error.UnsupportedOption` for these pointer-based options. Use `pcre2.c` for the raw interface. |

## Errors

`Error` contains the facade's classified failures; other match failures retain their native code in `MatchOutcome.failed`.

| Error | Meaning |
|---|---|
| `OutOfMemory` | PCRE2 allocation failure. |
| `PatternInfoUnavailable` | A required pattern metadata query failed. |
| `StartOffsetOutOfRange` | Match start offset exceeds the subject. |
| `NoSuchGroup` | Group number is outside the match-data capacity. |
| `OvectorTooSmall` | Match-data offset vector cannot hold the pattern's captures, or a serialization pointer array is too short. |
| `VersionBufferTooSmall`, `VersionUnavailable` | Caller buffer cannot hold the version and NUL, or PCRE2 cannot report its version. |
| `SettingRefused` | PCRE2 refused a context setting. |
| `SubstituteBufferTooSmall` | Substitution output does not fit; no partial result is written. |
| `DfaWorkspaceTooSmall` | DFA scratch storage is below the required size. |
| `JitUnsupported` | JIT stack creation was refused because JIT is disabled. |
| `SubstringUnavailable` | A requested capture is absent, unset or unavailable. |
| `SubstringBufferTooSmall` | Caller buffer cannot hold the copied capture and NUL. |
| `SerializationRefused` | PCRE2 rejected serialized input or blocks with incompatible character tables. |

## Ownership and lifetimes

- `Regex`, `MatchData`, contexts and `Posix.Compiled` own native blocks. Call each value's `deinit`; do not copy an owning struct and release both copies.
- `Owned`, `SubstringList`, `Converted` and `Serialized` own PCRE2 allocations. Their `deinit` methods use the matching PCRE2 free routine; free them through the same library instance that created them.
- Captures borrow the subject. They remain valid only until the subject is released or the next `match`, `dfa` or non-`.matched` substitution on that `MatchData`.
- `Name.name` and MARK labels borrow the compiled `Regex`. `MatchData.subject` also borrows the caller's slice; it is never a replacement for that storage.
- References to general contexts, character tables, callback functions, callback data and DFA workspace are borrowed. Keep them alive for every context, pattern or operation that uses them.
- The POSIX wrapper owns its internal pattern and match data through `Compiled`; `Posix.capture` still borrows the subject supplied by the caller.
