_: {
  # Tailscale VPN for remote access
  services.tailscale = {
    enable = true;
    openFirewall = true;

    # Enable routing features for subnet router / exit node capabilities
    useRoutingFeatures = "server";

    # Extra flags for tailscale up (only used if authKeyFile is set)
    extraUpFlags = [
      "--accept-routes" # Accept routes from other nodes
      "--ssh" # Enable Tailscale SSH
    ];
  };

  # Optional: If you want naspi to be a subnet router to access your home network remotely
  # Uncomment and adjust the subnet to match your local network
  # After enabling, run: sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-routes

  # Allow Tailscale to forward traffic (required for subnet router)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
}
