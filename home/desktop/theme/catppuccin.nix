{
  inputs,
  lib,
  config,
  ...
}: let
  themeToggleBin = "${config.programs.theme-toggle.package}/bin/theme-toggle";
in {
  imports = [inputs.catppuccin.homeModules.catppuccin];

  # Prevent "file would be clobbered" errors after theme-toggle modifies configs
  home.activation.cleanThemeFiles = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
    # Remove files that theme-toggle may have modified (no longer symlinks)
    for f in \
      "$HOME/.config/kitty/kitty.conf" \
      "$HOME/.config/btop/btop.conf" \
      "$HOME/.config/starship.toml" \
      "$HOME/.config/k9s/config.yaml" \
      "$HOME/.config/lazygit/config.yml" \
      "$HOME/.config/lazydocker/config.yml" \
      "$HOME/.config/foot/foot.ini" \
      "$HOME/.config/yazi/theme.toml" \
      "$HOME/.config/Kvantum/kvantum.kvconfig" \
      "$HOME/.config/gtk-3.0/settings.ini" \
      "$HOME/.config/gtk-3.0/gtk.css" \
      "$HOME/.config/gtk-4.0/settings.ini" \
      "$HOME/.config/gtk-4.0/gtk.css"
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
  home.activation.restoreTheme = lib.hm.dag.entryAfter ["linkGeneration"] ''
    $VERBOSE_ECHO "Restoring theme settings..."
    run ${themeToggleBin} restore || true
  '';

  catppuccin = {
    flavor = "mocha";

    brave.enable = true;
    # Firefox skipped: nix module sets fixed flavor, incompatible with dynamic theming
    gtk.icon.enable = false; # Using Papirus (set in gtk.nix)
    kvantum.enable = true;
  };
}
