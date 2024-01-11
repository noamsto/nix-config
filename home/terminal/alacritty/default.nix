{inputs, ...}: {
  xdg.configFile = {
    "alacritty/catppuccin".source = inputs.catpuccin-alacritty;
    "alacritty/alacritty.toml".source = ./alacritty.toml;
  };
  programs.alacritty = {
    enable = true;
  };
}
