{lib, ...}: {
  imports = [
    ./default.nix
  ];

  # Override filesystem configuration for SD image builds
  # Completely remove the /boot/firmware mount and let SD image builder handle it at /boot
  fileSystems = lib.mkForce {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = ["noatime"];
    };
  };

  # SD Image configuration - only used when building images
  sdImage = {
    firmwareSize = 256; # MB - increase from default 30MB for RPi4 firmware + dtoverlays
    expandOnBoot = true; # Auto-expand root partition (default)
  };
}
