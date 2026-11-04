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
      # absent (read exits non-zero) in light mode. Absolute path: the Home
      # Manager activation entry below runs this with activate's own PATH, which
      # has no /usr/bin, so a bare `defaults` would exit 127 and every switch
      # would resolve to light.
      if /usr/bin/defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
        theme=dark
      else
        theme=light
      fi

      # Debounce: skip if already applied (the watched plist changes for many
      # unrelated reasons). The shared theme-state.json is the only record, so
      # a missing or unparseable file never debounces (get_current_theme
      # defaults to dark, which would pin a corrupt file on a dark Mac).
      # THEME_APPLY_FORCE bypasses it for the activation entry below, which
      # runs right after the updaters' output was reset to the Home Manager
      # defaults — there the recorded theme says nothing about what is on disk.
      if [[ -z "''${THEME_APPLY_FORCE:-}" && -f "$STATE_FILE" && "$(jq -r '.theme // empty' "$STATE_FILE" 2>/dev/null)" == "$theme" ]]; then
        exit 0
      fi

      _run_updates_neutral "$theme" \
        update_kitty update_fish update_starship update_btop update_tmux \
        update_lazydocker update_process_compose update_bat update_delta \
        update_fzf update_yazi update_lazygit

      write_state "$theme" "$(failed_to_json)"
    '';
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    programs.theme-toggle = {
      package = theme-apply-macos;

      # kitty is the only surface the Mac themes beyond the terminal apps the
      # shared cleanup in home/theme/default.nix already covers.
      mutatedFiles = [".config/kitty/kitty.conf"];
    };

    home = {
      packages = [theme-apply-macos];

      # Apply the correct theme after activation so a fresh switch lands themed.
      activation.applyThemeMacos = lib.hm.dag.entryAfter ["linkGeneration"] ''
        run env THEME_APPLY_FORCE=1 ${theme-apply-macos}/bin/theme-apply-macos || true
      '';
    };
  }
