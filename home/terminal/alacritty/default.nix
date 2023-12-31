{inputs, ...}: {
  xdg.configFile = {
    "alacritty/catppuccin".source = inputs.catpuccin-alacritty;
    "alacritty/alacritty.yml".source = ./alacritty.yml;
  };
  programs.alacritty = {
    enable = true;
  };
}
