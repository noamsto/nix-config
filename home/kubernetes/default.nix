{
  config,
  pkgs,
  inputs,
  ...
}: {
  # K9s
  programs.k9s = {
    enable = true;
    settings.k9s = {
      ui = {
        skin = "catppuccin-mocha-transparent";
        enableMouse = true;
      };
    };
  };
  home.file."${config.xdg.configHome}/k9s/skins" = {
    source = "${inputs.k9s-catuppuccin-skins}/dist";
    recursive = true;
  };
  home.packages = with pkgs; [
    kubectl
  ];
}
