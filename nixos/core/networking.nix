{config, ...}: {
  networking.firewall.enable = true;
  networking.hostName = config.hostname;
  networking.networkmanager = {
    enable = true; # Easiest to use and most distros use this by default.
    dns = "systemd-resolved";
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
      # geoProviderUrl = "https://beacondb.net/v1/geolocate?key=YOUR_API_KEY";
      # submissionUrl = "https://beacondb.net/v1/geolocate?key=YOUR_API_KEY";
    };
  };
}
