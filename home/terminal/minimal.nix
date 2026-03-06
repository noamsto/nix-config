# Minimal terminal configuration for headless servers
# Imports only the portable shell/tool configs (no GUI terminals)
# Note: btop.nix depends on config.theme (desktop only) — use btop package directly
{...}: {
  imports = [
    ./fish
  ];

  programs.bat.enable = true;
}
