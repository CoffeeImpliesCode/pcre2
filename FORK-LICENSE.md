<!--
SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
Copyright (c) 2026 the contributors to this fork.
-->

# FORK-LICENSE.md — the grant for files this fork added

This covers **only** fork-authored files: the Zig build graph, manifest,
aggregate header, the whole of the `zig/` facade, the whole of the `runtime/`
loading route, tests, fixtures, smoke program, consumer, CI workflow, Nix and
devenv packaging, and this documentation set. It grants nothing over upstream's
bytes, and it changes nothing about them. `LICENCE.md` is upstream's file,
shipped unmodified.

## The grant

```
SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
```

That identifier is upstream's own (`LICENCE.md:4`), and it is the owner's choice
for the fork's independent work, made on 2026-10-04. Upstream's terms do not
govern these files; this grant does, and it happens to name the same terms.

## One body, published under each project's own identifier

`runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c` and
`runtime/sync.h` are the workspace's loader core rather than work written for
PCRE2: `diff` against `fast_float/runtime/` leaves exactly two kinds of line
different — the SPDX identifier at the head of each file, and the `sync.h`
include guard — and `runtime/graph.zig:13` and `build.zig:1049-1051` each say so
in their own words. The identifier follows the project, because the terms behind
it are the owner's per-project authorization, so one body ships under each SDK's
own identifier with that SDK's own guard and no per-SDK edit to anything else.
`runtime/library.zig` and `runtime/graph.zig` are PCRE2's own: the first states
that it is the file another SDK replaces (`runtime/library.zig:8-12`), and the
second is what `build.zig:269` imports.

## Authorization

* Direct owner authorization for the fork-authored set above, on 2026-10-04.
* It supersedes the earlier record in `NOTICE.md` that these files were
  **unassigned** and that an earlier offer of these terms was unsupported and
  withdrawn (`CHANGELOG.md` entry 21). That record described the state before
  this authorization and is kept as history.

## Copyright

```
Copyright (c) 2026 the contributors to this fork.
All rights reserved.
```

No individual is named because none was supplied. Upstream's copyright is not
affected: the basic library functions are Copyright (c) 1997-2007 University of
Cambridge and Copyright (c) 2007-2024 Philip Hazel, the JIT support Copyright
(c) 2010-2024 Zoltan Herczeg, and the stack-less JIT Copyright (c) 2009-2024
Zoltan Herczeg (`LICENCE.md:23-57`). Those statements cover upstream's work; no
fork-authored file carries them and none should be added.

## The terms

Reproduced from `LICENCE.md:70-94` without rewording, and with the exemption at
`LICENCE.md:100-104`:

> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are met:
>
> * Redistributions of source code must retain the above copyright notices,
>   this list of conditions and the following disclaimer.
>
> * Redistributions in binary form must reproduce the above copyright
>   notices, this list of conditions and the following disclaimer in the
>   documentation and/or other materials provided with the distribution.
>
> * Neither the name of the University of Cambridge nor the names of any
>   contributors may be used to endorse or promote products derived from this
>   software without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
> AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
> IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
> ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
> LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
> CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
> SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
> INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
> CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
> ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
> POSSIBILITY OF SUCH DAMAGE.
>
> The second condition in the BSD licence (covering binary redistributions) does
> not apply all the way down a chain of software. If binary package A includes
> PCRE2, it must respect the condition, but if package B is software that
> includes package A, the condition is not imposed on package B unless it uses
> PCRE2 independently.

A binary redistribution must reproduce these notices in its documentation or
other materials, which is why `package.nix`'s build output carries the licence
texts. There is no Apache-2.0 obligation in this tree: no `NOTICE`-file
requirement, no statement-that-files-changed requirement, and no patent grant or
termination clause, because the shipped terms grant no patent licence.

## Paths this file does not cover

`NOTICE.md` holds the per-path inventory.

| Paths | Grant |
|---|---|
| `src/`, `doc/` | upstream's **BSD-3-Clause WITH PCRE2-exception** (`LICENCE.md:10-13`) |
| `testdata/` | **not copyrighted; public domain** (`LICENCE.md:14`) — not a BSD grant |
| `src/pcre2_jit_compile.c`, `src/pcre2_jit_*_inc.h`, `deps/sljit` | upstream's **2-clause BSD** for the JIT (`LICENCE.md:16-20`, `:57`) |
| `LICENCE.md`, `COPYING`, `AUTHORS.md`, `SECURITY.md` | upstream's own records, shipped unmodified |
| `.gitignore` | upstream's file, with this fork's appended block recorded in `NOTICE.md` |

`deps/sljit` is an **empty directory** in this checkout: the submodule named at
`.gitmodules:1-3` was never populated, nothing here compiles or links it, and no
sljit licence text is shipped because there is no sljit code to ship.

`README.upstream.md` is upstream's README preserved byte for byte, not
fork-authored work, and is deliberately absent from `UPSTREAM.sha256` for the
reason `UPSTREAM.md` § "Integrity" gives.

## SPDX identifiers in fork-authored files

Files carry `SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception` in the
comment form their format allows: `//` in Zig and Nix, `/* */` in C
(`translate.h`, `runtime/sync.c`, `runtime/sync.h`), `<!-- -->` in Markdown, and
`#` in shell and YAML. Upstream files never gain one.