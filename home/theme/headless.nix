{
  pkgs,
  config,
  lib,
  osConfig ? null,
  ...
}: let
  paletteEnv = import ./palette-env.nix {inherit pkgs config lib;};

  # Named theme-toggle, not theme-apply-headless: lazytmux's bridge daemon
  # fans a controller's light/dark toggle out to every mirrored remote by
  # running `theme-toggle apply <theme>` there, and a host missing that name
  # is a silent no-op (noamsto/lazytmux#545) — the mirror then paints the
  # remote's old palette inside a re-themed local frame.
  theme-toggle = pkgs.writeShellApplication {
    name = "theme-toggle";
    runtimeInputs = paletteEnv.coreRuntimeInputs;
    text = ''
      ${paletteEnv.exports}
      export THEME_APPLY_PLATFORM=headless

      # shellcheck source=/dev/null
      source "${paletteEnv.libScript}"

      # Terminal apps only. The neutral lib's other updaters drive GTK, Kvantum
      # and Hyprland, none of which exist here; update_kitty is skipped for the
      # same reason — this host is reached over ssh, so the terminal emulator
      # runs on the machine at the other end.
      apply_headless() {
        local theme="$1"
        case "$theme" in
        dark | light) ;;
        *)
          echo "theme-toggle: unknown theme '$theme' (want dark|light)" >&2
          return 1
          ;;
        esac
        _run_updates_neutral "$theme" \
          update_fish update_starship update_tmux update_btop \
          update_bat update_delta update_fzf update_yazi \
          update_lazygit update_lazydocker update_process_compose
        write_state "$theme" "$(failed_to_json)"
        if [[ ''${#FAILED_UPDATES[@]} -gt 0 ]]; then
          echo "theme-toggle: applied $theme (''${#FAILED_UPDATES[@]} failed: ''${FAILED_UPDATES[*]})" >&2
        fi
      }

      case "''${1:-toggle}" in
      apply)
        apply_headless "''${2:-}"
        ;;
      toggle)
        if [[ "$(get_current_theme)" == "dark" ]]; then
          apply_headless light
        else
          apply_headless dark
        fi
        ;;
      get)
        get_current_theme
        ;;
      *)
        echo "Usage: theme-toggle [toggle|apply <dark|light>|get]"
        exit 1
        ;;
      esac
    '';
  };
in
  # Linux hosts with no desktop. A desktop Linux host gets the Hyprland wrapper
  # and macOS gets theme-apply-macos; both assign the same option, so the gates
  # must stay mutually exclusive or the assignments collide.
  lib.mkIf (pkgs.stdenv.hostPlatform.isLinux && (osConfig.desktop.mode or "none") == "none") {
    home.packages = [theme-toggle];
    programs.theme-toggle.package = theme-toggle;
  }
