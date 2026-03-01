{config, ...}: {
  networking = {
    firewall = {
      enable = true;
      trustedInterfaces = ["docker0"];

      # Valent/KDE Connect ports for device communication
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
      allowedUDPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];

      allowedTCPPorts = [
        # Spotify track sync with other devices
        57621
      ];
    };

    hostName = config.hostname;
    networkmanager = {
      enable = true; # Easiest to use and most distros use this by default.
      dns = "systemd-resolved";
      wifi.backend = "iwd";
    };

    wireless.iwd = {
      enable = true;
      settings = {
        General = {
          EnableNetworkConfiguration = false; # Let NM handle IP config
          RoamRetryInterval = 15; # Retry roaming every 15s if needed
        };
        Scan = {
          DisablePeriodicScan = false;
          InitialPeriodicScanInterval = 1; # Fast initial scan
          MaximumPeriodicScanInterval = 60; # Slow down after connected
        };
        Rank = {
          BandModifier5Ghz = 2.0; # Prefer 5GHz (you have good signal)
          BandModifier6Ghz = 3.0; # Prefer 6GHz if available
        };
      };
    };
  };

  services = {
    # DNS service - disable mDNS to avoid conflict with Avahi
    resolved = {
      enable = true;
      settings.Resolve = {
        LLMNR = false;
        MulticastDNS = false;
      };
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
