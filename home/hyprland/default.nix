{config, ...}: {
  imports = [./waybar ./dunst];
  xdg.configFile = {
    # "hypr/hyprland.conf".source = ./hyprland.conf;  # TODO: Enable once config is settled
    "hypr/hyprland.conf".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/hyprland/hyprland.conf";
    "hypr/start.sh".source = ./start.sh;
  };
}
