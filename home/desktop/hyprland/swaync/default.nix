{
  config,
  lib,
  pkgs,
  ...
}: {
  # Install swaync package directly instead of using service module
  # This avoids the service module overriding our out-of-store symlinks
  home.packages = [pkgs.swaynotificationcenter];

  # Use out-of-store symlinks for config (development iteration)
  # NOTE: style.css is NOT symlinked - it's generated directly by theme-toggle
  # from swaync-colors-*.css + swaync-style-base.css
  xdg.configFile = {
    "swaync/config.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/swaync-config.json";

    "swaync/icons".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/icons";
  };
}
