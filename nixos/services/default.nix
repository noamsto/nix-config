{...}: {
  imports = [
    ./tlp.nix
    ./tailscale.nix
    ./airconnect.nix
    ./jellyfin.nix
    ./local-proxy.nix
    ./agent-dashboard.nix
    ./money-scout.nix
    ./toddl-issue-intake.nix
  ];
}
