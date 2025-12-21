{
  pkgs,
  config,
  ...
}: {
  # Process-compose theme is set dynamically by theme-toggle script
  # NOTE: theme.yaml is NOT symlinked - it's copied directly by theme-toggle
  # from catppuccin-mocha.yaml or catppuccin-latte.yaml

  home.packages = [
    pkgs.process-compose
  ];
}
