_: let
  hostConfig = (import ../../lib/host-configs.nix).argon-rpi4;
in {
  imports = [
    # Core configuration
    ../../options.nix
    ./hardware.nix
    ./system.nix
    ../../nixos/core/nice-looking-console.nix
    ../../nixos/core/nix.nix
  ];

  # Configuration options from shared host-configs
  inherit (hostConfig) hostname email profile;
  desktop.mode = hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

  # Additional nvmd pattern settings
  boot.tmp.useTmpfs = true;
}
