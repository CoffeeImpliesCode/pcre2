# PCRE2 fork notes

## Source changes

Upstream C sources, headers, tests, fixture data, and licence texts remain unchanged. `.gitignore` is the only edited upstream support file; the upstream README is preserved unchanged as `README.upstream.md`.

| File | Change and purpose |
|---|---|
| `.gitignore` | Adds reinclusions for fork-owned files and guards for upstream templates consumed by the build. |
| `README.md` | Replaces the upstream front door with fork-specific build, support, and consumption guidance. |
| `README.upstream.md` | Preserves the original upstream README after its move from `README.md`. |
| `translate.h` | Adds the translation aggregate, width-gated POSIX declarations, and guarded compiler typedefs needed for NetBSD headers. |
| `zig/root.zig` | Adds the public facade that selects the configured width and exposes typed, raw C, POSIX, and runtime-loading APIs. |
| `zig/widthed.zig` | Adds width-generic wrappers so API types and offsets use the selected code-unit type. |
| `zig/raw.zig` | Adds typed bindings to width-suffixed C declarations for the selected width. |
| `zig/posix.zig` | Adds a typed facade for upstream's POSIX wrapper, which is available only at width 8. |
| `runtime/loader.zig` | Adds explicit path or system-name loading with validation and process-lifetime provider retention. |
| `runtime/generate.zig` | Generates runtime dispatch from the translated C declarations. |
| `runtime/library.zig` | Requires the declared exports and probes each width before publishing a provider. |
| `runtime/graph.zig` | Connects translated declarations to dispatch without linking the native library into the facade. |
| `runtime/sync.h` | Declares the prefixed lock, wait, broadcast, and thread-identity interface used by the loader. |
| `runtime/sync.c` | Implements that synchronization interface for Windows, WASI/Emscripten, and pthread targets. |
| `tests.zig` | Adds facade behavior tests across widths without changing upstream tests. |
| `smoke.zig` | Adds a deterministic example with hand-worked code-unit offsets. |
| `consumer/build.zig` | Adds a separate package that imports the published module and forwards its build options. |
| `consumer/src/main.zig` | Exercises named captures across widths and loads a provider only in runtime mode. |
| `testdata/foundation-fixtures.zig` | Adds fork-owned expected answers while leaving upstream fixture files unchanged. |

## Build graph deviations

- `build.zig` generates `config.h` per target and builds the core source set at widths 8, 16, and 32 into one primary artifact. `-Dcode-unit-width` selects the facade and installed artifact name; it does not remove the other width exports.
- At width 8, `src/pcre2posix.c` is compiled into the core for runtime loading; the separate upstream POSIX library remains. The graph installs upstream tools, including `pcre2posix_test` (normally non-installed), metadata, manuals, documentation, and licence records.
- Translation uses Aro directly on GNU libc targets. Elsewhere, the target C preprocessor expands `translate.h` before Aro parses it; `-fno-blocks` keeps Darwin block declarations out of the parser, and `translate.h` carries compiler-provided 128-bit typedefs where needed.
- `pcre2-config` derives its prefix from its installed `bin/` path because Zig 0.17 exposes install paths only during the make phase.
- `RunTest` receives the source directory as a make-time absolute path argument because Zig 0.17 no longer resolves `LazyPath` during configuration.
- The `sljit` dependency and JIT build option are removed because the submodule is empty and fetching it would require a network dependency. JIT is disabled, but its public entry points remain and report refusal.
- `-fsys=pcre2-8` uses an installed header and library instead of bundled C sources. `-Druntime=true` resolves an explicit provider and does not link the native artifact into the facade.
- The default install builds dynamic linkage on GNU libc targets and static linkage elsewhere. An explicit dynamic request is rejected when the target has no dynamic loader.
- `check` compiles the facade, tests, smoke program, and native sources without running them. Its native matrix covers `x86_64-linux-gnu`, `aarch64-linux-gnu`, `riscv64-linux-gnu`, `aarch64-macos`, `x86_64-windows-gnu`, and `wasm32-wasi`; an explicit foreign `-Dtarget` checks that target instead.

## Platform boundaries

- The POSIX facade and wrapper are available only for width 8.
- `-fsys=pcre2-8` is restricted to the build machine's architecture, OS, and ABI; it does not provide cross-target system integration.
- A runtime provider must export all three code-unit widths declared by the translated header, plus POSIX entry points when that facade is used. Loading is explicit, with no fallback; targets without a dynamic loader cannot use runtime loading.
- WASI uses static linkage by default and cannot produce a shared artifact. A compile-only `check` result is not evidence that a target runs successfully.
- JIT execution is unavailable in this build; the facade reports that limitation rather than substituting an interpreter path for JIT.
