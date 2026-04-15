# Home Manager configurations
{inputs, ...}: let
  hostConfigs = import ../lib/host-configs.nix;

  mkHomeConfig = hostConfig:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = import ../lib/overlays.nix inputs;
      };
      modules = [../home/noams.nix];
      extraSpecialArgs = {
        inherit inputs;
        osConfig = hostConfig;
      };
    };
in {
  flake.homeConfigurations = {
    # Default configs for nh auto-detection (username@hostname)
    "noams@thinkpad-p14s" = mkHomeConfig hostConfigs.thinkpad-p14s;
    "noams@thinkpad-p14s-g5" = mkHomeConfig hostConfigs.thinkpad-p14s-g5;
    "noams@thinkpad-p14s-g6" = mkHomeConfig hostConfigs.thinkpad-p14s-g6;

    # Fallback for nh auto-detection (username only, defaults to personal)
    noams = mkHomeConfig hostConfigs.thinkpad-p14s;

    # Legacy names for compatibility
    noams-hyprland = mkHomeConfig hostConfigs.thinkpad-p14s;
    noams-hyprland-work = mkHomeConfig hostConfigs.thinkpad-p14s-g5;

    # KDE variant
    noams-kde = mkHomeConfig (hostConfigs.thinkpad-p14s // {desktop.mode = "kde";});
  };
}
