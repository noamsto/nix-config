{pkgs, ...}: {
  imports = [
    ./kanshi
  ];

  # Hyprland polkit authentication agent
  services.hyprpolkitagent.enable = true;

  # Hyprpaper wallpaper daemon
  services.hyprpaper = {
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

  # Declaratively manage wallpaper file
  xdg.configFile."wallpapers/space_nebula.png" = {
    source = ./wallpapers/space_nebula.png;
  };

  # Hyprsunset blue light filter for Hyprland
  services.hyprsunset = {
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
}
