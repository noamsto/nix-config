{
  inputs,
  pkgs,
  lib,
  ...
}: let
  catppuccin-btop = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "btop";
    rev = "f437574b600f1c6d932627050b15ff5153b58fa3";
    sha256 = "sha256-mEGZwScVPWGu+Vbtddc/sJ+mNdD2kKienGZVUcTSl+c=";
  };
in {
  imports = [inputs.catppuccin.homeModules.catppuccin];

  # Add latte theme for btop (catppuccin module only adds mocha)
  xdg.configFile."btop/themes/catppuccin_latte.theme".source = "${catppuccin-btop}/themes/catppuccin_latte.theme";

  # Clean up theme-managed files before Home Manager creates symlinks
  # This prevents "file would be clobbered" errors after theme-toggle modifies configs
  home.activation.cleanThemeFiles = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    # Remove files that theme-toggle may have modified (no longer symlinks)
    for f in \
      "$HOME/.config/kitty/kitty.conf" \
      "$HOME/.config/btop/btop.conf" \
      "$HOME/.config/starship.toml" \
      "$HOME/.config/k9s/config.yaml" \
      "$HOME/.config/lazygit/config.yml" \
      "$HOME/.config/foot/foot.ini" \
      "$HOME/.config/yazi/theme.toml"
    do
      if [ -f "$f" ] && [ ! -L "$f" ]; then
        $VERBOSE_ECHO "Removing theme-managed file: $f"
        run rm -f "$f"
      fi
    done
  '';

  # Run theme-toggle restore after Home Manager activation
  # This ensures theme-managed configs (kitty, starship, k9s, btop, lazygit)
  # are updated to match the current theme after rebuilds
  home.activation.restoreTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    # Only run if theme-toggle exists and we have a display (not in headless rebuild)
    if command -v theme-toggle &>/dev/null && [ -n "''${DISPLAY:-}''${WAYLAND_DISPLAY:-}" ]; then
      $VERBOSE_ECHO "Restoring theme settings..."
      run theme-toggle restore || true
    fi
  '';

  catppuccin = {
    flavor = "mocha";

    # === BROWSERS ===
    brave.enable = true;

    # === HYPRLAND ===
    # hyprlock always stays dark (mocha) regardless of theme toggle
    hyprlock = {
      enable = true;
      flavor = "mocha";
    };
  };
}
