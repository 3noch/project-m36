{ haskell }:
{
  haskellPackages = haskell.packages.ghc802.override {
    overrides = self: super: {
      distributed-process-client-server = haskell.lib.dontCheck (haskell.lib.doJailbreak super.distributed-process-client-server);
      distributed-process-extras = haskell.lib.doJailbreak super.distributed-process-extras;
      megaparsec = self.callHackage "megaparsec" "4.4.0" {};
      persistent = super.persistent_2_2_4_1;
      persistent-template = super.persistent-template_2_1_8_1;
    };
  };
}
