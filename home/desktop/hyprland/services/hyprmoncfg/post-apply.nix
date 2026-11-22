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

      # jq -e: 0 = an external is connected, 1 = none; anything else is a parse failure.
      rc=0
      jq -e 'any(.[]; .name | test("^(eDP|LVDS|DSI)"; "i") | not)' <<<"$monitors" >/dev/null || rc=$?
      case $rc in
        0) profile=docked ;;
        1) profile=laptop ;;
        *)
          echo "hyprmoncfg-post-apply: cannot parse hyprctl monitors output" >&2
          exit "$rc"
          ;;
      esac

      # Dispatched through Hyprland so xrdb runs with the session's DISPLAY.
      hyprctl dispatch "hl.dsp.exec_cmd(\"${xresourcesApply}/bin/xresources-apply $profile\")"
    '';
  }
