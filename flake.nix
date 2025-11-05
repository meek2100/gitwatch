{
  description = "A bash script to watch a file or folder and commit changes to a git repo";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      packages = flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
          # --- ADDED LINE ---
          lib = nixpkgs.lib;
        in
        {
          packages = rec {
            gitwatch = pkgs.callPackage ./gitwatch.nix { };
            default = gitwatch;
          };
          apps = rec {
            gitwatch = flake-utils.lib.mkApp { drv = packages.gitwatch; };
            default = gitwatch;
          };
        }
      );
    in
    packages
    // {
      modules = [ ./module.nix ];
      license = nixpkgs.lib.licenses.gpl3Plus;
    };
}
