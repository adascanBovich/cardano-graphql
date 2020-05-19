{ pkgs, lib }:

let
  # TODO: filter src to just the files needed to build
  src = ../.;
  packages = self: {
    sources = import ./sources.nix;
    cardano-graphql-src = src;
    nodejs = pkgs.nodejs-12_x;
    inherit (self.callPackage self.sources.yarn2nix {}) yarn2nix mkYarnModules mkYarnPackage;
    inherit (import self.sources.niv {}) niv;
    cardano-graphql = self.callPackage ./cardano-graphql.nix {};
    persistgraphql = (self.callPackage ./node-packages {}).persistgraphql;
    hasura-cli = self.callPackage ./go-packages/hasura-cli.nix {};
    vgo2nix = self.callPackage self.sources.vgo2nix {};
    hasuraHaskellPackages = pkgs.haskellPackages.override {
      overrides = import ./graphql-engine/hs-overlay.nix { inherit (pkgs) haskell; };
    };
    graphql-engine = self.hasuraHaskellPackages.graphql-engine;
  };
in lib.makeScope pkgs.newScope packages
