{config, ...}: {
  networking.firewall = {
    enable = true;
    trustedInterfaces = ["docker0"];

    allowedTCPPorts = [
      # Spotify track sync with other devices
      57621
    ];
  };

  networking.hostName = config.hostname;
  networking.networkmanager = {
    enable = true; # Easiest to use and most distros use this by default.
    dns = "systemd-resolved";
    wifi.backend = "iwd";
  };

  networking.wireless.iwd.enable = true;

  services = {
    # DNS service - disable mDNS to avoid conflict with Avahi
    resolved = {
      enable = true;
      extraConfig = ''
        MulticastDNS=no
        LLMNR=no
      '';
    };

    # For discovering zero-conf network sharing
    avahi = {
      enable = true;
      nssmdns4 = true;
    };

    openssh.enable = true;

    # Location service
    geoclue2 = {
      enable = true;
      # geoProviderUrl = "https://beacondb.net/v1/geolocate";
      # submissionUrl = "https://beacondb.net/v1/geolocate?key=YOUR_API_KEY";
    };
  };
  location.provider = "geoclue2";
}
