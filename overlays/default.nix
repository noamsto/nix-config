# ./overlays/default.nix
{inputs, ...}: {
  nixpkgs.overlays = [
    inputs.hyprpanel.overlay
    inputs.yazi.overlays.default
    inputs.claude-code.overlays.default

    (final: _: {
      stable = import inputs.nixpkgs-stable {
        system = final.system;
        config.allowUnfree = true;
      };
    })
    (_final: super: {utillinux = super.util-linux;})

    (final: _: {
      fprintd = inputs.nixpkgs-fprintd-1_94_2.legacyPackages.${final.system}.fprintd;
    })

    (final: _: {
      devenv = inputs.devenv.packages.${final.system}.default;
    })
  ];
}
