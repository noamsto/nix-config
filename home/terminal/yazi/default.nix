{inputs, ...}: {
  imports = [./yazi-theme.nix];
  # xdg.configFile."yazi/themes/theme.toml".source = "${inputs.catppuccin-yazi}/themes/mocha.toml";
  xdg.configFile."yazi/Catppuccin-mocha.tmTheme".source = "${inputs.catppuccin-bat}/themes/Catppuccin Mocha.tmTheme";
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
  };
}
