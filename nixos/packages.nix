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
    fastfetch

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
    firefox
  ];
in {
  environment.systemPackages =
    core-packages
    ++ lib.optionals
    isDesktop
    desktop-packages;
}
