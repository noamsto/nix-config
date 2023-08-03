{
  config,
  pkgs,
  ...
}: {
  home.file."${config.xdg.configHome}/btop/themes/catpuccin_mocha.theme".source = ./catpuccin_mocha.theme;
  programs.btop = {
    enable = true;
    settings = {
      color_theme = "catpuccin_mocha";
    };
  };
}
