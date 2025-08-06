{
  config,
  lib,
  ...
}: {
  # Enable swaync package but disable Home Manager service config generation
  services.swaync.enable = true;

  # Use out-of-store symlinks for easier development iteration
  xdg.configFile = {
    "swaync/config.json" = lib.mkForce {source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/swaync-config.json";};

    "swaync/style.css" = lib.mkForce {source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/swaync-style.css";};
  };
}
