// SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
// Copyright (c) 2026 the contributors to this fork.
//
//! Upstream's POSIX `regcomp`/`regexec` emulation, typed.
//!
//! `pcre2posix.h:159-163` declares four entry points -- `pcre2_regcomp`,
//! `pcre2_regexec`, `pcre2_regerror` and `pcre2_regfree` -- and `:165-176`
//! defines the POSIX spellings `regcomp`, `regexec`, `regerror` and `regfree`
//! as macros over them.
//!
//! ## Where it lives
//!
//! Upstream builds it as a **second artifact**, `libpcre2-posix`, with its own
//! soname (`configure.ac:726-753`) and its own export list
//! (`src/libpcre2-posix.sym.in`, the same four names at the same
//! `PCRE2_10.47` node). This fork keeps that artifact, its header,
//! `libpcre2-posix.pc`, `pcre2-config` and the programs that use it exactly as
//! upstream has them.
//!
//! It is 8-bit by construction and not by preference: `pcre2_regcomp` takes a
//! `const char *` pattern and `regmatch_t::rm_so` counts bytes
//! (`src/pcre2posix.h:104-119`), and `src/pcre2posix.c` never includes
//! `pcre2.h` at all (`:49-52`) -- it declares the four functions itself and
//! reaches the core through the same names `pcre2_8*` has. So this surface is
//! offered only when this build compiled the 8-bit width, which is exactly when
//! `build.zig` builds the wrapper, and `translate.h` includes
//! `pcre2posix.h` under `#if PCRE2_CODE_UNIT_WIDTH == 8`.
//!
//! ## Both linkages reach it
//!
//! `build.zig` also compiles `src/pcre2posix.c` into the **core** library for
//! width 8 and adds the four names to the core's generated version script. That
//! is what makes a runtime-loading build work: `load` names one file, and a
//! provider that is only upstream's `libpcre2-8.so` would not carry the four,
//! so `runtime/graph.zig` routes them like every other entry point and
//! `runtime/library.zig` requires them of the provider. `routed` below says which
//! mechanism a caller is in; both reach the same four functions at the same
//! `PCRE2_10.47` node, so a provider answers for them at the version upstream
//! gives them.
//!
//! ## Ownership
//!
//! A `Compiled` here owns one `regex_t`, and `pcre2_regfree` is the only thing
//! that releases it. Inside, the wrapper asks PCRE2 for a `pcre2_code_8`
//! (`src/pcre2posix.c:301`) and a `pcre2_match_data_8` (`:325`) and frees both
//! itself in `pcre2_regfree` (`:254-259`), so no PCRE2 block escapes and no Zig
//! allocator is involved. That is also why the four functions here are thin:
//! everything interesting happens on the other side of the wrapper.
//!
//! The `regex_t` is a value in `Compiled` and not a pointer to one, because it
//! is the struct `pcre2_regcomp` fills in place and `pcre2_regfree` reads back
//! (`src/pcre2posix.h:159-163`); a pointer to a `compile` local would name a
//! slot that is gone before anything could free it.

const c = @import("c");
const widthed = @import("widthed.zig");

/// The wrapper's own option bits, `src/pcre2posix.h:58-70`.
///
/// Most are POSIX's, which is what the header says of the block as a whole
/// ("mostly defined by POSIX, but with some extras", `:56`), and the
/// exceptions are marked one by one: five bits are `NOT defined by POSIX`,
/// two belong to another system -- BSD's `REG_STARTEND` and GNU's `REG_PEND` --
/// and `REG_EXTENDED` is not in the list at all. Upstream defines that one as
/// zero (`:72-75`) so a program written against POSIX still compiles; this
/// binding does not restate it. Every value below is the header's, and the
/// mapping into PCRE2 options is the wrapper's -- `src/pcre2posix.c:292-298`
/// for the word `compile` passes and `:364-366` for the one `exec` passes --
/// and not here.
pub const option = struct {
    pub const icase: u32 = 0x0001; // :58 REG_ICASE, maps to PCRE2_CASELESS
    pub const newline: u32 = 0x0002; // :59 REG_NEWLINE, maps to PCRE2_MULTILINE
    pub const notbol: u32 = 0x0004; // :60 REG_NOTBOL
    pub const noteol: u32 = 0x0008; // :61 REG_NOTEOL
    /// Not POSIX. Maps to `PCRE2_DOTALL`.
    pub const dotall: u32 = 0x0010; // :62 REG_DOTALL
    /// Do not report what was matched. A compile-time bit: the wrapper keeps
    /// the `cflags` it was compiled with and drops the caller's match array on
    /// every later attempt because of it (`src/pcre2posix.c:300`, `:368-372`),
    /// which is why `exec` reports `matched_without_reporting` from the block
    /// rather than from its own flags.
    pub const nosub: u32 = 0x0020; // :63 REG_NOSUB
    /// Not POSIX. Maps to `PCRE2_UTF`.
    pub const utf: u32 = 0x0040; // :64 REG_UTF
    /// BSD: pass the subject by its start and end offsets rather than as a
    /// string, through the `const char *` argument itself.
    pub const startend: u32 = 0x0080; // :65 REG_STARTEND
    /// Not POSIX. Maps to `PCRE2_NOTEMPTY`.
    pub const notempty: u32 = 0x0100; // :66 REG_NOTEMPTY
    /// Not POSIX. Maps to `PCRE2_UNGREEDY`.
    pub const ungreedy: u32 = 0x0200; // :67 REG_UNGREEDY
    /// Not POSIX. Maps to `PCRE2_UCP`.
    pub const ucp: u32 = 0x0400; // :68 REG_UCP
    /// GNU: the pattern's end is in `regex_t::re_endp` rather than at a NUL.
    pub const pend: u32 = 0x0800; // :69 REG_PEND
    /// Maps to `PCRE2_LITERAL`, so every character in the pattern is literal.
    pub const nospec: u32 = 0x1000; // :70 REG_NOSPEC
};

/// The wrapper's error values, `src/pcre2posix.h:79-97`.
///
/// POSIX's own set, kept here so a caller can name one without the raw route.
/// The wrapper returns them unchanged, so a caller matching a name against a
/// code is matching upstream's table.
pub const code = struct {
    pub const assert: c_int = 1; // :80
    pub const badbr: c_int = 2; // :81
    pub const badpat: c_int = 3; // :82
    pub const badrpt: c_int = 4; // :83
    pub const ebrace: c_int = 5; // :84
    pub const ebrack: c_int = 6; // :85
    pub const ecollate: c_int = 7; // :86
    pub const ectype: c_int = 8; // :87
    pub const eescape: c_int = 9; // :88
    pub const empty: c_int = 10; // :89
    pub const eparen: c_int = 11; // :90
    pub const erange: c_int = 12; // :91
    pub const esize: c_int = 13; // :92
    pub const espace: c_int = 14; // :93
    pub const esubreg: c_int = 15; // :94
    pub const invarg: c_int = 16; // :95
    pub const nomatch: c_int = 17; // :96, REG_NOMATCH
};

/// `regex_t`, `src/pcre2posix.h:103-110`.
///
/// The struct is declared by the header, so this is a re-export rather than a
/// restatement: `c.regex_t` in this file, `c.pcre2_regcomp` in a consumer and
/// the compiled `regex_t` in the library are one nominal type, and a value of
/// one needs no cast. Its size is fixed by that declaration, which is exactly
/// why upstream refuses to spell these four functions `regcomp` and friends: a
/// system `regex_t` differs in size and the two would be mixed
/// (`src/pcre2posix.h:153-157`).
pub const Regex = c.regex_t;

/// `regoff_t`, `src/pcre2posix.h:114`: `int`.
pub const Offset = c.regoff_t;

/// `regmatch_t`, `src/pcre2posix.h:116-119`.
pub const Match = c.regmatch_t;

/// The wrapper's own marker for a group that did not take part: `-1`.
///
/// `src/pcre2posix.c:403-408` writes the literal `-1` into **both** ends of a
/// `regmatch_t` for every group `pcre2_match` left unset, and for every slot of
/// the caller's array past the one the match filled. `-1` is upstream's own
/// marker here, **not** `PCRE2_UNSET` narrowed: `-1` and `~@as(usize, 0)` are
/// different values, and a caller comparing a POSIX capture against the width
/// surface's marker would never match.
///
/// Typed `c_int` rather than `Offset`, which is `c.regoff_t`, so that this one
/// constant is publishable in a build whose translation carries no
/// `regoff_t` at all.
pub const unset: c_int = -1;

/// What `pcre2_regcomp` did.
pub const CompileOutcome = union(enum) {
    /// The pattern compiled. Owns the wrapper's own block, which owns the
    /// compiled pattern and the match-data block inside it; release it with
    /// `Compiled.deinit`.
    compiled: Compiled,
    /// Upstream refused the pattern, with its own POSIX code.
    rejected: struct { code: c_int },
};

/// Everything this wrapper can refuse to do, and nothing else.
///
/// Separate from the width surface's error set because the wrapper is a
/// different library with its own failure modes: it returns POSIX codes rather
/// than PCRE2 ones, and it has two options that change what the pointer
/// arguments mean.
pub const Error = error{
    /// `REG_STARTEND` or `REG_PEND` was set.
    ///
    /// Both are features where the wrapper reads a pointer-sized value out of a
    /// `const char *` argument rather than a string: `REG_STARTEND` takes the
    /// subject's start and end offsets that way (`src/pcre2posix.h:65`), and
    /// `REG_PEND` takes the pattern's end the same way (`:69`). A Zig slice
    /// passed in their place would be a pointer the wrapper then adds to, so
    /// this binding refuses them instead of passing something whose meaning it
    /// cannot check. The raw route is where a caller who wants them goes.
    UnsupportedOption,
    /// The compiled pattern has already been released, or was never compiled.
    /// `exec` reads `Compiled.raw` before it makes the call, so this is a
    /// caller mistake rather than a condition PCRE2 reports.
    RegexNotCompiled,
};

/// What one `pcre2_regexec` did.
pub const MatchOutcome = union(enum) {
    /// It matched, and `pmatch` holds the offsets: group 0 is the whole match,
    /// and a group that did not take part has `unset` in both ends, and every
    /// slot of the caller's array past the ones the match filled is written
    /// with that same value rather than left alone
    /// (`src/pcre2posix.c:403-408`).
    matched: void,
    /// `REG_NOMATCH`, the ordinary negative answer and not an error.
    no_match: void,
    /// The pattern was compiled with `REG_NOSUB`, so the wrapper matched and
    /// reported nothing at all, and still answered zero
    /// (`src/pcre2posix.c:368-372`, `:396-400`). It is the compiled pattern's
    /// own flags that say so, not `exec`'s: see `exec`.
    matched_without_reporting: void,
    /// Any other non-zero answer, which is one of the `code` values.
    failed: struct { code: c_int },
};

/// A compiled POSIX regular expression, owned.
///
/// Created by `compile`, released by `deinit`, and valid in between. The
/// wrapper's own `regex_t` is a value here rather than a pointer to one,
/// because `pcre2_regcomp` fills the struct the caller hands it
/// (`src/pcre2posix.c:277-301`) and `pcre2_regfree` is the one that reads it
/// back: a pointer to a local of `compile` would name a slot that is gone by
/// the time anything could free it.
///
/// Inside it there are two PCRE2 blocks -- a compiled pattern and a match-data
/// block -- and the wrapper frees both itself in `pcre2_regfree`
/// (`src/pcre2posix.c:254-259`, allocated at `:301` and `:325`), so nothing
/// escapes and nothing here has to be released twice.
pub const Compiled = struct {
    /// The wrapper's own block. `null` once `deinit` has run.
    raw: ?Regex,

    /// Releases the wrapper's block, and with it the compiled pattern and the
    /// match-data block the wrapper put inside it. A second call on this value
    /// is a no-op.
    pub fn deinit(self: *Compiled) void {
        if (self.raw) |*raw| c.pcre2_regfree(raw);
        self.raw = null;
    }
};

/// Compiles `pattern` with the wrapper's own `pcre2_regcomp`.
///
/// A rejection is a value rather than an error, and carries upstream's POSIX
/// code. `REG_BADPAT` is the **default**, not the answer for every bad pattern:
/// the wrapper takes the compile-error index and looks it up in two tables,
/// falling back to `REG_BADPAT` for anything not listed
/// (`src/pcre2posix.c:312-319`). So `a(b` is `REG_EPAREN`, because `missing )`
/// maps there (`:146`), as do `missing ) after (?# comment` (`:151`) and
/// `unmatched closing parenthesis` (`:156`);
/// `reference to non-existent subpattern` is `REG_ESUBREG` (`:148`), both
/// `parentheses nested too deeply` and `regular expression too large` are
/// `REG_ESIZE` (`:152`, `:154`), `failed to get memory` is `REG_ESPACE` (`:155`),
/// and the first table's earlier rows give a missing terminating `]`, an
/// out-of-order range, bad `{...}` repeat counts and bad escapes their own codes
/// (`:129-158`). Match the code, not a guess about which kind of wrong the
/// pattern is.
///
/// `pattern` is a NUL-terminated string, because that is what the wrapper
/// takes: without `REG_PEND` it passes `PCRE2_ZERO_TERMINATED` and lets the
/// library find the end (`src/pcre2posix.c:289-290`), so an embedded NUL ends
/// the pattern. That is the POSIX contract and not an accident of this
/// binding.
///
/// The flags are the wrapper's own `cflags`, and they are kept: `REG_NOSUB`
/// among them is remembered in the block and is what `exec` reports from.
///
/// `REG_PEND` is `error.UnsupportedOption`, because with it set the wrapper
/// reads the pattern's end out of `regex_t::re_endp` rather than looking for a
/// NUL (`src/pcre2posix.c:289-290`), and this call has no way to fill that
/// field before the wrapper reads it. `REG_STARTEND` has no meaning at compile
/// time and is simply not passed.
pub fn compile(pattern: [:0]const u8, flags: u32) Error!CompileOutcome {
    if ((flags & option.pend) != 0) return error.UnsupportedOption;
    var compiled: Regex = undefined;
    const rc = c.pcre2_regcomp(&compiled, pattern.ptr, @bitCast(flags));
    if (rc != 0) return .{ .rejected = .{ .code = rc } };
    return .{ .compiled = .{ .raw = compiled } };
}

/// Runs one attempt of a compiled pattern over `subject`.
///
/// `subject` is a NUL-terminated string, because that is what the wrapper
/// takes: without `REG_STARTEND` it measures the subject with `strlen` before
/// it matches (`src/pcre2posix.c:385-389`), so an embedded NUL ends the
/// subject. Its length is never this binding's to pass.
///
/// `pmatch` is the caller's array of `Match`, one per capturing group plus
/// group 0, and `pmatch.len` is the match count handed over as the wrapper's
/// `nmatch`, which is the number of `regmatch_t` slots and nothing to do with
/// the subject's length (`src/pcre2posix.h:160-161`,
/// `src/pcre2posix.c:396-408`). A group that did not take part comes back with
/// both ends equal to `unset` (`:403-404`), which is a value the caller reads
/// through `capture` rather than an absence this call hides, and every slot
/// past the ones the match filled is written with that same value rather than
/// left alone (`:408`): an array shorter than the pattern's capture count is a
/// smaller answer, not an overrun.
///
/// `flags` are the wrapper's `eflags`, and three of them are all it reads:
/// `REG_NOTBOL`, `REG_NOTEOL` and `REG_NOTEMPTY` become the matching options
/// (`src/pcre2posix.c:364-366`) and the rest of the word is ignored. Two
/// consequences, both of them upstream's rather than this file's:
///
///  * `REG_NOSUB` passed here does nothing. It is a compile-time bit: the
///    wrapper records the `cflags` it was compiled with (`src/pcre2posix.c:300`)
///    and zeroes its own match count from that record on every attempt
///    (`:368-372`), which is why `matched_without_reporting` is decided here
///    from the compiled block's flags.
///  * `REG_STARTEND` is `error.UnsupportedOption`: it makes the `const char *`
///    subject argument carry two offsets instead of a string
///    (`src/pcre2posix.h:65`, `src/pcre2posix.c:379-384`), and passing a
///    pointer where the wrapper expects to read two integers is not something
///    this binding can do safely. The raw route is where a caller who wants it
///    goes.
pub fn exec(
    compiled: *const Compiled,
    subject: [:0]const u8,
    pmatch: []Match,
    flags: u32,
) Error!MatchOutcome {
    if ((flags & (option.startend | option.pend)) != 0) return error.UnsupportedOption;
    const regex: *const Regex = if (compiled.raw) |*r| r else return error.RegexNotCompiled;
    const rc = c.pcre2_regexec(regex, subject.ptr, pmatch.len, pmatch.ptr, @bitCast(flags));
    if (rc == 0) {
        if ((@as(u32, @bitCast(regex.re_cflags)) & option.nosub) != 0)
            return .matched_without_reporting;
        return .matched;
    }
    if (rc == code.nomatch) return .no_match;
    return .{ .failed = .{ .code = rc } };
}

/// The text of one capture, resolved against the subject the caller passed.
///
/// The wrapper stores offsets, not pointers, so this is the same arrangement as
/// the width surface's `MatchData.group`: a pair of byte offsets into the
/// caller's own slice. A group that did not take part answers null, because the
/// wrapper leaves `unset` in both ends of it (`src/pcre2posix.c:403-408`).
///
/// This is a `function`, not a method, because the wrapper's `regmatch_t` holds
/// no pointer back to the subject it matched: that is the caller's, and it must
/// be the subject `exec` was given.
pub fn capture(subject: []const u8, match: Match) ?[]const u8 {
    if (match.rm_so == unset or match.rm_eo == unset) return null;
    const start: usize = @intCast(match.rm_so);
    const end: usize = @intCast(match.rm_eo);
    if (start > end or end > subject.len) return null;
    return subject[start..end];
}

/// Upstream's message for one POSIX error code, written into `buffer` and
/// returned as a window on it.
///
/// `pcre2_regerror_N` writes at most `len` bytes including the terminating NUL
/// and answers the length it would have written had the buffer been long
/// enough (`src/pcre2posix.c:198-246`), so a zero-length buffer is a legal
/// size query and answers the needed length without writing anything.
///
/// `compiled` is the wrapper's own block, which contributes an ` at offset N`
/// suffix when the compile that produced it failed (`src/pcre2posix.c:210-220`);
/// a successful compile clears that offset instead (`:326`). A rejected
/// pattern has no block to hand over, because `compile` returns `.rejected` and
/// keeps no block from the attempt that failed, so `null` is the honest answer
/// for one. With `Compiled.raw` inline, a compiled pattern's block is
/// `&compiled.raw.?`.
pub fn message(buffer: []u8, err: c_int, compiled: ?*const Regex) [:0]const u8 {
    const needed = c.pcre2_regerror(
        err,
        if (compiled) |r| r else null,
        buffer.ptr,
        buffer.len,
    );
    // The count includes the terminator, and it is the count the library needed
    // rather than the count it wrote, so a buffer one byte short of it is the
    // case this has to catch rather than pass through.
    const length = @min(needed, buffer.len);
    if (length == 0) return buffer[0..0 :0];
    return buffer[0 .. length - 1 :0];
}

/// Why the wrapper is or is not available in this configuration.
///
/// A named type rather than a compile error string, so a caller can ask the
/// question without triggering one, and so `build.zig`'s own width check and this
/// one read the same fact.
pub const Availability = enum {
    /// The 8-bit width was compiled and this build links the wrapper beside it.
    linked,
    /// The wrapper is not reachable: this build compiled a width other than 8,
    /// which is the only case in which `build.zig` builds no wrapper and the
    /// only case in which `translate.h` leaves its declarations out. How the
    /// symbols are reached is not part of this answer; `routed` below says
    /// that, and both linkages work for the 8-bit width.
    unavailable,
};

/// Whether the translated header this build produced carries the wrapper's four
/// entry points and its two structs.
///
/// The aggregate translation header `translate.h` names `pcre2.h` alone
/// (`translate.h:126-127`), and `pcre2posix.h` is a second header for a second
/// artifact, so whether these declarations are present at all is a property of
/// the translation and not of this file. Asking is how this surface stays honest
/// in a build where they are not there: the answer is `.unavailable`, and the
/// entries below say why rather than a name the caller cannot use.
pub const translated: bool = @hasDecl(c, "pcre2_regcomp") and
    @hasDecl(c, "pcre2_regexec") and
    @hasDecl(c, "pcre2_regerror") and
    @hasDecl(c, "pcre2_regfree") and
    @hasDecl(c, "regex_t") and
    @hasDecl(c, "regmatch_t") and
    @hasDecl(c, "regoff_t");

/// Which of the two states this build is in.
///
/// Two facts have to agree, and each one alone would be a guess:
///
///  * the translation carries the wrapper's declarations, which is
///    `translated` above and is `build.zig`'s aggregate header deciding it:
///    `translate.h` includes `pcre2posix.h` under
///    `#if PCRE2_CODE_UNIT_WIDTH == 8`;
///  * the compiled width is 8, because the wrapper is 8-bit by construction
///    (`src/pcre2posix.h:104-119` counts bytes) and `build.zig` builds no
///    wrapper for 16 or 32.
///
/// A runtime-loading build of the 8-bit width is `.linked` too, and for the
/// same two reasons: `translate.h` includes `pcre2posix.h` for that width, and
/// `build.zig` compiles `src/pcre2posix.c` into the core library and exports the
/// four from it, so the one file a `load` names carries them. `routed` below is
/// the distinction a caller needs: the wrapper works in both linkages, and only
/// the mechanism differs.
pub const availability: Availability = if (translated and
    widthed.compiled_width == .@"8") .linked else .unavailable;

/// Whether the four entry points are resolved through the runtime dispatch.
///
/// True in a runtime-loading build, where `runtime/graph.zig` routes them like
/// every other entry point and `runtime/library.zig` requires them of the
/// provider. That is possible because `build.zig` compiles `src/pcre2posix.c`
/// into the core library for width 8 and exports the four from the core's
/// generated version script, so one provider carries both the width library's
/// names and the wrapper's; upstream's separate `libpcre2-posix` is still built,
/// installed and unchanged.
///
/// False in a linked build, where `c` is the translated header and the four are
/// ordinary linked calls with no table and no check. Both states are a working
/// way to call the wrapper; `routed` says which one a caller is in, so a
/// consumer that cares about the mechanism can ask rather than infer it from
/// the build flags.
pub const routed: bool = runtime_loaded;

/// Whether this build was configured to resolve the native symbols at run time.
///
/// Read through the generated dispatch's own flag, which is what `zig/root.zig`
/// reads too; declared here so this file does not have to import the module
/// root, which would be a cycle.
const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// The wrapper's option bits, reachable in every configuration.
///
/// Named at file scope as well so `Unavailable` below can publish them under
/// the short name without its own `option` declaration shadowing the one it is
/// aliasing.
pub const posix_option = option;

/// The wrapper's error codes, reachable in every configuration, for the same
/// reason as `posix_option`.
pub const posix_code = code;

/// The two answers to "does this build have the wrapper", at file scope under
/// a second name, for the same reason as `posix_option`.
pub const posix_availability = Availability;

/// The wrapper's unset marker at file scope under a second name, for the same
/// reason.
pub const posix_unset = unset;

/// The message a refused entry point carries.
fn unavailable_message(comptime what: []const u8) []const u8 {
    return "pcre2: the POSIX wrapper is not reachable in this build, so " ++
        what ++ " has no library behind it. It is 8-bit by construction " ++
        "(src/pcre2posix.h:104-119), build.zig builds it only for width 8, and " ++
        "translate.h includes pcre2posix.h only under " ++
        "#if PCRE2_CODE_UNIT_WIDTH == 8. A runtime-loading build is not the " ++
        "reason: build.zig compiles the wrapper into the core for width 8 and " ++
        "exports the four from it, so one provider carries them. Build with " ++
        "-Dcode-unit-width=8, and read pcre2.Posix.availability to see which of " ++
        "the two facts is the one missing.";
}

/// What this file publishes when the wrapper is not reachable.
///
/// Named members with one compile-time message each, rather than an absent
/// struct, so the answer a caller gets says which of the three facts above was
/// the one that failed instead of "no member named compile".
pub const Unavailable = struct {
    /// Always `.unavailable` here, so a caller can branch on it without
    /// triggering a compile error.
    pub const availability: posix_availability = .unavailable;

    /// The same type `Posix.availability` answers with in the other state, so a
    /// caller names one type rather than two.
    pub const Availability = posix_availability;

    /// The wrapper's unset marker, which is a header constant with no symbol
    /// behind it and is therefore published in both states for the same reason
    /// as `option` and `code` below.
    pub const unset = posix_unset;

    /// The wrapper's option bits and error codes are header constants with no
    /// symbols behind them, so they are published in both states: a caller
    /// matching a name against a code is matching upstream's table, and the
    /// table is the same whether or not the library was built.
    pub const option = posix_option;
    pub const code = posix_code;

    pub fn compile(pattern: [:0]const u8, flags: u32) Error!CompileOutcome {
        _ = pattern;
        _ = flags;
        @compileError(unavailable_message("pcre2.Posix.compile"));
    }

    pub fn exec(
        compiled: *const Compiled,
        subject: [:0]const u8,
        pmatch: []Match,
        flags: u32,
    ) Error!MatchOutcome {
        _ = compiled;
        _ = subject;
        _ = pmatch;
        _ = flags;
        @compileError(unavailable_message("pcre2.Posix.exec"));
    }

    pub fn capture(subject: []const u8, match: Match) ?[]const u8 {
        _ = subject;
        _ = match;
        @compileError(unavailable_message("pcre2.Posix.capture"));
    }

    pub fn message(buffer: []u8, err: c_int, compiled: ?*const Regex) [:0]const u8 {
        _ = buffer;
        _ = err;
        _ = compiled;
        @compileError(unavailable_message("pcre2.Posix.message"));
    }
};
