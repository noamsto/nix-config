# Evaluation fixture for nixosModules.rpi, built with nixos-raspberrypi's
# lib.nixosSystem (see flake-modules/nixos-systems.nix). CI builds its toplevel,
# kernel included, so Pi hosts on this library substitute the kernel.
{self}: {...}: {
  imports = [
    self.nixosModules.rpi
  ];

  hostname = "example-rpi4";
  username = "user";

  nix-config.rpi = {
    board = "rpi4";
    sshAuthorizedKeys = ["ssh-ed25519 AAAAexample example@example.invalid"];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
    };
    "/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
    };
  };

  system.stateVersion = "26.05";
}
