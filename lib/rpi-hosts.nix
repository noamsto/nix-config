# Raspberry Pi Host Configurations
# Single source of truth for all RPi deployment metadata
{
  naspi = {
    flake = "naspi";
    hostname = "naspi.local";
    user = "noams";
    installer_user = "nixos";
    filesystem = "zfs";
    post_setup = ["zfs-keyfiles" "temp-dataset"];
    build_strategy = "remote"; # Default: build on target
    description = "Raspberry Pi 4 NAS with ZFS RAID1 on dual SSDs";
  };

  argon-rpi4 = {
    flake = "argon-rpi4";
    hostname = "argon-rpi4.local";
    user = "noams";
    installer_user = "nixos";
    filesystem = "btrfs";
    post_setup = [];
    build_strategy = "remote"; # Default: build on target
    description = "Raspberry Pi 4 with Argon V2 case and external SSD boot";
  };

  rpi4-installer = {
    flake = "rpi4-installer";
    hostname = "rpi4-installer";
    user = "nixos";
    is_installer = true;
    description = "Minimal installer image for initial RPi4 deployment";
  };
}
