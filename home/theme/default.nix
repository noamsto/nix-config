{
  lib,
  config,
  ...
}: {
  # headless.nix self-gates on a Linux host with no desktop — the one case the
  # Hyprland and macOS wrappers both leave unclaimed.
  imports = [./palette.nix ./headless.nix];

  options.programs.theme-toggle = {
    # Deliberately has no default: each platform wrapper assigns its own
    # derivation, so the Mac closure never pulls the Linux-only deps that the
    # Hyprland theme-toggle needs.
    package = lib.mkOption {
      type = lib.types.package;
      description = "The platform's theme switcher package.";
    };

    mutatedFiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Home-relative paths that a theme updater rewrites in place. Platform
        wrappers append the files only their own updater set touches.
      '';
    };
  };

  config = {
    # Every platform runs these updaters, so every platform mutates these files.
    programs.theme-toggle.mutatedFiles = [
      ".config/btop/btop.conf"
      ".config/starship.toml"
      ".config/lazygit/config.yml"
      ".config/lazydocker/config.yml"
      ".config/yazi/theme.toml"
    ];

    # The updaters replace these HM symlinks with regular files, which makes the
    # next activation fail its link check with "file would be clobbered" — so
    # drop the mutated copies first. Lives here rather than in each platform
    # wrapper because all three wrappers share most of the list, and the one
    # that fell behind (headless) failed activation on a stale backup.
    home.activation.cleanThemeFiles = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      for f in ${lib.escapeShellArgs config.programs.theme-toggle.mutatedFiles}; do
        f="$HOME/$f"
        if [ -f "$f" ] && [ ! -L "$f" ]; then
          $VERBOSE_ECHO "Removing theme-managed file: $f"
          run rm -f "$f"
        fi
      done
    '';
  };
}
