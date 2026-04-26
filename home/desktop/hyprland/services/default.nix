{...}: {
  imports = [
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
        splash_offset = 2;

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

  # Declaratively manage wallpaper files (for hyprpaper fallback)
  xdg.configFile."wallpapers/space_nebula.png".source = ./wallpapers/space_nebula.png;

  # Wallpapers for Noctalia shuffle (~/Pictures/Wallpapers)
  home.file = {
    "Pictures/Wallpapers/space_nebula.png".source = ./wallpapers/space_nebula.png;
    "Pictures/Wallpapers/crimson_migration.jpeg".source = ./wallpapers/3840_x_2160_a_silent_migration_across_a_crimson.jpeg;
    "Pictures/Wallpapers/natures_quiet_masterpiece.jpeg".source = ./wallpapers/3840_x_2160_natures_quiet_masterpiece.jpeg;
    "Pictures/Wallpapers/still_waters_at_dusk.jpeg".source = ./wallpapers/3840_x_2160_still_waters_at_dusk.jpeg;
    "Pictures/Wallpapers/island_sunny_day.png".source = ./wallpapers/island_sunny_day_3840_x_2160.png;
    "Pictures/Wallpapers/gold_river.jpg".source = ./wallpapers/01-GoldRiver-iunewind-UHD.jpg;
    "Pictures/Wallpapers/far_ruins.jpg".source = ./wallpapers/02-FarRuins-iunewind-UHD.jpg;
    "Pictures/Wallpapers/autumn_sunset.jpg".source = ./wallpapers/03-AutumnSunset-iunewind-UHD.jpg;
    "Pictures/Wallpapers/forest_spring.jpg".source = ./wallpapers/04-ForestSpring-iunewind-UHD.jpg;
    "Pictures/Wallpapers/green_valley.jpg".source = ./wallpapers/10-GreenValley-iunewind-UHD.jpg;
    "Pictures/Wallpapers/desert.jpg".source = ./wallpapers/28-Desert-iunewind-UHD.jpg;
    "Pictures/Wallpapers/lone_tree_river.jpg".source = ./wallpapers/34-LoneTreeRiver-iunewind-UHD.jpg;
    "Pictures/Wallpapers/milky_way_galaxy_rising_star.png".source = ./wallpapers/milky_way_galaxy_rising_star.png;
    "Pictures/Wallpapers/orange_tree_with_dark_mountains.png".source = ./wallpapers/orang_tree_with_dark_mountains.png;
    "Pictures/Wallpapers/back_to_serenity.png".source = ./wallpapers/back_to_serenity.png;
  };
}
