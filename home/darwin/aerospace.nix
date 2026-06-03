{
  lib,
  pkgs,
  ...
}: let
  # i3/Hyprland-style numbered workspaces, generated rather than spelled out.
  workspaces = map toString (lib.range 1 9);

  # Hyper = Cmd+Ctrl+Alt. Karabiner maps Caps-hold to this combo (Caps-tap = Esc).
  # Cmd is included so the combo NEVER reaches the terminal/tmux (which can only
  # bind Alt/Ctrl), giving AeroSpace a conflict-free, WM-exclusive modifier that
  # behaves like Linux's SUPER. Shift is deliberately left OUT of Hyper so it
  # stays free as a differentiator for the "move"/"move-to-workspace" variants.
  hyper = "cmd-ctrl-alt";

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

        # Mirrors the Hyprland binds (home/desktop/hyprland/settings/bindings.nix)
        # with $mainMod SUPER → Hyper (see the `hyper` let-binding above), so the
        # muscle memory matches the ThinkPad. Two intentional divergences from the
        # Linux layout, forced by collapsing SUPER into a Shift-free Hyper:
        #   move window      Linux: SUPER+Ctrl  → Mac: Hyper+Shift
        #   workspace prev/next Linux: SUPER+Shift+h/l → Mac: Hyper+[ / Hyper+]
        # (these get harmonized on the Linux side when ported.)
        mode.main.binding =
          {
            # focus (Hyper + h/j/k/l)
            "${hyper}-h" = "focus left";
            "${hyper}-j" = "focus down";
            "${hyper}-k" = "focus up";
            "${hyper}-l" = "focus right";

            # move window (Hyper + Shift + h/j/k/l)
            "${hyper}-shift-h" = "move left";
            "${hyper}-shift-j" = "move down";
            "${hyper}-shift-k" = "move up";
            "${hyper}-shift-l" = "move right";

            # cycle workspaces (Hyper + [ / ])
            "${hyper}-leftSquareBracket" = "workspace --wrap-around prev";
            "${hyper}-rightSquareBracket" = "workspace --wrap-around next";

            # F = fullscreen (gaps), Shift+F = true/native fullscreen
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

            # app launch (Hyprland C=terminal, B=browser, E=file manager)
            "${hyper}-c" = "exec-and-forget open -a kitty";
            "${hyper}-b" = "exec-and-forget open -a Firefox";
            "${hyper}-e" = "exec-and-forget open -a Finder";
          }
          // focusWorkspace
          // moveToWorkspace;
      };
    };
  }
