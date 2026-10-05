# SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
# Copyright (c) 2026 the contributors to this fork.
#
# The canonical development environment. Tools in `packages`; the SDK itself is
# never in the shell. Its variants are named as lazy `outputs`, so entering the
# shell instantiates nothing and `devenv build outputs.static` builds the same
# package.nix the flake exposes.
#
# Scratch locations are read from the environment at shell time and only where
# the caller has not already chosen a value: a committed file names no host
# path, and a caller's own scratch is not overridden.
#
# Each entry that reaches `zig build` settles the same question for itself
# before it runs — its working directory, its build caches and its flags —
# so a route needs no `HOST_SCRATCH_ROOT` to stay out of this checkout, and
# still lets a caller who exported one of those win. The state the shell CLI
# already created — devenv's runtime sockets, `DEVENV_ROOT`, `DEVENV_STATE` — is
# not something this file can move after the fact.
#
# Every entry below names this directory for itself. `devenv shell -- <name>`
# runs an entry in the **caller's** working directory, and that directory is
# not this tree: a `--from path:<sdk>` run creates its own project directory
# beside the SDK, and `DEVENV_ROOT` points there. An entry that assumed it was
# already in this repository looked for `UPSTREAM.sha256` and `consumer/` in a
# directory that has neither. `./.` below is the directory holding *this* file,
# which is the one fact that does not depend on where the caller is standing.
# It covers scripts as well as tasks, because devenv materialises both as
# generated shell programs that inherit the caller's directory.
#
# Every `zig build` below carries the workspace's gate recipe — `-j8`, an
# explicit external `--cache-dir` and `--summary all` — because a canonical
# entry that left the count to the host ran at whatever the machine happened to
# offer, and one that left the cache to Zig wrote `.zig-cache` into this
# checkout. They are named before `"$@"`, which stays last, and every one of
# them is read last-wins, so a caller's own `-j`, `--cache-dir`, `--summary` or
# `-D…` still wins over what this file names.
{ pkgs, ... }:

let
  sdk = linkage: pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16; inherit linkage; };

  lib = pkgs.lib;

  # This directory, as a plain string.
  #
  # `builtins.toString`, not a bare `${./.}`: interpolating the path itself asks
  # Nix for its store copy, which is a read-only copy of this whole working tree
  # rather than the tree these entries are gates of. `escapeShellArg` quotes
  # the rendered string once, so a directory with a space or a quote in it
  # still reaches the shell as a single argument.
  sdkRoot = builtins.toString ./.;

  # `|| exit 1`, because a `cd` that fails leaves the body running in the
  # caller's own directory, which is the one directory these entries must never
  # build in: it has no `build.zig`, no `consumer/` and no `UPSTREAM.sha256`.
  inSdk = "cd ${lib.escapeShellArg sdkRoot} || exit 1";
  inConsumer = "cd ${lib.escapeShellArg (sdkRoot + "/consumer")} || exit 1";

  # Every real `zig build` below passes `--cache-dir` explicitly, so Zig never
  # falls back to the `.zig-cache` it writes beside `build.zig` — inside this
  # checkout for the five SDK-root entries, and a second one inside
  # `<sdk>/consumer` for `sdk.consumer`. A caller's own cache variables win and
  # are never overwritten: `ZIG_LOCAL_CACHE_DIR` is both the value `enterShell`
  # exports from `HOST_SCRATCH_ROOT` and the one a caller sets for itself, and
  # this runs in the body as well as in `enterShell`, because a `TasksRun` route
  # never reaches that hook. A missing one is filled from `XDG_CACHE_HOME`, else
  # from `TMPDIR`, because both are scratch the caller already named; with the
  # local cache still unnamed the entry stops and says which variable is
  # missing. No host path is named here: `/tmp` and `/var/tmp` are not approved
  # mounts, this checkout is not scratch, and neither is written without the
  # caller having said so.
  requireExternalCache = ''
    if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ] || [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
      if [ -n "''${XDG_CACHE_HOME:-}" ]; then
        cache_root="''${XDG_CACHE_HOME}/foundation-libs/pcre2"
      elif [ -n "''${TMPDIR:-}" ]; then
        cache_root="''${TMPDIR}/foundation-libs/pcre2"
      elif [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
        echo "pcre2: ZIG_LOCAL_CACHE_DIR is unset, and neither XDG_CACHE_HOME nor" >&2
        echo "TMPDIR names scratch either, so there is nowhere approved outside" >&2
        echo "this checkout for build state or an install prefix. Export one." >&2
        exit 1
      else
        cache_root="''${ZIG_LOCAL_CACHE_DIR%/zig-local}"
      fi
      if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="$cache_root/zig-local"
      fi
      if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="$cache_root/zig-global"
      fi
    fi
    mkdir -p "''${ZIG_LOCAL_CACHE_DIR}" "''${ZIG_GLOBAL_CACHE_DIR}"
  '';
in
{
  packages = [
    # The pinned compiler. A versionless `zig` on PATH is not this and must not
    # gate this SDK.
    pkgs.zig_0_16
    # The SDK's other consumer is a C program against an installed prefix.
    pkgs.stdenv.cc
    pkgs.pkg-config
    pkgs.gnumake
    pkgs.gdb
    pkgs.git
  ];

  outputs = {
    static = sdk "static";
    shared = sdk "dynamic";
    # No `linkage`: the SDK's own policy, dynamic on GNU libc and static
    # elsewhere.
    default = sdk null;
  };

  enterShell = ''
    if [ -n "''${HOST_SCRATCH_ROOT:-}" ]; then
      if [ -z "''${XDG_CACHE_HOME:-}" ]; then
        export XDG_CACHE_HOME="''${HOST_SCRATCH_ROOT}/cache"
      fi
      if [ -z "''${ZIG_GLOBAL_CACHE_DIR:-}" ]; then
        export ZIG_GLOBAL_CACHE_DIR="''${HOST_SCRATCH_ROOT}/cache/zig"
      fi
      if [ -z "''${ZIG_LOCAL_CACHE_DIR:-}" ]; then
        export ZIG_LOCAL_CACHE_DIR="''${HOST_SCRATCH_ROOT}/cache/foundation-libs/pcre2/zig-local"
      fi
      if [ -z "''${TMPDIR:-}" ]; then
        export TMPDIR="''${HOST_SCRATCH_ROOT}/tmp"
      fi
      mkdir -p "$XDG_CACHE_HOME" "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR" "$TMPDIR"
    fi
  '';

  scripts = {
    "sdk.build" = {
      description = "Compile the C artifacts and install them under the caller's local cache";
      exec = ''
        ${inSdk}
        ${requireExternalCache}
        # An external `--prefix`. `zig build`'s own default is `zig-out` beside
        # the build root, which in this workspace is a volume mount, so the
        # default writes a delivery tree into the source repository. The
        # prefix belongs under `ZIG_LOCAL_CACHE_DIR`: the caller's own value
        # first, then the one `enterShell` fills in from `HOST_SCRATCH_ROOT`,
        # then `XDG_CACHE_HOME` or `TMPDIR` — the preamble above has already
        # settled that or stopped. The shell's `:?` form stays under it as a
        # second refusal, not as a fallback.
        #
        # `-j8 --cache-dir … --summary all` is the workspace's gate recipe, and
        # every `zig build` in this file names it, before `"$@"`. `"$@"` still
        # comes last and each of those flags is read last-wins, so a caller who
        # wants another count, another cache, another summary or a `-D…` still
        # wins over what is named here.
        zig build --prefix "''${ZIG_LOCAL_CACHE_DIR:?}/pcre2-install" -j8 --cache-dir "''${ZIG_LOCAL_CACHE_DIR:?}" --summary all "$@"
      '';
    };

    "sdk.test" = {
      description = "Run the behavioural suite in Debug";
      exec = ''
        ${inSdk}
        ${requireExternalCache}
        # No `--prefix`: `test` installs nothing. The cache is the preamble's,
        # outside this checkout, and the flags are the workspace's gate recipe,
        # named before `"$@"` so a caller still wins with its own.
        zig build test -j8 --cache-dir "''${ZIG_LOCAL_CACHE_DIR:?}" --summary all "$@"
      '';
    };

    "sdk.test-release-safe" = {
      description = "Run the behavioural suite with the optimizer on";
      exec = ''
        ${inSdk}
        ${requireExternalCache}
        zig build test -Doptimize=ReleaseSafe -j8 --cache-dir "''${ZIG_LOCAL_CACHE_DIR:?}" --summary all "$@"
      '';
    };

    "sdk.smoke" = {
      description = "Run the deterministic smoke program";
      exec = ''
        ${inSdk}
        ${requireExternalCache}
        zig build smoke -j8 --cache-dir "''${ZIG_LOCAL_CACHE_DIR:?}" --summary all "$@"
      '';
    };

    "sdk.check" = {
      description = "Compile the core, facade, tests and smoke for the six baseline targets, running nothing";
      exec = ''
        ${inSdk}
        ${requireExternalCache}
        # `check` compiles six baseline targets and runs nothing, so it names no
        # prefix; it is still a build, so it keeps the external cache and the
        # gate flags.
        zig build check -j8 --cache-dir "''${ZIG_LOCAL_CACHE_DIR:?}" --summary all "$@"
      '';
    };

    "sdk.integrity" = {
      description = "Replay UPSTREAM.sha256 over the native sources, headers, licences and oracle bytes";
      exec = ''
        ${inSdk}
        sha256sum -c UPSTREAM.sha256 "$@"
      '';
    };

    "sdk.consumer" = {
      description = "Run the separate consumer package against this one";
      exec = ''
        ${inConsumer}
        ${requireExternalCache}
        # No `--prefix`: this package installs nothing. Its install step hangs
        # on the executable's Compile step and installs no file
        # (`consumer/build.zig:145-149`), so what this entry produces is a
        # proof and a proof is not a deliverable. The cache is the preamble's —
        # `ZIG_LOCAL_CACHE_DIR`, which `enterShell` exports and the preamble
        # otherwise fills from `XDG_CACHE_HOME` or `TMPDIR` — because this body
        # builds in `<sdk>/consumer`, where a default `.zig-cache` would be a
        # second one inside this checkout; `--cache-dir` names it instead. The
        # gate flags come before `"$@"`, as everywhere.
        zig build run -j8 --cache-dir "''${ZIG_LOCAL_CACHE_DIR:?}" --summary all "$@"
      '';
    };
  };
}