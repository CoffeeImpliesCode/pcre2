<!--
SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
Copyright (c) 2026 the contributors to this fork.
-->

Grant covers only fork-authored files: build graph, manifest, aggregate header, `zig/` facade, `runtime/` loader, tests, fixtures, smoke program, consumer, Nix/devenv packaging, and docs. It covers no upstream bytes; `LICENCE.md` is upstream's, shipped unmodified.

## Grant

```
SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
```

Rights holder authorized the grant on 2026-10-04.

## Copyright

```
Copyright (c) 2026 the contributors to this fork.
All rights reserved.
```

Upstream copyrights: University of Cambridge (basic library, 1997-2007), Philip Hazel (basic library, 2007-2024), and Zoltan Herczeg (JIT, 2010-2024; stack-less JIT, 2009-2024). None are fork-authored.

## Terms

```
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notices,
  this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright
  notices, this list of conditions and the following disclaimer in the
  documentation and/or other materials provided with the distribution.

* Neither the name of the University of Cambridge nor the names of any
  contributors may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

The second condition in the BSD licence (covering binary redistributions) does
not apply all the way down a chain of software. If binary package A includes
PCRE2, it must respect the condition, but if package B is software that
includes package A, the condition is not imposed on package B unless it uses
PCRE2 independently.
```

## Paths outside this grant

| Paths | Grant |
|---|---|
| `src/`, `doc/` | upstream's **BSD-3-Clause WITH PCRE2-exception** |
| `testdata/` | **not copyrighted; public domain** — not a BSD grant |
| `src/pcre2_jit_compile.c`, `src/pcre2_jit_*_inc.h`, `deps/sljit` | upstream's **2-clause BSD** for the JIT |
| `LICENCE.md`, `COPYING`, `AUTHORS.md`, `SECURITY.md` | upstream's own records, shipped unmodified |
| `.gitignore` | upstream's file, with this fork's appended block recorded in `NOTICE.md` |

`README.upstream.md` is upstream's README, preserved byte for byte and not fork-authored.
