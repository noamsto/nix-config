{
  lib,
  pkgs,
  ...
}: let
  # i3/Hyprland-style numbered workspaces, generated rather than spelled out.
  workspaces = map toString (lib.range 1 9);
  focusWorkspace = lib.listToAttrs (map (n: lib.nameValuePair "alt-${n}" "workspace ${n}") workspaces);
  moveToWorkspace = lib.listToAttrs (map (n: lib.nameValuePair "alt-shift-${n}" "move-node-to-workspace ${n}") workspaces);
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

        # Mirrors the Hyprland binds (home/desktop/hyprland/settings/bindings.nix),
        # with $mainMod SUPER → alt: cmd-<key> would clobber system-wide macOS
        # shortcuts (copy/quit/find/close), so alt is the conflict-free stand-in.
        mode.main.binding =
          {
            # focus (Hyprland: H=left, L=right, K=up, J=down)
            alt-h = "focus left";
            alt-j = "focus down";
            alt-k = "focus up";
            alt-l = "focus right";

            # move window (Hyprland uses $mainMod + CTRL)
            alt-ctrl-h = "move left";
            alt-ctrl-j = "move down";
            alt-ctrl-k = "move up";
            alt-ctrl-l = "move right";

            # cycle workspaces (Hyprland $mainMod + SHIFT + H/L)
            alt-shift-h = "workspace --wrap-around prev";
            alt-shift-l = "workspace --wrap-around next";

            # F = fullscreen (gaps), SHIFT+F = true/native fullscreen
            alt-f = "fullscreen";
            alt-shift-f = "macos-native-fullscreen";

            alt-q = "close"; # Hyprland Q = killactive
            alt-r = "layout tiles horizontal vertical"; # Hyprland R = togglesplit
            alt-t = "layout floating tiling"; # Hyprland T = toggle floating

            # resize (Hyprland =/- grow/shrink, arrows = resizeactive)
            alt-equal = "resize smart +50";
            alt-minus = "resize smart -50";
            alt-left = "resize width -50";
            alt-right = "resize width +50";
            alt-up = "resize height -50";
            alt-down = "resize height +50";

            # app launch (Hyprland C=terminal, B=browser, E=file manager)
            alt-c = "exec-and-forget open -a Ghostty";
            alt-b = "exec-and-forget open -a Firefox";
            alt-e = "exec-and-forget open -a Finder";
          }
          // focusWorkspace
          // moveToWorkspace;
      };
    };
  }
