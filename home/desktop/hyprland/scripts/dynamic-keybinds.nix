{
  pkgs,
  lib,
  ...
}: let
  dynamic-keybinds = pkgs.writeShellScriptBin "dynamic-keybinds" ''
    # Terminal window classes that should NOT have Ctrl+hjkl bound in Hyprland
    TERMINAL_CLASSES="kitty|foot|alacritty|wezterm"

    bind_navigation() {
        ${lib.getExe' pkgs.hyprland "hyprctl"} keyword bind "CTRL, H, movefocus, l" >/dev/null 2>&1
        ${lib.getExe' pkgs.hyprland "hyprctl"} keyword bind "CTRL, L, movefocus, r" >/dev/null 2>&1
        ${lib.getExe' pkgs.hyprland "hyprctl"} keyword bind "CTRL, K, movefocus, u" >/dev/null 2>&1
        ${lib.getExe' pkgs.hyprland "hyprctl"} keyword bind "CTRL, J, movefocus, d" >/dev/null 2>&1
    }

    unbind_navigation() {
        ${lib.getExe' pkgs.hyprland "hyprctl"} keyword unbind "CTRL, H" >/dev/null 2>&1
        ${lib.getExe' pkgs.hyprland "hyprctl"} keyword unbind "CTRL, L" >/dev/null 2>&1
        ${lib.getExe' pkgs.hyprland "hyprctl"} keyword unbind "CTRL, K" >/dev/null 2>&1
        ${lib.getExe' pkgs.hyprland "hyprctl"} keyword unbind "CTRL, J" >/dev/null 2>&1
    }

    handle() {
        if [[ ''${1:0:12} == "activewindow" ]]; then
            # Format: activewindow>>CLASS,TITLE
            window_class="''${1:14}"
            window_class="''${window_class%%,*}"

            if echo "$window_class" | ${lib.getExe pkgs.gnugrep} -qE "^($TERMINAL_CLASSES)$"; then
                unbind_navigation
            else
                bind_navigation
            fi
        fi
    }

    # Initial state: bind keys for non-terminal apps
    bind_navigation

    # Listen to Hyprland socket events for window focus changes
    ${lib.getExe pkgs.socat} -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
        handle "$line"
    done
  '';
in {
  home.packages = [dynamic-keybinds];

  wayland.windowManager.hyprland.settings = {
    exec-once = [
      "dynamic-keybinds"
    ];
  };
}
