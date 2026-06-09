{
  lib,
  pkgs,
  ...
}: let
  # i3/Hyprland-style numbered workspaces, generated rather than spelled out.
  workspaces = map toString (lib.range 1 9);

  # Hyper = Cmd+Alt. Karabiner maps Caps-hold to this combo (Caps-tap = Esc).
  # Cmd is included so the combo NEVER reaches the terminal/tmux (which can only
  # bind Alt/Ctrl), giving AeroSpace a conflict-free, WM-exclusive modifier that
  # behaves like Linux's SUPER. It's only Cmd+Alt (not Ctrl/Shift), so BOTH Ctrl
  # and Shift stay free — letting us mirror the ThinkPad's Hyprland binds 1:1
  # (SUPER→Hyper): Ctrl = move window, Shift = cycle / move-to workspace.
  hyper = "cmd-alt";

  focusWorkspace = lib.listToAttrs (map (n: lib.nameValuePair "${hyper}-${n}" "workspace ${n}") workspaces);
  moveToWorkspace = lib.listToAttrs (map (n: lib.nameValuePair "${hyper}-shift-${n}" "move-node-to-workspace ${n}") workspaces);
in
  lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    programs.aerospace = {
      enable = true;
      # launchd owns startup; the HM module ignores AeroSpace's own start-at-login.
      launchd.enable = true;

      settings = {
        default-root-container-layout = "tiles";
        default-root-container-orientation = "auto";

        gaps = {
          inner = {
            horizontal = 8;
            vertical = 8;
          };
          outer = {
            left = 8;
            right = 8;
            top = 8;
            bottom = 8;
          };
        };

        # 1:1 mirror of the Hyprland binds (home/desktop/hyprland/settings/
        # bindings.nix) with $mainMod SUPER → Hyper, so muscle memory matches the
        # ThinkPad exactly.
        mode.main.binding =
          {
            # focus — Hyprland: SUPER + h/j/k/l (movefocus)
            "${hyper}-h" = "focus left";
            "${hyper}-j" = "focus down";
            "${hyper}-k" = "focus up";
            "${hyper}-l" = "focus right";

            # move window — Hyprland: SUPER + Ctrl + h/j/k/l (movewindow)
            "${hyper}-ctrl-h" = "move left";
            "${hyper}-ctrl-j" = "move down";
            "${hyper}-ctrl-k" = "move up";
            "${hyper}-ctrl-l" = "move right";

            # cycle workspaces — Hyprland: SUPER + Shift + H/L (workspace m±1)
            "${hyper}-shift-h" = "workspace --wrap-around prev";
            "${hyper}-shift-l" = "workspace --wrap-around next";

            # F = fullscreen (gaps), Shift+F = native fullscreen
            "${hyper}-f" = "fullscreen";
            "${hyper}-shift-f" = "macos-native-fullscreen";

            "${hyper}-q" = "close"; # Hyprland Q = killactive
            "${hyper}-r" = "layout tiles horizontal vertical"; # Hyprland R = togglesplit
            "${hyper}-t" = "layout floating tiling"; # Hyprland T = toggle floating

            # resize (Hyprland =/- grow/shrink, arrows = resizeactive)
            "${hyper}-equal" = "resize smart +50";
            "${hyper}-minus" = "resize smart -50";
            "${hyper}-left" = "resize width -50";
            "${hyper}-right" = "resize width +50";
            "${hyper}-up" = "resize height -50";
            "${hyper}-down" = "resize height +50";

            # app launch (Hyprland C=terminal, B=browser, E=file manager, Y=music)
            "${hyper}-c" = "exec-and-forget open -a kitty";
            "${hyper}-b" = "exec-and-forget open -a Firefox";
            "${hyper}-e" = "exec-and-forget open -a Finder";
            "${hyper}-y" = "exec-and-forget ${lib.getExe pkgs.pear-desktop}";
          }
          // focusWorkspace # Hyprland: SUPER + 1-9 (workspace)
          // moveToWorkspace; # Hyprland: SUPER + Shift + 1-9 (movetoworkspace)
      };
    };
  }
