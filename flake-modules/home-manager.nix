# Home Manager configurations
{inputs, ...}: let
  # Import shared host configurations
  hostConfigs = import ../lib/host-configs.nix;

  # Helper to create x86_64 Home Manager configuration
  mkHomeConfig = system: hostConfig:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = import ../lib/overlays.nix inputs;
      };
      modules = [
        ../home/noams.nix
      ];
      extraSpecialArgs = {
        inherit inputs;
        osConfig = hostConfig;
      };
    };

  # Helper to create ARM Home Manager configuration (for Pi)
  mkArmHomeConfig = hostConfig:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.legacyPackages."aarch64-linux";
      modules = [
        ../hosts/naspi/home.nix
      ];
      extraSpecialArgs = {
        inherit inputs;
        osConfig = hostConfig;
      };
    };
in {
  flake.homeConfigurations = {
    # Raspberry Pi standalone
    naspi-raspbian = mkArmHomeConfig hostConfigs.naspi;

    # x86_64 standalone configurations
    noams-hyprland = mkHomeConfig "x86_64-linux" hostConfigs.thinkpad-p14s;
    noams-hyprland-work = mkHomeConfig "x86_64-linux" hostConfigs.thinkpad-p14s-g5;

    # KDE variant using personal profile host as base
    noams-kde = mkHomeConfig "x86_64-linux" (hostConfigs.thinkpad-p14s
      // {
        desktop.mode = "kde";
      });
  };
}
