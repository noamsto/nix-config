{config, ...}: {
  imports = [
    # Core configuration
    ../../options.nix
    ../../overlays
    ./hardware.nix
    ./system.nix
    ./xscript.nix
    ./media-services.nix
    # ./paperless.nix  # Disabled - will run on separate RPi4
    ./monitoring.nix
    ./tailscale.nix
    ./network-resilience.nix
    ./reverse-proxy.nix
    ../../nixos/core/nice-looking-console.nix
    ../../nixos/core/nix.nix
    ../../nixos/core/locale.nix
    ../../secrets
    # ./password-fix.nix  # Removed - systemd cycles fixed, agenix works now
  ];

  # Configuration options
  desktop.mode = "none";
  machine.type = "server";
  profile = "personal";

  # Additional settings for ZFS system
  # Disabled - SSD boot doesn't need tmpfs protection, kernel builds need >4GB tmp space
  # boot.tmp.useTmpfs = true;

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

    # Announce NFS and Samba shares for auto-discovery
    extraServiceFiles = {
      nfs = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h NFS</name>
          <service>
            <type>_nfs._tcp</type>
            <port>2049</port>
          </service>
        </service-group>
      '';

      smb = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h SMB</name>
          <service>
            <type>_smb._tcp</type>
            <port>445</port>
          </service>
        </service-group>
      '';
    };
  };

  # Fix avahi-daemon.socket ordering cycle
  # The socket was requiring sysinit.target which created a cycle with sockets.target
  systemd.sockets.avahi-daemon = {
    unitConfig = {
      DefaultDependencies = "no";
    };
    socketConfig = {
      # Keep only essential dependencies
      After = "-.mount";
    };
  };
}
