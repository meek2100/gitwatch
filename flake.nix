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
      # --- ADDED LINE ---
      lib = nixpkgs.lib;
      packages = flake-utils.lib.eachDefaultSystem (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
           # --- REMOVED LINE ---
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
      # --- MODIFIED: Use lib (defined above) ---
      license = lib.licenses.gpl3Plus;
    };
}
