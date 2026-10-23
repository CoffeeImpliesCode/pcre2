# SPDX-License-Identifier: BSD-3-Clause WITH PCRE2-exception
# Copyright (c) 2026 the contributors to this fork.
{
  description = "PCRE2 10.49, compiled from this repository's own C sources, with a Zig facade";

  # Pin nixpkgs to make flake evaluation reproducible.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;

      # Enumerate supported systems for pure evaluation.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forEachSystem = f:
        lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Build three variants from one derivation; default keeps its target policy.
      sdk = pkgs: args:
        pkgs.callPackage ./package.nix ({ zig = pkgs.zig_0_16; } // args);

      # Reuse devenv's development tool list.
      devEnv = pkgs: pkgs.callPackage ./devenv.nix { };
    in
    {
      packages = forEachSystem (pkgs: {
        default = sdk pkgs { };
        static = sdk pkgs { linkage = "static"; };
        shared = sdk pkgs { linkage = "dynamic"; };
      });

      # Keep shell tools separate from the SDK package build.
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