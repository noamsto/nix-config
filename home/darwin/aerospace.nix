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

  # hyper+T floats the focused window (the binding's `layout floating tiling`
  # toggle), then this sizes+centers it. AeroSpace delegates float geometry to
  # macOS, so System Events is the only lever — this is what gives the Hyprland
  # "float pops to a small centered window" feel that AeroSpace lacks natively.
  # Main-display centering only (Finder desktop bounds); a float on a secondary
  # display lands roughly. Kept as a writeText file (not a shell heredoc) so Nix
  # indentation-stripping can't mangle a heredoc terminator.
  floatCenterScript = pkgs.writeText "aerospace-float-center.applescript" ''
    tell application "Finder" to set screenBounds to bounds of window of desktop
    set screenWidth to item 3 of screenBounds
    set screenHeight to item 4 of screenBounds
    set winWidth to round (screenWidth * 0.65)
    set winHeight to round (screenHeight * 0.75)
    set xPos to round ((screenWidth - winWidth) / 2)
    set yPos to round ((screenHeight - winHeight) / 2)
    tell application "System Events"
      set frontApp to first application process whose frontmost is true
      tell frontApp
        if (count of windows) > 0 then
          set position of front window to {xPos, yPos}
          set size of front window to {winWidth, winHeight}
        end if
      end tell
    end tell
  '';
  floatCenter = pkgs.writeShellScript "aerospace-float-center" ''
    # Let AeroSpace finish detaching the window into a macOS float first.
    sleep 0.12
    osascript ${floatCenterScript}
  '';

  # Window → workspace assignments mirroring Hyprland's window_rule.nix
  # "workspace N [silent]" rules. follow=false → move only (AeroSpace never
  # follows by default — equals Hyprland's `silent`); follow=true → move then
  # switch (Hyprland's non-silent firefox rule).
  wsAssign = appId: ws: follow: {
    "if".app-id = appId;
    run =
      if follow
      then ["move-node-to-workspace ${ws}" "workspace ${ws}"]
      else "move-node-to-workspace ${ws}";
  };
  floatApp = appId: {
    "if".app-id = appId;
    run = "layout floating";
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    programs.aerospace = {
      enable = true;
      # The binary comes from the Homebrew cask so its TCC grants survive version
      # bumps — rationale in the Mac host config (private flake). Config stays here.
      package = null;
      # The module's agent would hardcode the store-path binary; the Mac host config (private flake)
      # declares one against /Applications instead. The toml still gets
      # start-at-login = false, so launchd remains the only starter.
      launchd.enable = false;

      settings = {
        # v2 only changes the persistent-workspaces default (inferred → empty);
        # we don't set that option, so this is a no-op opt-in that silences the
        # "config-version = 1 is outdated" reload warning.
        config-version = 2;

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

        # Window rules mirroring Hyprland's window_rule.nix workspace/float rules.
        # Only the rules AeroSpace can honour port: workspace assignment and
        # plain float. Geometry/opacity/pin/idle rules are compositor-only and
        # have no AeroSpace equivalent (macOS handles PiP-on-top natively).
        on-window-detected = [
          (wsAssign "net.kovidgoyal.kitty" "1" false) # Hyprland: kitty → WS1 silent
          (wsAssign "org.mozilla.firefox" "2" true) # Hyprland: firefox → WS2 (follow)
          (wsAssign "org.ferdium.ferdium-app" "5" false) # Hyprland: ferdium → WS5 silent
          (wsAssign "com.tinyspeck.slackmacgap" "5" false) # Hyprland: slack → WS5 (not yet installed)
          (wsAssign "us.zoom.xos" "5" false) # Hyprland: zoom → WS5 (not yet installed)
          (wsAssign "com.github.th-ch.youtube-music" "9" false) # Hyprland: music → WS9 silent
          (floatApp "org.videolan.vlc") # Hyprland: vlc float
          (floatApp "com.apple.calculator") # Hyprland: calculator float
        ];

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
            # Hyprland T = toggle floating. AeroSpace floats at the tiled size, so
            # follow the toggle with a size+center pass (see floatCenter above).
            "${hyper}-t" = [
              "layout floating tiling"
              "exec-and-forget ${floatCenter}"
            ];

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
            # Electron apps must launch as a .app bundle (the raw inner binary
            # can't find its Helper apps), so `open` the bundle rather than getExe.
            "${hyper}-y" = "exec-and-forget open ${pkgs.pear-desktop}/Applications/YouTube\\ Music.app";
          }
          // focusWorkspace # Hyprland: SUPER + 1-9 (workspace)
          // moveToWorkspace; # Hyprland: SUPER + Shift + 1-9 (movetoworkspace)
      };
    };

    # AeroSpace draws no window borders, so the focused window is otherwise
    # invisible against its neighbours. JankyBorders gives a uniform focus
    # border (active vs inactive only — it can't single out floats). Catppuccin
    # mocha: active = blue (matches the Hyprland border), inactive = surface1.
    services.jankyborders = {
      enable = true;
      settings = {
        style = "round";
        width = 5.0;
        hidpi = "on";
        # Blue→mauve gradient: a flat pastel border vanished on light window
        # chrome (Finder), the gradient reads on light *and* dark. The module
        # drops settings bare into a bash array, so the value carries its own
        # quotes to survive gradient()'s parens/commas. inactive = overlay0
        # (visible but muted, brighter than surface1).
        active_color = "\"gradient(top_left=0xff89b4fa,bottom_right=0xffcba6f7)\"";
        inactive_color = "0xff6c7086";
      };
    };

    # The module only wires its reload-on-change hook when its own LaunchAgent is
    # enabled, so re-add the reload. Activation-wide rather than an onChange on
    # the toml, whose home.file key the module derives from xdg.configHome and
    # isn't ours to reproduce; reload-config is idempotent. Absolute path because
    # activation doesn't inherit the interactive PATH, and the probe skips the
    # reload before brew has installed the cask.
    home.activation.aerospaceReloadConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
      aerospace=/Applications/AeroSpace.app/Contents/MacOS/aerospace
      if $aerospace list-modes --current >/dev/null 2>&1; then
        run $aerospace reload-config
      fi
    '';
  }
