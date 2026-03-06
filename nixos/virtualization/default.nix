{
  pkgs,
  config,
  lib,
  ...
}: let
  isDesktop = config.desktop.isEnabled;
  desktop-packages = with pkgs; [
    distrobox
    distrobox-tui
    qemu
  ];
in {
  environment.systemPackages =
    (with pkgs; [
      lazydocker
      docker-compose
    ])
    ++ lib.optionals
    isDesktop
    desktop-packages;

  virtualisation.docker = {
    enable = true;
    extraPackages = [pkgs.openssh pkgs.git];
  };
  users.users.${config.username}.extraGroups = ["docker"];
}
