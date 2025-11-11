{
  description = "A bash script to watch a file or folder and commit changes to a git repo";
<<<<<<< HEAD
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };
=======
>>>>>>> master
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
<<<<<<< HEAD
      lib = nixpkgs.lib;
=======
>>>>>>> master
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
<<<<<<< HEAD
          apps = rec {
            gitwatch = flake-utils.lib.mkApp { drv = packages.gitwatch; };
            default = gitwatch;
          };
=======
>>>>>>> master
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
