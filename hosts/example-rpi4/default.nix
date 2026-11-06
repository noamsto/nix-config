# Evaluation fixture for nixosModules.rpi, built with nixos-raspberrypi's
# lib.nixosSystem (see flake-modules/nixos-systems.nix). CI builds its toplevel
# and the kernel's headers (dev output), so Pi hosts on this library substitute
# both from this repo's cache.
{self}: {config, ...}: {
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

  # nixos-raspberrypi's cache has the kernel's out and modules but not dev, so a
  # host building a dtbo or out-of-tree module would compile the kernel on the Pi.
  # Pulling dev into the closure makes CI build it and push it to our cache.
  system.extraDependencies = [config.boot.kernelPackages.kernel.dev];

  system.stateVersion = "26.05";
}
