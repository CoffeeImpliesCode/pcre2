# SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
# Copyright (c) 2026 the contributors to this fork.
#
# Canonical shell; lazy package variants use the same `package.nix` derivation.
#
# Fill caller-unset scratch variables without committing host paths.
#
# Each task sets its working directory, caches, and flags; caller values win.
# Devenv state paths and sockets are created before this file runs.
#
# Tasks may start in the caller's directory; entries explicitly switch to this SDK root.
#
# Set `-j8`, external cache, and summary defaults before `"$@"` so caller options win.
{ pkgs, ... }:

let
  sdk = linkage: pkgs.callPackage ./package.nix { zig = pkgs.zig_0_16; inherit linkage; };

  lib = pkgs.lib;

  # Resolve and shell-quote this file's source path, not a read-only Nix store copy.
  sdkRoot = builtins.toString ./.;

  # Stop if `cd` fails; tasks must not build from the caller's directory.
  inSdk = "cd ${lib.escapeShellArg sdkRoot} || exit 1";
  inConsumer = "cd ${lib.escapeShellArg (sdkRoot + "/consumer")} || exit 1";

  # Keep both Zig caches outside the checkout; caller-specified locations take precedence.
  # Fall back to `XDG_CACHE_HOME` or `TMPDIR`, and fail if neither provides external scratch.
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
    # Use the pinned Zig 0.16 compiler.
    # C toolchain and pkg-config for the consumer package.
    pkgs.zig_0_16
    pkgs.stdenv.cc
    pkgs.pkg-config
    pkgs.gnumake
    pkgs.gdb
    pkgs.git
  ];

  outputs = {
    static = sdk "static";
    shared = sdk "dynamic";
    # Leave linkage unset in the default variant so the target policy applies.
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
        # Install under the external local cache, not beside `build.zig`.
        # Defaults precede `"$@"` so caller-supplied flags override them.
        zig build --prefix "''${ZIG_LOCAL_CACHE_DIR:?}/pcre2-install" -j8 --cache-dir "''${ZIG_LOCAL_CACHE_DIR:?}" --summary all "$@"
      '';
    };

    "sdk.test" = {
      description = "Run the behavioural suite in Debug";
      exec = ''
        ${inSdk}
        ${requireExternalCache}
        # Run tests without installing; use the external cache and overridable gate defaults.
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
        # Compile-only check; no prefix is needed, but keep external cache and gate defaults.
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
        # Run the consumer proof without installing files; use the shared external cache.
        zig build run -j8 --cache-dir "''${ZIG_LOCAL_CACHE_DIR:?}" --summary all "$@"
      '';
    };
  };
}