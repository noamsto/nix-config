_: {
  # Enable Tailscale VPN service
  services.tailscale = {
    enable = true;
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
