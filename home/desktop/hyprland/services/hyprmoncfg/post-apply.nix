{pkgs}: let
  xresourcesApply = import ../../scripts/xresources-apply.nix {inherit pkgs;};
in
  pkgs.writeShellApplication {
    name = "hyprmoncfg-post-apply";
    runtimeInputs = [pkgs.jq];
    text = ''
      # hyprctl comes from PATH on purpose: hyprmoncfgd's nixpkgs wrapper prefixes
      # Hyprland's bin, and keeping it off runtimeInputs lets tests stub it.
      monitors=$(hyprctl monitors -j)

      profile=laptop
      if jq -e 'any(.[]; .name | test("^(eDP|LVDS|DSI)"; "i") | not)' <<<"$monitors" >/dev/null; then
        profile=docked
      fi

      # Dispatched through Hyprland so xrdb runs with the session's DISPLAY.
      hyprctl dispatch "hl.dsp.exec_cmd(\"${xresourcesApply}/bin/xresources-apply $profile\")"
    '';
  }
