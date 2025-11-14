{lib, ...}: let
  # Import shared host configuration
  hostConfig = (import ../../lib/host-configs.nix).thinkpad-p14s-g5;
in {
  imports = [
    ./hardware-configuration.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    ./host_secrets.nix
  ];

  # Import shared configuration
  inherit (hostConfig) hostname email profile;
  desktop.mode = lib.mkDefault hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

  # AMD Ryzen 7 PRO 8840HS: 16 cores, 54GB RAM
  nix.settings = {
    max-jobs = 4;
    cores = 4; # 4x4 = 16 threads total
    max-silent-time = 14400;
    timeout = 172800;
  };

  # Allow access to hardware monitoring and power interfaces for btop
  services.udev.extraRules = ''
    # Allow all users to read hardware monitoring (not sensitive data)
    SUBSYSTEM=="hwmon", KERNEL=="hwmon*", MODE="0644"

    # Allow access to power supply info (TDP, battery, etc)
    SUBSYSTEM=="power_supply", MODE="0644"

    # Allow access to RAPL (Running Average Power Limit) for power monitoring
    SUBSYSTEM=="powercap", MODE="0644"
  '';

  # Host-specific overrides can go here
  # (aliases are now in nixos/core/aliases.nix)
}
