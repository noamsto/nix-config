{
  pkgs,
  config,
  ...
}: let
  kittyThemesPath = "${pkgs.kitty-themes}/share/kitty-themes/themes";
  waybarColorsDir = "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/waybar";

  theme-toggle = pkgs.writeShellApplication {
    name = "theme-toggle";
    runtimeInputs = with pkgs; [
      dconf # dconf write for GTK settings
      libnotify # notify-send
      hyprland # hyprctl
      swaynotificationcenter # swaync-client
      procps # pkill, pgrep
      kitty # kitty @ remote control
      tmux # tmux set/run-shell
      coreutils # cp, nohup
      networkmanagerapplet # nm-applet
      blueman # blueman-applet
      libsForQt5.qtstyleplugin-kvantum # kvantummanager
    ];
    text = ''
      export KITTY_THEMES_PATH="${kittyThemesPath}"
      export WAYBAR_COLORS_DIR="${waybarColorsDir}"
      ${builtins.readFile ./sh/theme-toggle.sh}
    '';
  };
in {
  home.packages = [theme-toggle];
}
