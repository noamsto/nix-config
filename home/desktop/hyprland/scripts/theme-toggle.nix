{
  pkgs,
  config,
  lib,
  ...
}: let
  paletteEnv = import ../../../theme/palette-env.nix {inherit pkgs config lib;};

  notifyIconLight = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Light/48x48/status/weather-clear.svg";
  notifyIconDark = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark/48x48/status/weather-clear-night.svg";

  theme-toggle = pkgs.writeShellApplication {
    name = "theme-toggle";
    runtimeInputs =
      paletteEnv.coreRuntimeInputs
      ++ (with pkgs; [
        dconf
        libnotify
        hyprland
        procps
        networkmanagerapplet
        libsForQt5.qtstyleplugin-kvantum
        quickshell
        kitty
      ]);
    text = ''
      ${paletteEnv.exports}
      export NOTIFY_ICON_LIGHT="${notifyIconLight}"
      export NOTIFY_ICON_DARK="${notifyIconDark}"
      export THEME_APPLY_LIB="${paletteEnv.libScript}"

      ${builtins.readFile ./sh/theme-toggle.sh}
    '';
  };
in {
  config = {
    home.packages = [theme-toggle];
    programs.theme-toggle.package = theme-toggle;
  };
}
