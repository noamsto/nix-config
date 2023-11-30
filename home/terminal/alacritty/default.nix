{
  config,
  pkgs,
  catpuccin-alacritty,
  ...
}: {
  xdg.configFile = {
    "alacritty/catppuccin".source = catpuccin-alacritty;
    "alacritty/alacritty.yml".source = ./alacritty.yml;
  };
  programs.alacritty = {
    enable = true;
  };
}
