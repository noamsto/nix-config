# Minimal RPi4 installer configuration using nvmd nixosInstaller
{nixos-raspberrypi, ...}: {
  # Use nvmd base modules - nixosInstaller already includes installer modules
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-4.base
  ];

  # Basic system configuration
  system.stateVersion = "24.05";
  nixpkgs.hostPlatform = "aarch64-linux";

  # Network configuration for remote deployment
  networking.hostName = "rpi4-installer";

  # User configuration with SSH key for deployment
  users.users.nixos.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
  ];

  # Hardware configuration
  hardware = {
    enableRedistributableFirmware = true;
    raspberry-pi.config.all = {};
  };
}
