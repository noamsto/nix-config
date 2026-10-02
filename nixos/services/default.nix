{...}: {
  imports = [
    ./tlp.nix
    ./tailscale.nix
    ./airconnect.nix
    ./jellyfin.nix
    ./local-proxy.nix
    ./money-scout.nix
  ];
}
