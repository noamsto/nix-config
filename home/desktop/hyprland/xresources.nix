{
  lib,
  pkgs,
  osConfig,
  ...
}: let
  # Calculate DPI based on laptop-scale (default to 1.25 if not set)
  # 96 * 1.25 = 120, 96 * 2.0 = 192
  scale = builtins.fromJSON (osConfig.laptop-scale or "1.25");
  dpi = builtins.floor (96.0 * scale);

  # Records the active profile so the Hyprland start hook can replay it.
  xresourcesApply = import ./scripts/xresources-apply.nix {inherit pkgs;};
in {
  # XWayland HiDPI scaling via .Xresources
  # This provides proper scaling for XWayland apps when using force_zero_scaling

  home.packages = [xresourcesApply];

  home.file = {
    # Laptop profile: dynamic scale based on host config
    ".Xresources.laptop".text = ''
      Xft.dpi: ${toString dpi}
      Xft.autohint: 0
      Xft.lcdfilter: lcddefault
      Xft.hintstyle: hintfull
      Xft.hinting: 1
      Xft.antialias: 1
      Xft.rgba: rgb
    '';

    # Docked profile: 1.0 scale (96 DPI for external monitors)
    ".Xresources.docked".text = ''
      Xft.dpi: 96
      Xft.autohint: 0
      Xft.lcdfilter: lcddefault
      Xft.hintstyle: hintfull
      Xft.hinting: 1
      Xft.antialias: 1
      Xft.rgba: rgb
    '';

    # Default .Xresources symlinks to laptop profile (for undocked use)
    ".Xresources".source = lib.mkDefault (builtins.toFile "Xresources" ''
      Xft.dpi: ${toString dpi}
      Xft.autohint: 0
      Xft.lcdfilter: lcddefault
      Xft.hintstyle: hintfull
      Xft.hinting: 1
      Xft.antialias: 1
      Xft.rgba: rgb
    '');
  };
}
