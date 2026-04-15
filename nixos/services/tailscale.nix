{config, ...}: {
  # Enable Tailscale VPN service
  services.tailscale = {
    enable = true;
    # Allow the main user to use tailscale commands (file get, etc.) without sudo
    extraSetFlags = ["--operator=${config.username}"];
    # Use the Tailscale subnet router and exit node features if needed
    # useRoutingFeatures = "both";
  };

  # Open Tailscale port in firewall
  networking.firewall = {
    # Allow Tailscale UDP port
    allowedUDPPorts = [41641];
    # Allow traffic on Tailscale network interface
    trustedInterfaces = ["tailscale0"];
  };
}
