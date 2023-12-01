_: {
  imports = [./waybar];
  xdg.configFile = {
    "hypr/hyprland.conf".source = ./hyprland.conf;
    "hypr/start.sh".source = ./start.sh;
  };
}
