#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
# Copyright (c) 2026 the contributors to this fork.
#
# Settings for cross-test's standard Zig build; command-line options override these defaults.
#
# Supply `CROSS_LIBC_RUNTIMES` from the host environment when GNU-libc target loaders are needed.
#
# This fork's grant and inventory are recorded in `FORK-LICENSE.md` and `NOTICE.md`; upstream's licence is unchanged.

# Run the public Zig API tests.
CROSS_BUILD_STEP=test

# Parallel jobs within each target build.
CROSS_BUILD_JOBS=2

# Deadline for each target build, in seconds.
CROSS_BUILD_TIMEOUT=1800

# Deadline for each test-binary run, in seconds.
CROSS_TIMEOUT=600
