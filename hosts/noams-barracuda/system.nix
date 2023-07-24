# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  lib,
  config,
  ...
}: {
  imports = [
    ../../modules/nixos/core.nix
    ../../modules/nixos/kde.nix
    ../../modules/nixos/containers
    ../../modules/nixos/cloud
    # ../../modules/nixos/hyprland.nix
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    enableCryptodisk = true;
    useOSProber = true;
  };

  boot.initrd = {
    luks.devices."root" = {
      device = "/dev/disk/by-uuid/ff066183-b3a3-43f3-af0b-515d1e80155f"; # UUID for /dev/nvme01np2
      preLVM = true;
      keyFile = "/keyfile0.bin";
      allowDiscards = true;
    };
    secrets = {
      # Create /mnt/etc/secrets/initrd directory and copy keys to it
      "keyfile0.bin" = "/etc/secrets/initrd/keyfile0.bin";
    };
  };
}
