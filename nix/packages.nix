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
    cli-ext = (self.callPackage ./cli-ext {}).cli-ext;
    persistgraphql = (self.callPackage ./persistgraphql {}).persistgraphql;
    hasura-cli = self.callPackage ./hasura-cli {};
    vgo2nix = self.callPackage self.sources.vgo2nix {};
    hasuraHaskellPackages = pkgs.haskellPackages.override {
      overrides = import ./graphql-engine/hs-overlay.nix { inherit (pkgs) haskell; };
    };
    graphql-engine = self.hasuraHaskellPackages.graphql-engine;
  };
in lib.makeScope pkgs.newScope packages
