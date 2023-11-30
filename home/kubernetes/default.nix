{
  config,
  pkgs,
  ...
}: {
  # K9s
  programs.k9s.enable = true;
  home.file."${config.xdg.configHome}/k9s/skin.yml".source = ./k9s_catpuccin.yml;
  home.packages = with pkgs; [
    kubectl
  ];
}
