# SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
# Copyright (c) 2026 the contributors to this fork.
#
# One injected, source-only derivation over this repository's own `src/`.
# `linkage` and `codeUnitWidth` are arguments; the variants live in the entry
# points (flake.nix, devenv.nix), not here.
#
# The build graph owns everything native: the C flags, the source list, the
# per-target `config.h`, and every installed artifact, header, tool, licence
# record and pkg-config file. This file names the variant, the width, the CPU
# baseline, the optimization mode and the prefix, and nothing else — one writer
# per path.
{ lib, stdenv, zig, linkage ? null, codeUnitWidth ? 8 }:

# `zig build` targets the compiler's own native target, so a cross package set
# is refused rather than answered with a host-arch library under a foreign
# name. A native build on a remote builder of the same system is unaffected.
assert stdenv.hostPlatform.system == stdenv.buildPlatform.system;
assert linkage == null || linkage == "static" || linkage == "dynamic";
assert codeUnitWidth == 8 || codeUnitWidth == 16 || codeUnitWidth == 32;

let
  src = lib.cleanSourceWith {
    src = ./.;
    # VCS metadata, build outputs and devenv/direnv state are excluded;
    # `lib.cleanSource` alone knows none of them. Every source, test, fixture
    # and licence file a consumer or the graph needs is kept.
    filter = path: _type:
      let base = baseNameOf (toString path);
      in !(lib.elem base [
        ".git" ".jj" ".devenv" ".devenv.flake.nix" ".direnv"
        ".zig-cache" "zig-cache" "zig-out" "zig-pkg" "result"
      ] || lib.hasPrefix "result-" base);
  };
in
stdenv.mkDerivation {
  pname = "pcre2";
  # `build.zig.zon` `.version`, checked against the pinned upstream release at
  # configure time. The C library's own version string is "10.49 2026-09-28"
  # (`configure.ac:11-14`).
  version = "10.49.0";

  inherit src;

  strictDeps = true;
  nativeBuildInputs = [ zig ];

  # The Zig setup hook registers configure/build/check/install. This derivation
  # supplies the install itself and lets the other two out of the way, so
  # nothing is built once with the hook's defaults and again here.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  # Without this the Zig setup hook substitutes its own `zig build test` for the
  # check phase, which is a second, differently-flagged build of the same tree.
  dontUseZigCheck = true;
  # The hook would otherwise add its own `--prefix` and `-Dcpu=baseline
  # --release=safe`; both are named below instead, once.
  dontAddPrefix = true;
  dontSetZigDefaultFlags = true;

  installPhase = ''
    runHook preInstall

    # Caches under the Nix-provided TMPDIR, outside the unpacked source tree.
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"

    # One real install. `install` compiles and installs and runs nothing: at
    # width 8 it also compiles the smoke program, and at 16 or 32 the `test`,
    # `smoke` and `check` steps refuse that width with a stated reason rather
    # than passing empty.
    zig build install \
      --prefix "$out" \
      -j"''${NIX_BUILD_CORES:-1}" \
      -Doptimize=ReleaseSafe \
      -Dcpu=baseline \
      -Dcode-unit-width=${toString codeUnitWidth} \
      ${lib.optionalString (linkage != null) "-Dlinkage=${linkage}"}

    runHook postInstall
  '';

  meta = {
    description = "Perl-compatible regular expressions, 2nd API (PCRE2 10.49), "
      + "compiled from this repository's own C sources";

    longDescription = ''
      PCRE2 built from PCRE2Project/pcre2 at tag pcre2-10.49, commit
      6f9d7c1373262c541324a16a358785b33ef116cf, with Zig 0.16.0: the full
      code-unit-${toString codeUnitWidth} core with Unicode support, the
      interpreter and the DFA matcher, JIT functionality disabled because the
      JIT's sljit submodule is empty in this checkout and must not be fetched.
      Also installed: the public header, the POSIX wrapper at width 8,
      upstream's pcre2test, the API manual, the testdata oracle and the licence
      material.

      The library is BSD-3-Clause WITH PCRE2-exception and testdata/ is public
      domain; this fork's build, tests and packaging carry the same BSD terms
      under FORK-LICENSE.md. Nothing here promises a wholly static binary: the
      static variant is a static library artifact, and a consumer's C runtime is
      its own.
    '';

    homepage = "https://pcre2project.github.io/pcre2/";

    license = {
      # Upstream's own SPDX identifier (`LICENCE.md:4`). nixpkgs has no built-in
      # identifier for the PCRE2 exception, so the terms are spelled out rather
      # than mapped onto a plain BSD-3-Clause record that would drop the
      # exemption. `licenseFile` below names the shipped text.
      shortName = "bsd3";
      fullName = "BSD 3-Clause \"New\" or \"Revised\" License, with the PCRE2 "
        + "binary-redistribution exception";
      free = true;
      redistributable = true;
      url = "https://github.com/PCRE2Project/pcre2/blob/main/LICENCE.md";
    };
    licenseFile = "LICENCE.md";

    # These derivations build for the compiler's own native target, and only
    # Linux has been able to run a gate on them. `lib.platforms`, reached
    # through the injected `lib`: callPackage fills an injected `platforms`
    # from the package scope, which is a different set and has no `unix`.
    platforms = lib.platforms.unix;

    mainProgram = "pcre2test";
  };
}