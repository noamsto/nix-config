{pkgs, ...}: let
  toggle-floating = pkgs.writeShellScriptBin "toggle-floating" ''
    #!/usr/bin/env bash

    # Smart toggle floating that:
    # - When tiled → float + resize 80% + center
    # - When floating → just unfloat (let tiling layout handle size)

    IS_FLOATING=$(hyprctl activewindow -j | jq -r '.floating')

    if [[ "$IS_FLOATING" == "true" ]]; then
      # Currently floating → just toggle off, let tiling handle it
      hyprctl dispatch togglefloating
    else
      # Currently tiled → float + resize + center
      hyprctl --batch "dispatch togglefloating; dispatch resizeactive exact 65% 65%; dispatch centerwindow"
    fi
  '';
in {
  home.packages = [toggle-floating];
}
