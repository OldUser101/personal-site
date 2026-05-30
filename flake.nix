{
  description = "ngill.net dev shell and build flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    tars.url = "github:OldUser101/tars";
  };

  outputs =
    {
      self,
      nixpkgs,
      tars,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));

      genDevBuildInputs = pkgs: [
        tars.packages.${pkgs.stdenv.hostPlatform.system}.default
        pkgs.curl
        pkgs.jq
        pkgs.yq
        pkgs.python314
        pkgs.python314Packages.python-frontmatter
        pkgs.prettier
      ];
    in
    {
      apps = forAllSystems (pkgs: {
        publish = {
          type = "app";
          program = builtins.toString (
            pkgs.writeShellScript "publish" ''
              export PATH=${pkgs.lib.makeBinPath (genDevBuildInputs pkgs)}:$PATH
              export ATPROTO_DID="did:plc:khwj2pmtsiuijj4jnuomle37"
              export SITE_KEY="3mn2jmgo7ge2y"
              export SOURCE_DIR="./content/blog/posts"
              export ROOT_DIR="./content/blog"
              export CONTENT_DIR="./content"
              export BUILD_DIR="./build"
              scripts/standard_site.sh
            ''
          );
        };
      });

      packages = forAllSystems (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          pname = "personal-site";
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
          buildInputs = genDevBuildInputs pkgs;
        };
      });
    };
}
