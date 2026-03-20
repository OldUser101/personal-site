{
  description = "nathanjgill.uk dev shell and build flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    tars = {
      url = "github:OldUser101/tars";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, tars }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems
        (system: f (import nixpkgs { inherit system; }));
    in {
      packages = forAllSystems (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "nathanjgill.uk";
          version = "1.0";

          src = self;

          nativeBuildInputs = [
            tars.packages.${pkgs.stdenv.hostPlatform.system}.default
            pkgs.python314
            pkgs.python314Packages.python-frontmatter
          ];

          buildPhase = ''
            # Verify plugins before patching
            tars plugin verify

            patchShebangs ./plugins/*

            # Skip plugin verification, shebangs patched
            # causing verification to fail.
            tars build --no-verify
          '';

          installPhase = ''
            mkdir -p $out
            cp -r build/{*,.*} $out/
          '';
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = [
            tars.packages.${pkgs.stdenv.hostPlatform.system}.default
            pkgs.python314
            pkgs.python314Packages.python-frontmatter
            pkgs.prettier
          ];
        };
      });
    };
}
