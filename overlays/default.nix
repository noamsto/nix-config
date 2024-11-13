# ./overlays/default.nix
{inputs, ...}: {
  nixpkgs.overlays = [
    inputs.hyprpanel.overlay
    inputs.yazi.overlays.default

    (final: _: {
      stable = import inputs.nixpkgs-stable {
        system = final.system;
        config.allowUnfree = true;
      };
    })
    (_final: super: {utillinux = super.util-linux;})
    (final: _: {
      matugen = inputs.matugen.packages.${final.system}.default;
    })
  ];
}
