{lib, ...}: {
  # XWayland HiDPI scaling via .Xresources
  # This provides proper scaling for XWayland apps when using force_zero_scaling

  home.file = {
    # Laptop profile: 2.0 scale (96 * 2.0 = 192 DPI)
    ".Xresources.laptop".text = ''
      Xft.dpi: 192
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
      Xft.dpi: 192
      Xft.autohint: 0
      Xft.lcdfilter: lcddefault
      Xft.hintstyle: hintfull
      Xft.hinting: 1
      Xft.antialias: 1
      Xft.rgba: rgb
    '');
  };
}
