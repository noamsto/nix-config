{...}: {
  networking.firewall.enable = true;
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
    geoclue2.enable = true;
  };
}
