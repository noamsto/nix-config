{...}: {
  imports = [
    ./catppuccin.nix
    ./gtk.nix
  ];

  # Theme configuration is in catppuccin.nix (Mocha/dark) and gtk.nix
  #
  # Runtime theme switching is handled by theme-toggle script using:
  # - gsettings color-scheme (GTK apps via portal)
  # - gsettings icon-theme (icon switching)
  # - Hyprland border colors (hyprctl)
  # - Waybar/swaync signal reload
  #
  # Note: Apps configured via catppuccin.nix (kitty, btop, etc.) retain their
  # built theme until a rebuild with different flavor is performed.
  # HM specialisations were attempted but blocked by catppuccin module deprecations.
}
