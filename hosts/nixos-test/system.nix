# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{pkgs, ...}: {
  imports = [
    ../../modules/nixos/core.nix
    ../../modules/nixos/kde.nix
    ../../modules/nixos/containers
    ../../modules/nixos/cloud
  ];
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  boot.loader.grub.useOSProber = true;
}
