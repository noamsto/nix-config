{nixos-raspberrypi, ...}: {
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-4.base
    raspberry-pi-4.display-vc4
    raspberry-pi-4.case-argonone
  ];

  # Hardware device tree configuration
  hardware.deviceTree = {
    # Filter to only include Raspberry Pi 4 device trees (speeds up build)
    filter = "*rpi-4-*.dtb";
  };

  hardware.enableRedistributableFirmware = true;

  # fileSystems managed by disko.nix
}
