{
  inputs,
  nixpkgs,
  ...
}: let
  inherit (inputs) nixos-raspberrypi;
in {
  thinkpad-p14s = nixpkgs.lib.nixosSystem {
    modules = [./thinkpad-p14s];
    specialArgs = {inherit inputs;};
  };
  thinkpad-p14s-g5 = nixpkgs.lib.nixosSystem {
    modules = [
      ./thinkpad-p14s-g5
    ];
    specialArgs = {inherit inputs;};
  };

  # Raspberry Pi with disko (following nvmd pattern)
  naspi = nixos-raspberrypi.lib.nixosSystem {
    specialArgs = {
      inherit inputs;
      inherit nixos-raspberrypi;
    };
    system = "aarch64-linux";
    modules = [
      ./naspi
      inputs.disko.nixosModules.disko
      ./naspi/disko.nix
    ];
  };

  # For deploying to systems running from installer (no repartitioning)
  naspi-installer-target = nixos-raspberrypi.lib.nixosSystem {
    specialArgs = {
      inherit inputs;
      inherit nixos-raspberrypi;
    };
    system = "aarch64-linux";
    modules = [
      ./naspi
      # No disko - use fileSystems that match installer layout
      {
        fileSystems = {
          "/boot/firmware" = {
            device = "/dev/disk/by-label/FIRMWARE";
            fsType = "vfat";
            options = ["noatime" "umask=0022"];
          };
          "/" = {
            device = "/dev/disk/by-label/NIXOS_SD";
            fsType = "ext4";
            options = ["noatime" "data=writeback" "barrier=0"];
          };
        };
      }
    ];
  };

  # RPI4 Installer configuration (following nvmd pattern)
  # This creates a minimal installer image using mkNixOSRPiInstaller pattern
  rpi4-installer = nixos-raspberrypi.lib.nixosInstaller {
    specialArgs = inputs // {nixos-raspberrypi = nixos-raspberrypi;};
    modules = [
      ./rpi4-installer
    ];
  };

  # Standard RPI4 configuration using NixOS wiki approach
  rpi4-standard = nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = {inherit inputs;};
    modules = [
      ./rpi4-standard
    ];
  };
}
