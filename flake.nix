# SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
# Copyright (c) 2026 the contributors to this fork.
{
  description = "PCRE2 10.49, compiled from this repository's own C sources, with a Zig facade";

  # Fixed rev: a flake whose nixpkgs floats answers a different question each
  # time it is evaluated. The driver owns `flake.lock`; this is the rev it pins.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # No `builtins.currentSystem`: a flake evaluation is pure, and the
      # supported systems are named here.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forEachSystem = f:
        lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # One package.nix, three variants. `default` passes no `linkage`, so the
      # SDK's own policy runs — dynamic on a GNU-libc target, static elsewhere.
      sdk = pkgs: args:
        pkgs.callPackage ./package.nix ({ zig = pkgs.zig_0_16; } // args);

      # The same tool list devenv uses, read rather than restated.
      devEnv = pkgs: pkgs.callPackage ./devenv.nix { };
    in
    {
      packages = forEachSystem (pkgs: {
        default = sdk pkgs { };
        static = sdk pkgs { linkage = "static"; };
        shared = sdk pkgs { linkage = "dynamic"; };
      });

      # Tools only. Building the SDK is what `nix build` is for, and devenv is
      # the canonical development environment for it.
      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          name = "pcre2-sdk";
          packages = (devEnv pkgs).packages;
          shellHook = ''
            echo "pcre2 SDK shell — Zig 0.16.0 from the pinned nixpkgs; the SDK itself is not built here."
            echo "Canonical: devenv shell. Try: devenv sdk.test | devenv sdk.smoke | devenv sdk.check"
          '';
        };
      });
    };
}