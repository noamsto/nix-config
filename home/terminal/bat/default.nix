{inputs, ...}: {
  xdg.configFile."bat/themes/Catppuccin-mocha.tmTheme".source = "${inputs.catppuccin-bat}/themes/Catppuccin Mocha.tmTheme";
  programs.bat = {
    enable = true;
    config = {
      theme = "Catppuccin-mocha";
    };
  };
}
