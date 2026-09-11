{...}: {
  imports = [
    ./tlp.nix
    ./tailscale.nix
    ./sentinelone.nix
    ./airconnect.nix
    ./jellyfin.nix
    ./local-proxy.nix
  ];
}
