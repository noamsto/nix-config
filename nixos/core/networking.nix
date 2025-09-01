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
    wifi.backend = "iwd"; # Use iwd instead of wpa_supplicant
  };

  # Configure iwd (iNet Wireless Daemon)
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General = {
        # Let NetworkManager handle IP configuration
        EnableNetworkConfiguration = false;
        # Improve roaming for better connectivity
        RoamThreshold = -75;
        RoamThreshold5G = -76;
      };
      Network = {
        EnableIPv6 = true;
        NameResolvingService = "systemd";
      };
      Settings = {
        AutoConnect = true;
      };
    };
  };

  services = {
    # DNS service
    resolved.enable = true;

    # For discovering zero-conf network sharing
    avahi = {
      enable = true;
      # For discovering zero-conf network sharing (avahi)
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
