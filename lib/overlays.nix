# Reusable overlays for both NixOS and standalone Home Manager
inputs: [
  (final: _: {
    stable = import inputs.nixpkgs-stable {
      system = final.system;
      config.allowUnfree = true;
    };
    nur = import inputs.nur {
      nurpkgs = final;
      pkgs = final;
    };
  })

  (final: _: {
    fprintd = inputs.nixpkgs-fprintd-1_94_2.legacyPackages.${final.system}.fprintd;
  })
]
