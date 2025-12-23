{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    inputs.vicinae.homeManagerModules.default
  ];
  home.packages = with pkgs; [
    libqalculate
  ];
  services.vicinae = {
    enable = true;
    systemd = {
      enable = true;
      autoStart = true;
    };
    # Settings are now in settings.json (new path) for runtime theme switching
    # The JSON file is symlinked out-of-store so theme-toggle.sh can modify it
  };

  # Override home-manager generated config with out-of-store symlink for runtime editing
  # Note: settings file path changed from vicinae.json to settings.json
  xdg.configFile."vicinae/settings.json" = lib.mkForce {
    source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/vicinae/vicinae-config.json";
    force = true; # Overwrite if file exists (prevents activation failures)
  };
}
