{config, ...}: {
  # Enable Tailscale VPN service
  services.tailscale = {
    enable = true;
    # --operator (shared across profiles) lets the user run tailscale without sudo.
    # --accept-routes is intentionally omitted: it's per-profile and extraSetFlags
    # isn't profile-aware, so the tsw/tsp abbreviations set it via `tailscale set`.
    extraSetFlags = [
      "--operator=${config.username}"
    ];
    useRoutingFeatures = "client";
  };

  # Open Tailscale port in firewall
  networking.firewall = {
    # Allow Tailscale UDP port
    allowedUDPPorts = [41641];
    # Allow traffic on Tailscale network interface
    trustedInterfaces = ["tailscale0"];
  };
}
