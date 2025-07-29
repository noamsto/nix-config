# ./overlays/default.nix
{inputs, ...}: {
  nixpkgs.overlays = [
    inputs.yazi.overlays.default

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

    # Hyprland overlay for clean package reference
    (final: _: {
      hyprland = inputs.hyprland.packages.${final.system}.hyprland;
    })
  ];
}
