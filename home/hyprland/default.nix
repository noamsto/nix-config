{
  pkgs,
  config,
  ...
}: {
  wayland.windowManager.hyprland.enable = true;

  xdg.configFile."hypr/hyprland.conf".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/hyprland/hyprland.conf";
  home.packages = with pkgs; [
    papirus-icon-theme
    bibata-cursors

    kdePackages.dolphin
  ];
}
