{
  pkgs,
  config,
  lib,
  ...
}: let
  paletteEnv = import ../../theme/palette-env.nix {inherit pkgs config lib;};

  theme-apply-macos = pkgs.writeShellApplication {
    name = "theme-apply-macos";
    runtimeInputs = paletteEnv.coreRuntimeInputs;
    text = ''
      ${paletteEnv.exports}
      export THEME_APPLY_PLATFORM=macos

      # launchd runs this agent with its minimal default PATH (no /opt/homebrew),
      # so update_kitty's `kitty @` client — the Homebrew cask, not nixpkgs, per
      # home/terminal/kitty/default.nix — wouldn't be found otherwise. Appended,
      # not prepended: /opt/homebrew/bin is group-writable, so putting it first
      # would let a stray `brew install jq` shadow the pinned runtimeInputs.
      export PATH="$PATH:/opt/homebrew/bin"

      # shellcheck source=/dev/null
      source "${paletteEnv.libScript}"

      # Resolve macOS appearance. AppleInterfaceStyle is "Dark" in dark mode and
      # absent (read exits non-zero) in light mode.
      if defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
        theme=dark
      else
        theme=light
      fi

      # Debounce: skip if already applied (the watched plist changes for many
      # unrelated reasons).
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}"
      mkdir -p "$state_dir"
      last_file="$state_dir/theme-apply-macos.last"
      if [[ -f "$last_file" && "$(cat "$last_file")" == "$theme" ]]; then
        exit 0
      fi

      _run_updates_neutral "$theme" \
        update_kitty update_fish update_starship update_btop update_tmux \
        update_lazydocker update_process_compose update_bat update_delta \
        update_fzf update_yazi update_lazygit

      printf '%s' "$theme" > "$last_file"
    '';
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    programs.theme-toggle.package = theme-apply-macos;

    home = {
      packages = [theme-apply-macos];

      # The updaters replace these HM symlinks with regular files, which makes
      # the next `darwin switch` fail its link check with "file would be
      # clobbered" — so drop the mutated copies first. Linux equivalent:
      # cleanThemeFiles in home/desktop/theme/catppuccin.nix.
      activation.cleanThemeFilesMacos = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
        for f in \
          "$HOME/.config/kitty/kitty.conf" \
          "$HOME/.config/btop/btop.conf" \
          "$HOME/.config/starship.toml" \
          "$HOME/.config/lazygit/config.yml" \
          "$HOME/.config/lazydocker/config.yml" \
          "$HOME/.config/yazi/theme.toml"
        do
          if [ -f "$f" ] && [ ! -L "$f" ]; then
            $VERBOSE_ECHO "Removing theme-managed file: $f"
            run rm -f "$f"
          fi
        done
      '';

      # Apply the correct theme after activation so a fresh switch lands themed.
      activation.applyThemeMacos = lib.hm.dag.entryAfter ["linkGeneration"] ''
        run ${theme-apply-macos}/bin/theme-apply-macos || true
      '';
    };
  }
