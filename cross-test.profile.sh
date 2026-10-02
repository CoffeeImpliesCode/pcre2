#!/usr/bin/env bash
# cross-test.profile.sh — settings only, for the `cross-test` harness.
#
# `cross-test` is run from this package root. It compiles and runs this
# package's real `test` step, `zig build test -Dtarget=TARGET`, once per target
# of the published Zig 0.16.0 Tier 1/2 matrix (53 platforms), and it owns the
# matrix, the runner policy and the QEMU/Wine/Wasmtime detection. This file
# configures none of that and must not: it holds ordinary Bash variable
# definitions only, no `cross_build_command`/`cross_artifact` hooks (so the
# standard Zig-build mode is used), no `CROSS_MATRIX` and no `TARGETS` (so the
# full published matrix is selected, never a subset), and no host-specific
# path. Every value here is a default that the command line overrides, so
# `cross-test --jobs N --build-jobs N --build-timeout N --timeout N` still
# wins; see `cross-test --help`.
#
# `CROSS_LIBC_RUNTIMES` is deliberately absent: it names a directory of foreign
# libc loaders on the machine running the harness, which is that machine's
# business and not this package's. Supply it in the environment when a
# GNU-libc cell needs one — which on this matrix is the two MinGW targets,
# whose `Abi` is `gnu`.
#
# Licence: **none asserted.** This is a fork-authored file, like `build.zig`,
# `translate.h`, `zig/root.zig`, `tests.zig` and `consumer/`. Upstream PCRE2 is
# BSD-3-Clause WITH PCRE2-exception and that grant is untouched; it does not
# reach this file, and `NOTICE.md` records the fork's own files as unassigned.

# The step that runs the public Zig API tests. This is the harness default too;
# it is named here so the package's contract is in the package.
CROSS_BUILD_STEP=test

# One target at a time inside one `zig build`. Per target this graph compiles
# the 29-unit 8-bit core, the POSIX wrapper, `pcre2test` and the translate-c
# aggregate, and links the facade twice; two parallel jobs per target keeps
# that from serialising.
CROSS_BUILD_JOBS=2

# Deadline for one `zig build test -Dtarget=…`. `test` depends only on the
# facade unit tests and the smoke program, so this covers compiling the core
# for that target and running its ten tests.
CROSS_BUILD_TIMEOUT=1800

# Per-test-binary deadline, passed on as `zig build --test-timeout`. The ten
# tests replay a fifteen-case fixture table and a handful of boundary cases;
# they are quick, and this only has to be above a normal run. No run of the
# full matrix has been observed here yet.
CROSS_TIMEOUT=600
