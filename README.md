<!--
SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
Copyright (c) 2026 the contributors to this fork.
-->

# PCRE2

PCRE2 10.49 packaged as a Zig module and native C library.
The Zig facade wraps a translation of upstream's public C header.

## Source deviations

| Path | Change |
|---|---|
| `.gitignore` | Keeps upstream rules and adds seven fork-source reinclusions plus five guards for upstream templates used by the build. |
| `translate.h` | Fork-authored aggregate header passed to Zig's translator with target-specific definitions; upstream headers remain unchanged. |
| `README.md` | Upstream's README is preserved unchanged as `README.upstream.md`; this file is the fork's package entry point. |

Upstream C sources, headers, tests, fixtures and licence texts are unchanged.

## Build deviations

- `build.zig` extends upstream's Zig 0.17.0 graph. It builds from this tree and downloads no build dependencies.
- The same 31 C translation units are compiled at widths 8, 16 and 32 into one core artifact. `-Dcode-unit-width` selects its installed name and the width of the Zig facade; it does not change the artifact's three-width closure.
- The POSIX wrapper is also compiled into the 8-bit core for runtime loading. The separate upstream `libpcre2-posix` artifact remains. The build installs `pcre2posix_test`, which upstream classifies as a non-installed test program.
- `config.h` is generated per target. Header translation uses Aro directly on GNU libc targets and the target C preprocessor before Aro elsewhere.
- The generated header and `config.h` are shared by C compilation and Zig translation; linkage settings also drive export declarations and pkg-config flags.
- The `sljit` dependency and JIT build option are removed. JIT compilation and stack creation are refused; other public JIT helpers are no-ops.
- The graph installs upstream's tools, pkg-config metadata, `pcre2-config`, manuals, documentation and licence records.

## Support matrix

| Surface | Support |
|---|---|
| Core widths | 8, 16 and 32; default 8. Each build publishes one typed width, while its bundled core defines all three. |
| Unicode | Enabled. JIT is unavailable. |
| POSIX wrapper | 8-bit only. |
| Linkage | Bundled builds default to dynamic on GNU libc targets and static elsewhere; system integration defaults to dynamic. Requested dynamic linkage is rejected when the target has no dynamic linker. |
| System integration | `-fsys=pcre2-8` uses the installed header and library; it requires width 8 and the build machine's target. |
| Runtime loading | `-Druntime=true` uses an explicit provider with no fallback. The provider must export all three widths; it must also export the POSIX entry points if that facade is used. |

## Consumption

Add the package to a consumer's `build.zig.zon`:

```zig
.dependencies = .{
    .pcre2 = .{ .path = "../pcre2" },
},
```

Import its module in `build.zig`:

```zig
const pcre2_dep = b.dependency("pcre2", .{ .target = target, .optimize = optimize });
exe_mod.addImport("pcre2", pcre2_dep.module("pcre2"));
```

The module name is `pcre2`; its raw translated C declarations are `pcre2.c`. The primary installed library is named `libpcre2-8`, `libpcre2-16` or `libpcre2-32`, according to the selected width. Width 8 also installs `libpcre2-posix`.

| Option | Effect |
|---|---|
| `-Dcode-unit-width=8\|16\|32` | Selects the primary artifact name and typed facade width; default 8. |
| `-Dlinkage=static\|dynamic` | Selects static or dynamic linkage; defaults as shown above. |
| `-Druntime=true` | Resolves native calls through an explicitly loaded provider. |
| `-fsys=pcre2-8` | Links an installed 8-bit library instead of compiling the bundled sources. |
| `-Dsanitize_c=<value>` | Selects C undefined-behaviour sanitization; default `off`. |
