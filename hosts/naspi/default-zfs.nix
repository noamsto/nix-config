{config, ...}: {
  imports = [
    # Core configuration
    ../../options.nix
    ./hardware.nix
    ./zfs-system.nix
    ./xscript.nix
    ./media-services.nix
    ./monitoring.nix
    ./tailscale.nix
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

  # Ensure Avahi starts after network is online to avoid race conditions
  systemd.services.avahi-daemon = {
    after = ["network-online.target"];
    wants = ["network-online.target"];
  };
}
