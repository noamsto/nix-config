{
  inputs,
  pkgs,
  ...
}: let
  font_family = "Ubuntu Nerd Font";

  # Define sensible colors for dark theme
  colors = {
    primary = "89b4fa"; # Light blue
    background = "1e1e2e"; # Dark background
    surface = "313244"; # Slightly lighter surface
    on_surface = "cdd6f4"; # Light text
    accent = "f38ba8"; # Pink accent
  };
in {
  programs.hyprlock = {
    enable = true;

    package = inputs.hyprlock.packages.${pkgs.system}.hyprlock;

    settings = {
      auth = {
        fingerprint.enable = true;
      };
      general = {
        disable_loading_bar = true;
      };

      background = [
        {
          monitor = "";
        }
      ];

      input-field = [
        {
          size = "300, 50";

          outline_thickness = 1;

          outer_color = "rgb(${colors.primary})";
          inner_color = "rgb(${colors.surface})";
          font_color = "rgb(${colors.on_surface})";

          fade_on_empty = false;
          placeholder_text = ''<span font_family="${font_family}" foreground="##${colors.on_surface}">Password...</span>'';

          dots_spacing = 0.2;
          dots_center = true;
        }
      ];

      label = [
        {
          monitor = "";
          text = "$TIME";
          inherit font_family;
          font_size = 50;
          color = "rgb(${colors.primary})";

          position = "0, 150";

          valign = "center";
          halign = "center";
        }
        {
          monitor = "";
          text = "cmd[update:3600000] date +'%a %b %d'";
          inherit font_family;
          font_size = 20;
          color = "rgb(${colors.primary})";

          position = "0, 50";

          valign = "center";
          halign = "center";
        }
      ];
    };
  };
}
