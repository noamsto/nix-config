{config, ...}: {
  imports = [
    # Core configuration
    ../../options.nix
    ./hardware.nix
    ./system.nix
    ./xscript.nix
    ../../nixos/core/nice-looking-console.nix
    ../../nixos/core/nix.nix
  ];

  # Configuration options
  desktop.mode = "none";
  machine.type = "server";
  profile = "personal";

  # Additional nvmd pattern settings
  boot.tmp.useTmpfs = true;
}
