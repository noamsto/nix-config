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
      # unrelated reasons). THEME_APPLY_FORCE bypasses it for the activation
      # entry below, which runs right after the updaters' output was reset to
      # the Home Manager defaults — there the cached theme says nothing about
      # what is on disk.
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}"
      mkdir -p "$state_dir"
      last_file="$state_dir/theme-apply-macos.last"
      if [[ -z "''${THEME_APPLY_FORCE:-}" && -f "$last_file" && "$(cat "$last_file")" == "$theme" ]]; then
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
