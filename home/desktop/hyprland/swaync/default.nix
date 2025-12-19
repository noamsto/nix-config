{
  config,
  lib,
  pkgs,
  ...
}: {
  # Install swaync package directly instead of using service module
  # This avoids the service module overriding our out-of-store symlinks
  home.packages = [pkgs.swaynotificationcenter];

  # Use out-of-store symlinks for runtime theme switching
  xdg.configFile = {
    "swaync/config.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/swaync-config.json";

    "swaync/style.css".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/swaync-style.css";

    "swaync/icons".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/icons";
  };
}
