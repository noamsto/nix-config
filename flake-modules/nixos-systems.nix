# NixOS system configurations
{inputs, ...}: let
  inherit (inputs) nixos-raspberrypi;
  inherit (inputs) nixpkgs;
in {
  flake = {
    nixosConfigurations = {
      thinkpad-p14s = nixpkgs.lib.nixosSystem {
        modules = [
          ../hosts/thinkpad-p14s
        ];
        specialArgs = {
          inherit inputs;
          inherit (inputs) self;
        };
      };

      thinkpad-p14s-g5 = nixpkgs.lib.nixosSystem {
        modules = [
          ../hosts/thinkpad-p14s-g5
        ];
        specialArgs = {
          inherit inputs;
          inherit (inputs) self;
        };
      };

      # Raspberry Pi with ZFS RAID1 on dual SSDs
      naspi = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          inherit nixos-raspberrypi;
          inherit (inputs) self;
        };
        system = "aarch64-linux";
        modules = [
          ../hosts/naspi
          inputs.disko.nixosModules.disko
          ../hosts/naspi/disko.nix
          inputs.go-bills.nixosModules.default
        ];
      };

      # Raspberry Pi 4 with Argon V2 case and external SSD boot
      argon-rpi4 = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          inherit nixos-raspberrypi;
          inherit (inputs) self;
        };
        system = "aarch64-linux";
        modules = [
          ../hosts/argon-rpi4
          inputs.disko.nixosModules.disko
          ../hosts/argon-rpi4/disko.nix
        ];
      };

      # RPI4 Installer configuration (using nixos-raspberrypi base + custom WiFi)
      # This creates a minimal installer image using mkNixOSRPiInstaller pattern
      rpi4-installer = nixos-raspberrypi.lib.nixosInstaller {
        specialArgs = inputs // {inherit nixos-raspberrypi;};
        modules = [
          nixos-raspberrypi.nixosModules.raspberry-pi-4.base
          nixos-raspberrypi.nixosModules.trusted-nix-caches
          # Add our custom networking configuration
          ../hosts/rpi4-installer
          # Don't import overlays - minimal installer doesn't need them
        ];
      };
    };

    # RPI4 Installer configuration (following nvmd pattern)
    # Build with: nix build .#rpi4-installer
    rpi4-installer = inputs.self.nixosConfigurations.rpi4-installer.config.system.build.sdImage;
  };
}
