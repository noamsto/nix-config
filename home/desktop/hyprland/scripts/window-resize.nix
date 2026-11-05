{pkgs, ...}: let
  window-resize = pkgs.writeShellScriptBin "window-resize" ''
    #!/usr/bin/env bash

    # Smart window resize that works for both floating and tiled/pseudo windows
    # Usage: window-resize [grow|shrink]

    AMOUNT=80

    # Get active window info
    WINDOW_INFO=$(hyprctl activewindow -j)
    IS_FLOATING=$(echo "$WINDOW_INFO" | jq -r '.floating')
    IS_PSEUDO=$(echo "$WINDOW_INFO" | jq -r '.pseudo')

    case "$1" in
      "grow")
        if [[ "$IS_PSEUDO" == "true" ]]; then
          # Pseudo: width inverted, height normal, auto-centers
          hyprctl dispatch "hl.dsp.window.resize({ x = -$AMOUNT, y = $AMOUNT, relative = true })"
        elif [[ "$IS_FLOATING" == "true" ]]; then
          # Floating window: resize bigger then recenter
          hyprctl dispatch "hl.dsp.window.resize({ x = $AMOUNT, y = $AMOUNT, relative = true })"
          hyprctl dispatch 'hl.dsp.window.center()'
        else
          # Tiled: shrink container to make window appear bigger
          hyprctl dispatch "hl.dsp.window.resize({ x = -$AMOUNT, y = -$AMOUNT, relative = true })"
        fi
        ;;
      "shrink")
        if [[ "$IS_PSEUDO" == "true" ]]; then
          # Pseudo: width inverted, height normal, auto-centers
          hyprctl dispatch "hl.dsp.window.resize({ x = $AMOUNT, y = -$AMOUNT, relative = true })"
        elif [[ "$IS_FLOATING" == "true" ]]; then
          # Floating window: resize smaller then recenter
          hyprctl dispatch "hl.dsp.window.resize({ x = -$AMOUNT, y = -$AMOUNT, relative = true })"
          hyprctl dispatch 'hl.dsp.window.center()'
        else
          # Tiled: grow container to make window appear smaller
          hyprctl dispatch "hl.dsp.window.resize({ x = $AMOUNT, y = $AMOUNT, relative = true })"
        fi
        ;;
      *)
        echo "Usage: window-resize [grow|shrink]"
        exit 1
        ;;
    esac
  '';
in {
  home.packages = [window-resize];
}
