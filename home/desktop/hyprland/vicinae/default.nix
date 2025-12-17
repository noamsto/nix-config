{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    inputs.vicinae.homeManagerModules.default # enable Home Manager
  ];
  home.packages = with pkgs; [
    libqalculate
  ];
  services.vicinae = {
    enable = true;
    autoStart = true;
    # Settings are now in vicinae-config.json for runtime theme switching
    # The JSON file is symlinked out-of-store so theme-toggle.sh can modify it
  };

  # Override home-manager generated config with out-of-store symlink for runtime editing
  xdg.configFile."vicinae/vicinae.json" = lib.mkForce {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/vicinae/vicinae-config.json";
  };
}
