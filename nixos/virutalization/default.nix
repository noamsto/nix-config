{
  pkgs,
  config,
  lib,
  ...
}: let
  isDesktop = config.desktop.mode != "none";
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

  virtualisation.docker.enable = true;
  users.users.${config.username}.extraGroups = ["docker"];
}
