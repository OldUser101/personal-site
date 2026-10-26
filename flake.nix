{
  description = "ngill.net dev shell and build flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
          system: f (import nixpkgs { inherit system; })
        );
    in
    {
      packages = forAllSystems (pkgs: {
        default =
          let
            site = import ./site.nix;
            lib = import ./lib.nix { inherit pkgs; };
          in
          lib.buildSite site;

        guestbook = pkgs.rustPlatform.buildRustPackage {
          pname = "guestbook";
          version = "0.1.0";

          src = ./server;

          cargoLock = {
            lockFile = ./server/Cargo.lock;
          };
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            prettier
            busybox

            python314
            python3Packages.beautifulsoup4
            python3Packages.pygments
            python3Packages.catppuccin

            cargo
            rustc
            rustfmt
            rust-analyzer
            rustPackages.clippy
          ];

          shellHook = ''
            export NGILL_NET_GUESTBOOK_ADDR="127.0.0.1"
            export NGILL_NET_GUESTBOOK_PORT="8080"
            export NGILL_NET_GUESTBOOK_LOG_LEVEL="trace"
            export NGILL_NET_GUESTBOOK_STORE="/data/ngill"
          '';
        };
      });
    };
}
