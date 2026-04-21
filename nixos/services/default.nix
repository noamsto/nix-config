{...}: {
  imports = [
    ./tlp.nix
    # ./auto-power-profile.nix  # Replaced by TLP
    # ./battery-threshold.nix   # Replaced by TLP
    ./tailscale.nix
    ./sentinelone.nix
  ];
}
