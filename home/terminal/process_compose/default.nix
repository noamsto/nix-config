{
  pkgs,
  config,
  ...
}: {
  # Process-compose theme is set dynamically by theme-toggle script
  # theme.yaml is overwritten with catppuccin-mocha.yaml or catppuccin-latte.yaml
  xdg.configFile."process-compose/theme.yaml".source =
    config.lib.file.mkOutOfStoreSymlink
    "${config.home.homeDirectory}/nix-config/home/terminal/process_compose/theme.yaml";

  home.packages = [
    pkgs.process-compose
  ];
}
