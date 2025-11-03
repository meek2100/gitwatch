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
        in
        {
          packages = rec {
            gitwatch = pkgs.callPackage ./gitwatch.nix { };
            default = gitwatch;
          };
        }
      );
    in
    packages // { modules = [ ./module.nix ]; };
}
