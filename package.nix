# SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
# Copyright (c) 2026 the contributors to this fork.
#
# Injected source-only derivation; the Zig graph owns native compilation and artifacts.
# Flake and devenv entry points select the `linkage` and `codeUnitWidth` variants.
{ lib, stdenv, zig, linkage ? null, codeUnitWidth ? 8 }:

  # Reject cross package sets because `zig build` targets the compiler's native target.
assert stdenv.hostPlatform.system == stdenv.buildPlatform.system;
assert linkage == null || linkage == "static" || linkage == "dynamic";
assert codeUnitWidth == 8 || codeUnitWidth == 16 || codeUnitWidth == 32;

let
  src = lib.cleanSourceWith {
    src = ./.;
    # Exclude VCS/build/devenv state; keep source, tests, fixtures, and licence files.
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
  # Match the build manifest; the C version string also includes its release date.
  version = "10.49.0";

  inherit src;

  strictDeps = true;
  nativeBuildInputs = [ zig ];

  # Run one intended install build; disable the Zig setup hook's default phases.
  dontConfigure = true;
  dontBuild = true;
  dontCheck = true;
  # Prevent the hook from substituting its own `zig build test` check.
  # Set the prefix and Zig defaults explicitly below.
  dontUseZigCheck = true;
  dontAddPrefix = true;
  dontSetZigDefaultFlags = true;

  installPhase = ''
    runHook preInstall

    # Keep Zig caches under Nix's `TMPDIR`, outside the source tree.
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
    mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"

    # Install once; this compiles smoke but does not execute it.
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
      # Preserve PCRE2's exception; nixpkgs has no dedicated short identifier.
      shortName = "bsd3";
      fullName = "BSD 3-Clause \"New\" or \"Revised\" License, with the PCRE2 "
        + "binary-redistribution exception";
      free = true;
      redistributable = true;
      url = "https://github.com/PCRE2Project/pcre2/blob/main/LICENCE.md";
    };
    licenseFile = "LICENCE.md";

    platforms = lib.platforms.unix;

    mainProgram = "pcre2test";
  };
}