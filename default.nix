{ pkgs, devMode ? false }:
let
  common = pkgs.callPackage ./common.nix {};

  package =
    { mkDerivation, aeson, attoparsec, base, base64-bytestring, binary
    , bytestring, Cabal, cassava, conduit, containers, data-interval
    , deepseq, deepseq-generics, directory, distributed-process
    , distributed-process-client-server, distributed-process-extras
    , either, extended-reals, filepath, ghc, ghc-boot, ghc-paths, Glob
    , gnuplot, hashable, hashable-time, haskeline, http-api-data, HUnit
    , list-t, megaparsec, monad-parallel, MonadRandom, mtl, network
    , network-transport, network-transport-tcp, old-locale
    , optparse-applicative, parallel, path-pieces, persistent
    , persistent-template, random, random-shuffle, resourcet, stdenv
    , stm, stm-containers, template-haskell, temporary, text, time
    , transformers, unix, unordered-containers, uuid, uuid-aeson
    , vector, vector-binary-instances, websockets

    , cabal-install
    }:
    mkDerivation {
      pname = "project-m36";
      version = "0.1";
      src = ./.;
      isLibrary = true;
      isExecutable = true;
      libraryHaskellDepends = [
        aeson attoparsec base base64-bytestring binary bytestring cassava
        conduit containers data-interval deepseq deepseq-generics directory
        distributed-process distributed-process-client-server
        distributed-process-extras either extended-reals filepath ghc
        ghc-boot ghc-paths Glob gnuplot hashable hashable-time haskeline
        http-api-data list-t monad-parallel MonadRandom mtl
        network-transport network-transport-tcp old-locale
        optparse-applicative parallel path-pieces persistent
        persistent-template random-shuffle resourcet stm stm-containers
        temporary text time transformers unix unordered-containers uuid
        vector vector-binary-instances
      ] ++ pkgs.lib.optional devMode cabal-install;

      executableHaskellDepends = [
        aeson attoparsec base base64-bytestring binary bytestring Cabal
        cassava conduit containers data-interval deepseq deepseq-generics
        directory either filepath ghc ghc-paths gnuplot hashable
        hashable-time haskeline http-api-data HUnit list-t megaparsec
        MonadRandom mtl optparse-applicative parallel path-pieces
        persistent persistent-template random stm stm-containers
        template-haskell temporary text time transformers
        unordered-containers uuid uuid-aeson vector vector-binary-instances
        websockets
      ];
      testHaskellDepends = [
        aeson attoparsec base base64-bytestring binary bytestring Cabal
        cassava conduit containers data-interval deepseq deepseq-generics
        directory either filepath gnuplot hashable hashable-time haskeline
        http-api-data HUnit list-t megaparsec MonadRandom mtl network
        network-transport-tcp optparse-applicative parallel path-pieces
        persistent persistent-template random stm stm-containers
        template-haskell temporary text time transformers
        unordered-containers uuid uuid-aeson vector vector-binary-instances
        websockets
      ];
      homepage = "https://github.com/agentm/project-m36";
      description = "Relational Algebra Engine";
      license = stdenv.lib.licenses.publicDomain;
    };

in pkgs.haskell.lib.dontCheck (common.haskellPackages.callPackage package {})
