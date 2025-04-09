{pkgs, ...}: {
  # $XDG_CONFIG_HOME/process-compose/theme.yaml
  xdg.configFile."process-compose/theme.yaml".source = ./catppuccin-mocha.yaml;
  home.packages = [
    pkgs.process-compose
  ];
}
