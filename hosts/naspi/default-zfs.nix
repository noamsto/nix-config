{config, ...}: {
  imports = [
    # Core configuration
    ../../options.nix
    ./hardware.nix
    ./zfs-system.nix
    ./xscript.nix
    ./media-services.nix
    ./monitoring.nix
    ../../nixos/core/nice-looking-console.nix
    ../../nixos/core/nix.nix
  ];

  # Configuration options
  desktop.mode = "none";
  machine.type = "server";
  profile = "personal";

  # Additional settings for ZFS system
  boot.tmp.useTmpfs = true;

  # Enable needed services for NAS functionality
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
  };

  # Ensure Avahi starts after network is online to avoid race conditions
  systemd.services.avahi-daemon = {
    after = ["network-online.target"];
    wants = ["network-online.target"];
  };
}
