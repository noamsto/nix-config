# NixOS system configurations
{inputs, ...}: let
  inherit (inputs) nixos-raspberrypi;
  nixpkgs = inputs.nixpkgs;
in {
  flake = {
    nixosConfigurations = {
      thinkpad-p14s = nixpkgs.lib.nixosSystem {
        modules = [../hosts/thinkpad-p14s];
        specialArgs = {inherit inputs;};
      };

      thinkpad-p14s-g5 = nixpkgs.lib.nixosSystem {
        modules = [../hosts/thinkpad-p14s-g5];
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
          ../hosts/naspi
          inputs.disko.nixosModules.disko
          ../hosts/naspi/disko.nix
        ];
      };

      # Raspberry Pi 4 with Argon V2 case and external SSD boot
      argon-rpi4 = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = {
          inherit inputs;
          inherit nixos-raspberrypi;
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
        specialArgs = inputs // {nixos-raspberrypi = nixos-raspberrypi;};
        modules = [
          nixos-raspberrypi.nixosModules.raspberry-pi-4.base
          nixos-raspberrypi.nixosModules.trusted-nix-caches
          # Add our custom networking configuration
          ../hosts/rpi4-installer
        ];
      };

      # Standard RPI4 configuration using NixOS wiki approach
      rpi4-standard = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = {inherit inputs;};
        modules = [
          ../hosts/rpi4-standard
        ];
      };
    };

    # RPI4 Installer configuration (following nvmd pattern)
    # Build with: nix build .#rpi4-installer
    rpi4-installer = inputs.self.nixosConfigurations.rpi4-installer.config.system.build.sdImage;

    # Standard RPI4 Image using nixos-generators (NixOS wiki approach)
    # Build with: nix build .#rpi4-standard-image
    rpi4-standard-image = inputs.nixos-generators.nixosGenerate {
      system = "aarch64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        ../hosts/rpi4-standard/image.nix
      ];
      format = "sd-aarch64";
    };
  };
}
