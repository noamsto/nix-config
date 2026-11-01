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
    # Point every container (default bridge and dynamic k3d bridges alike) at
    # the docker0 gateway, where systemd-resolved answers (see
    # services.resolved.DNSStubListenerExtra). Without this docker substitutes
    # the per-network bridge gateway, which resolved doesn't listen on, so
    # node-level image pulls fail to resolve. Keeps split-DNS working inside
    # containers instead of hardcoding a public resolver.
    daemon.settings.dns = ["172.17.0.1"];
  };
  users.users.${config.username}.extraGroups = ["docker"];
}
