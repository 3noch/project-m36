let
  pkgs = import <nixpkgs> {};
in
(pkgs.callPackage ./default.nix {
  devMode = true;
  haskellPackages = pkgs.haskell.packages.ghc802;
}).env
