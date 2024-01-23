{
  inputs,
  config,
  ...
}: {
  xdg.configFile = {
    "alacritty/catppuccin".source = inputs.catpuccin-alacritty;
    "alacritty/alacritty.toml".source = config.lib.file.mkOutOfStoreSymlink /home/noams/nix-config/home/terminal/alacritty/alacritty.toml;
    # "alacritty/alacritty.yaml".source = config.lib.file.mkOutOfStoreSymlink /home/noams/nix-config/home/terminal/alacritty/alacritty.yml;
  };
  programs.alacritty = {
    enable = true;
  };
}
