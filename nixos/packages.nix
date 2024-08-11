{
  pkgs,
  lib,
  config,
  ...
}: let
  isDesktop = config.desktop.mode != "none";
  core-packages = with pkgs; [
    vim
    wget
    git
    curl
    dmidecode

    # Fetchers
    fastfetch
    cpufetch
    ramfetch
    onefetch

    # Nix/NixOS package version diff tool
    nvd

    # python
    (python312.withPackages (ps:
      with ps;
        [
          ipython
          catppuccin
        ]
        ++ catppuccin.optional-dependencies.pygments))
  ];
  desktop-packages = with pkgs; [
    wlr-randr
    gpu-viewer
    firefox
  ];
in {
  environment.systemPackages =
    core-packages
    ++ lib.optionals
    isDesktop
    desktop-packages;
}
