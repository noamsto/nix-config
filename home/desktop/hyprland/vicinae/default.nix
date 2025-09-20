{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.vicinae.homeManagerModules.default # enable Home Manager
  ];
  home.packages = with pkgs; [
    inputs.vicinae.packages.${pkgs.system}.default
    libqalculate
  ];
  services.vicinae = {
    enable = true;
    autoStart = true;
    settings = {
      faviconService = "twenty"; # twenty | google | none
      font.size = 12;
      popToRootOnClose = false;
      closeOnFocusLost = true;
      rootSearch.searchFiles = false;
      theme.name = "catppuccin-mocha";
      window = {
        csd = true;
        opacity = 0.90;
        rounding = 8;
      };
    };
  };
}
