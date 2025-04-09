{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  isDesktop = config.desktop.mode != "none";
  isLaptop = config.machine.type == "laptop";
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
    # (inputs.self.packages.${pkgs.system}.aicommit2)
    wluma
  ];
  laptop-packages = with pkgs; [
    power-profiles-daemon
    rocmPackages.rocminfo
  ];
in {
  environment.systemPackages =
    core-packages
    ++ lib.optionals
    isDesktop
    desktop-packages
    ++ lib.optionals
    isLaptop
    laptop-packages;
}
