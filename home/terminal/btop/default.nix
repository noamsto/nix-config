{
  config,
  inputs,
  ...
}: {
  home.file."${config.xdg.configHome}/btop/themes/catppuccin_mocha.theme".source = "${inputs.catppuccin-btop}/themes/catppuccin_mocha.theme";
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "catppuccin_mocha";
      vim_keys = true;
    };
  };
}
