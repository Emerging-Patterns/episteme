{
  description = "episteme: primary-source Q&A over raw records, in Bend 2";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  # bendlang/bend's flake at the commit that packages 2.0.38 (the v2.0.38 tag
  # may still package 2.0.37)
  inputs.bend = {
    url = "github:bendlang/bend/042e797ebd1cfc060603e2682879909fe86fa8c2";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.ez = {
    url = "github:Emerging-Patterns/ez";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.bend.follows = "bend";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forEach = nixpkgs.lib.genAttrs systems;
      outputsFor = system:
        let
          ez = inputs.ez.lib.${system};
          ezBin = inputs.ez.packages.${system}.default;
          bend = inputs.bend.packages.${system}.default;
          bolt = ez.toolPackage { name = "bolt"; src = self; inherit bend; wrapFlags = ez.rtsFlags bend [ "--gpu" "off" ]; };
          bend-cc = ez.bend-cc;
          # the CLI, compiled with `bend main.bend -o`
          episteme = ez.mkPackage { inherit bend; src = self; };
        in {
          packages = {
            inherit bend bend-cc;
            ez = ezBin;
            inherit bolt episteme;
            default = episteme;
          };

          checks = {
            proofs = ez.mkProofs { ez = ezBin; src = self; };
            lint = ez.mkLint { src = self; };
            # the IO shell end to end on the synthetic fixtures; python3
            # runs the fake Honcho, and git builds and reads the fixture repos
            smoke = nixpkgs.legacyPackages.${system}.runCommand "smoke"
              { nativeBuildInputs = with nixpkgs.legacyPackages.${system}; [ python3 git ]; } ''
              EPISTEME=${episteme}/bin/episteme bash ${self}/tests/smoke.sh
              echo ok > $out
            '';
          };

          devShells.default = ez.mkShell {
            src = self;
            packages = [
              bend
              bend-cc
              ezBin
            ];
          };
        };
      perSystem = forEach outputsFor;
      each = name: forEach (system: perSystem.${system}.${name});
    in {
      packages = each "packages";
      checks = each "checks";
      devShells = each "devShells";
    };
}
