{pkgs, ...}: let
  toggle-floating = pkgs.writeShellScriptBin "toggle-floating" ''
    #!/usr/bin/env bash

    # Smart toggle floating that:
    # - When tiled → float + resize 65% + center
    # - When floating → just unfloat (let tiling layout handle size)

    IS_FLOATING=$(hyprctl activewindow -j | jq -r '.floating')

    if [[ "$IS_FLOATING" == "true" ]]; then
      # Currently floating → just toggle off, let tiling handle it
      hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })'
    else
      # Currently tiled → float + resize + center.
      # hl.dsp.window.resize takes numbers only (tableOptNum), so the old
      # `resizeactive exact 65% 65%` has no direct equivalent — compute the
      # pixels from the focused monitor's logical size (physical / scale).
      read -r W H < <(hyprctl monitors -j |
        jq -r '.[] | select(.focused) | "\((.width / .scale * 0.65) | floor) \((.height / .scale * 0.65) | floor)"')

      hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })'
      if [[ -n "''${W:-}" && -n "''${H:-}" ]]; then
        hyprctl dispatch "hl.dsp.window.resize({ x = $W, y = $H })"
      fi
      hyprctl dispatch 'hl.dsp.window.center()'
    fi
  '';
in {
  home.packages = [toggle-floating];
}
