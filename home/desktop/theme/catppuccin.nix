{inputs, ...}: {
  lib,
  config,
  ...
}: let
  themeToggleBin = "${config.programs.theme-toggle.package}/bin/theme-toggle";
in {
  imports = [inputs.catppuccin.homeModules.catppuccin];

  # Hyprland-only surfaces; the terminal apps every platform themes are
  # cleaned by the shared hook in home/theme/default.nix.
  programs.theme-toggle.mutatedFiles = [
    ".config/ghostty/config"
    ".config/kitty/kitty.conf"
    ".config/k9s/config.yaml"
    ".config/foot/foot.ini"
    ".config/Kvantum/kvantum.kvconfig"
    ".config/gtk-3.0/settings.ini"
    ".config/gtk-3.0/gtk.css"
    ".config/gtk-4.0/settings.ini"
    ".config/gtk-4.0/gtk.css"
  ];

  # Run theme-toggle restore after Home Manager activation
  # This ensures theme-managed configs (ghostty, starship, k9s, btop, lazygit)
  # are updated to match the current theme after rebuilds
  home.activation.restoreTheme = lib.hm.dag.entryAfter ["linkGeneration"] ''
    $VERBOSE_ECHO "Restoring theme settings..."
    run ${themeToggleBin} restore || true
  '';

  catppuccin = {
    enable = true;
    autoEnable = false;
    flavor = "mocha";

    brave.enable = true;
    # Firefox skipped: nix module sets fixed flavor, incompatible with dynamic theming
    gtk.icon.enable = false; # Using Papirus (set in gtk.nix)
    kvantum.enable = true;
  };
}
