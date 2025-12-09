{
  lib,
  pkgs,
  ...
}: let
  terminal = "kitty";
  fileManager = "${lib.getExe pkgs.xfce.thunar}";
  browser = "${lib.getExe pkgs.firefox}";
  youtube-music = "${lib.getExe pkgs.youtube-music}";

  toggle = program: service: let
    prog = builtins.substring 0 14 program;
    runserv = lib.optionalString service "run-as-service";
  in "pkill ${prog} || ${runserv} ${program}";

  runOnce = program: let
    progName = builtins.baseNameOf program;
    # Always use -f flag for reliable detection across all program types
  in "pgrep -f ${progName} || ${program}";

  # Kill and restart a program in background with disown
  restartProgramBackground = program: let
    progName = builtins.baseNameOf program;
    # Always use -f flag for reliable detection across all program types
  in "pkill -f ${progName} || true; sleep 0.5; ${program} & disown";
in {
  wayland.windowManager.hyprland.settings = {
    "$mainMod" = "SUPER";
    bind = [
      "$mainMod, C, exec, ${terminal} --single-instance --instance-group=hypr" # Changed from Q to C for console/terminal
      "$mainMod, E, exec, ${fileManager}"
      "$mainMod, B, exec, ${browser}"
      "$mainMod, F, fullscreen, 1" # Fullscreen with gaps (focus mode)
      "$mainMod SHIFT, F, fullscreen, 0" # True fullscreen (no gaps)
      "$mainMod, Q, killactive" # Changed from C to Q for quit/close window

      # Toggle pseudo (no auto-resize - pseudo maintains floating dimensions)
      "$mainMod, P, pseudo"

      "$mainMod, R, togglesplit,"

      # Toggle floating with auto-resize to 80% and center
      "$mainMod, T, togglefloating"
      "$mainMod, T, resizeactive, exact 80% 80%"
      "$mainMod, T, centerwindow"

      "$mainMod SHIFT, T, centerwindow" # Center the current window (useful for floating windows)
      "$mainMod, grave, hyprexpo:expo, toggle"

      "$mainMod, V, exec, vicinae vicinae://extensions/vicinae/clipboard/history"
      "$mainMod SHIFT, V, exec, walker -m clipboard"

      "$mainMod ALT, L, exec, hyprlock"

      # logout menu
      "$mainMod, Escape, exec, ${toggle "wleave" false} -p layer-shell --no-version-info --show-keybinds=true"

      # Move focus with SUPER+hjkl (using SUPER+ALT+L for right to avoid conflict with lock)
      "$mainMod, H, movefocus, l"
      "$mainMod, L, movefocus, r"
      "$mainMod, K, movefocus, u"
      "$mainMod, J, movefocus, d"

      # Switch workspaces with mainMod + [0-9]
      "$mainMod, 1, workspace, 1"
      "$mainMod, 2, workspace, 2"
      "$mainMod, 3, workspace, 3"
      "$mainMod, 4, workspace, 4"
      "$mainMod, 5, workspace, 5"
      "$mainMod, 6, workspace, 6"
      "$mainMod, 7, workspace, 7"
      "$mainMod, 8, workspace, 8"
      "$mainMod, 9, workspace, 9"

      # to switch between windows in a floating workspace
      "$mainMod, Tab, cyclenext," # change focus to another window
      "$mainMod, Tab, bringactivetotop," # bring it to the top
      "$mainMod SHIFT, Tab, cyclenext, prev" # change focus to previous window
      "$mainMod SHIFT, Tab, bringactivetotop," # bring it to the top

      # Move active window to a workspace with mainMod + SHIFT + [0-9]
      "$mainMod SHIFT, 1, movetoworkspace, 1"
      "$mainMod SHIFT, 2, movetoworkspace, 2"
      "$mainMod SHIFT, 3, movetoworkspace, 3"
      "$mainMod SHIFT, 4, movetoworkspace, 4"
      "$mainMod SHIFT, 5, movetoworkspace, 5"
      "$mainMod SHIFT, 6, movetoworkspace, 6"
      "$mainMod SHIFT, 7, movetoworkspace, 7"
      "$mainMod SHIFT, 8, movetoworkspace, 8"
      "$mainMod SHIFT, 9, movetoworkspace, 9"

      # Scroll through non-empty workspaces on current monitor (m = monitor, skips empty)
      "$mainMod SHIFT, L, workspace, m+1"
      "$mainMod SHIFT, H, workspace, m-1"
      "$mainMod, mouse_down, workspace, m+1"
      "$mainMod, mouse_up, workspace, m-1"

      # Example special workspace (scratchpad)down
      "$mainMod, S, togglespecialworkspace, magic"
      "$mainMod, M, movetoworkspace, special:magic"

      "$ALT, SPACE, exec, vicinae vicinae://toggle"
      "$ALTSHIFT, SPACE, exec, walker"

      # === PRODUCTIVITY SHORTCUTS ===
      # Quick application access
      "$mainMod, A, exec, sesh-launcher" # Tmux session launcher
      "$mainMod, N, exec, obsidian" # Notes
      "$mainMod, Y, exec, ${youtube-music}" # Music
      "$mainMod SHIFT, V, exec, pavucontrol" # Volume control
      "$mainMod SHIFT, B, exec, blueman-manager" # Bluetooth

      # Quick workspace jumps to organized workflow
      # Note: Use IDs not names - named workspaces create dynamic WS with negative IDs
      "$mainMod, D, workspace, 1" # Development (kitty) - same as Super+1
      "$mainMod SHIFT, D, movetoworkspace, 1" # Move to dev workspace
      "$mainMod, W, workspace, 2" # Web (browsers) - same as Super+2
      "$mainMod SHIFT, W, movetoworkspace, 2" # Move to web workspace

      # Window management helpers
      "$mainMod CTRL, H, movewindow, l" # Move window left
      "$mainMod CTRL, L, movewindow, r" # Move window right
      "$mainMod CTRL, K, movewindow, u" # Move window up
      "$mainMod CTRL, J, movewindow, d" # Move window down

      # Resize windows
      "$mainMod, left, resizeactive, -20 0"
      "$mainMod, right, resizeactive, 20 0"
      "$mainMod, up, resizeactive, 0 -20"
      "$mainMod, down, resizeactive, 0 20"

      # Quick resize shortcuts (smart: works for both floating and tiled/pseudo)
      "$mainMod, equal, exec, window-resize grow"
      "$mainMod, minus, exec, window-resize shrink"

      ", XF86AudioPlay, exec, ${runOnce youtube-music}"

      # Screenshot modes
      ", Print, exec, grimblast-satty" # screenshot with frozen screen and satty editor (mapped from SUPER+SHIFT+S via xremap)
      "ALT SHIFT, S, exec, screenshot-menu" # screenshot menu with vicinae

      # Screen recording (similar to grimblast)
      "$mainMod SHIFT, R, exec, record-screen-mp4" # record selected area/window as MP4
      "$ALTSHIFT, R, exec, record-screen-gif" # record selected area/window as GIF
    ];
    bindm = [
      # Move/resize windows with mainMod + LMB/RMB and dragging
      "$mainMod, mouse:272, movewindow"
      "$mainMod, mouse:273, resizewindow"
      "$mainMod ALT, mouse:272, resizewindow"
    ];

    bindl = [
      # media controls
      ", XF86AudioPlay, exec, playerctl play-pause"
      ", XF86AudioPrev, exec, playerctl previous"
      ", XF86AudioNext, exec, playerctl next"

      # volume with swaync notifications - updated to use new script options
      ", XF86AudioMute, exec, volume-control --toggle"
      ", XF86AudioMicMute, exec, volume-control --toggle-mic"
    ];
    bindle = [
      # volume with swaync notifications - updated to use new script options
      ", XF86AudioRaiseVolume, exec, volume-control --inc"
      ", XF86AudioLowerVolume, exec, volume-control --dec"

      # backlight - updated to use new script options
      ", XF86MonBrightnessUp, exec, brightness-control --inc"
      ", XF86MonBrightnessDown, exec, brightness-control --dec"

      # Resize windows
      "$mainMod, left, resizeactive, -20 0"
      "$mainMod, right, resizeactive, 20 0"
      "$mainMod, up, resizeactive, 0 -20"
      "$mainMod, down, resizeactive, 0 20"
    ];

    bindr = [
      # launcher
      # "$mainMod, SUPER_L, exec, vicinae vicinae://toggle"  # Fix toggle for vicinae
      # "$mainMod, SUPER_L, exec, vicinae"
    ];
  };
}
