{pkgs, ...}: {
  imports = [
    # ./kanshi  # Replaced by hyprdynamicmonitors
    ./hyprdynamicmonitors
    ./libinput-gestures.nix
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
        splash_offset = 2.0;

        preload = [
          "~/.config/wallpapers/space_nebula.png"
        ];

        wallpaper = [
          ",~/.config/wallpapers/space_nebula.png"
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

  # Declaratively manage wallpaper file
  xdg.configFile."wallpapers/space_nebula.png" = {
    source = ./wallpapers/space_nebula.png;
  };
}
