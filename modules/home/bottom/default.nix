{
  config,
  pkgs,
  catpuccin-bottom,
  ...
}:
  let catpuccin-flavor-file = "${catpuccin-bottom}/themes/mocha.toml";
  in
{

  home.file."${config.xdg.configHome}/bottom/bottom.toml".source = "${catpuccin-bottom}/themes/mocha.toml";
  programs.bottom = {
    enable = true;
  };
}
