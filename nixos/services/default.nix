{applyKeyed, ...}: {
  imports = [
    ./tlp.nix
    ./tailscale.nix
    (applyKeyed ./airconnect.nix)
    (applyKeyed ./jellyfin.nix)
    ./local-proxy.nix
    ./agent-dashboard.nix
    ./money-scout.nix
    ./toddl-issue-intake.nix
  ];
}
