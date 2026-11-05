{applyKeyed, ...}: {
  lib,
  osConfig,
  ...
}: let
  inherit (osConfig.nix-config.wallpapers) default;
  wallpapersDir = osConfig.nix-config.wallpapers.directory;
in {
  imports = [
    (applyKeyed ./hyprdynamicmonitors)
    ./libinput-gestures.nix
    ./polkit-agent-reregister.nix
  ];
  services = {
    # Hyprland polkit authentication agent
    hyprpolkitagent.enable = true;

    # Hyprpaper wallpaper daemon
    hyprpaper = {
      enable = true;
      settings = {
        ipc = "on";
        splash = false;
        splash_offset = 2;

        preload = [
          "${default}"
        ];

        wallpaper = [
          ",${default}"
        ];
      };
    };

    # Hyprsunset blue light filter for Hyprland
    hyprsunset = {
      enable = true;
      # transitions = {
      #   sunset = {
      #     calendar = "sunset";
      #     requests = [["temperature" "3000"]];
      #   };
      #   sunrise = {
      #     calendar = "sunrise";
      #     requests = [["identity"]];
      #   };
      # };
    };
  };

  home.file."Pictures/Wallpapers" = lib.mkIf (wallpapersDir != null) {
    source = wallpapersDir;
    recursive = true;
  };
}
