{inputs, ...}: {
  imports = [
    ./hardware-configuration.nix
    ./system.nix
    ../../options.nix
    # Only import core modules that are RPi4 compatible
    ../../nixos/core/locale.nix
    ../../nixos/core/networking.nix
    ../../nixos/core/nix.nix
    # Import nixos-hardware for RPi4 support
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
  ];

  hostname = "rpi4-standard";
  desktop.mode = "none";
  machine.type = "server";
  profile = "personal";
}
