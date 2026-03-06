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
  };

  # Seed vicinae config only if it doesn't exist yet; vicinae manages it at runtime
  home.activation.seedVicinaeConfig = let
    seedConfig = pkgs.writeText "vicinae-seed-config.json" (builtins.toJSON {
      "$schema" = "https://vicinae.com/schemas/config.json";
      keybinding = "default";
      theme.dark.name = "vicinae-dark";
      keybinds = {};
      providers = {
        applications.preferences.paths = [
          "${config.home.homeDirectory}/.local/share/applications"
          "/var/lib/flatpak/exports/share/applications"
          "/etc/profiles/per-user/${config.home.username}/share/applications"
          "/run/current-system/sw/share/applications"
        ];
        clipboard.preferences.monitoring = true;
      };
    });
  in
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      config_path="${config.xdg.configHome}/vicinae/settings.json"
      if [ ! -f "$config_path" ]; then
        mkdir -p "$(dirname "$config_path")"
        cp ${seedConfig} "$config_path"
        chmod 644 "$config_path"
      fi
    '';
}
