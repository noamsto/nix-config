{
  inputs,
  pkgs,
  ...
}: {
  imports = [inputs.walker.homeManagerModules.default];
  home.packages = with pkgs; [
    libqalculate
    iwmenu
  ];

  programs.walker = {
    enable = true;
    runAsService = false;

    # All options from the config.json can be used here.
    config = {
      ui.fullscreen = true;
      list = {
        height = 200;
      };
      websearch.prefix = "?";
      switcher.prefix = "/";
    };
  };
}
