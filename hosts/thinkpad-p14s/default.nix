{
  lib,
  inputs,
  ...
}: let
  # Import shared host configuration
  hostConfig = (import ../../lib/host-configs.nix).thinkpad-p14s;
in {
  imports = [
    ./hardware-configuration.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    # ./host_secrets.nix
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen4
  ];

  # Import shared configuration
  inherit (hostConfig) hostname email profile;
  desktop.mode = lib.mkDefault hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

  # Thinkfan configuration (currently disabled for gen4)
  hardware.thinkpad.thinkfan = {
    enable = false;
    generation = "gen4";
  };

  # Host-specific overrides can go here
  # (aliases are now in nixos/core/aliases.nix)
}
