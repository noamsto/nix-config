{lib, ...}: let
  terminal = "footclient";
  fileManager = "thunar";
  browser = "firefox";

  toggle = program: service: let
    prog = builtins.substring 0 14 program;
    runserv = lib.optionalString service "run-as-service";
  in "pkill ${prog} || ${runserv} ${program}";

  runOnce = program: "pgrep ${program} || ${program}";
in {
  wayland.windowManager.hyprland.settings = {
    "$mainMod" = "SUPER";
    "$screenshotarea" = ''hyprctl keyword animation "fadeOut,0,0,default"; grimblast --notify copysave area; hyprctl keyword animation "fadeOut,1,4,default"'';
    bind = [
      "$mainMod, Q, exec, ${terminal}"
      "$mainMod, E, exec, ${fileManager}"
      "$mainMod, B, exec, ${browser}"
      "$mainMod, F, fullscreen"
      "$mainMod, C, killactive"
      "$mainMod, P, pseudo"
      "$mainMod, R, togglesplit,"
      "$mainMod, T, togglefloating,"
      "$mainMod, grave, hyprexpo:expo, toggle"

      "$mainMod, V, exec, walker -m clipboard"

      "$mainMod ALT, L, exec, ${runOnce "hyprlock"}"

      # logout menu
      "$mainMod, Escape, exec, ${toggle "wlogout" true} -p layer-shell"

      # Move focus with SUPER+hjkl
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
      "$mainMod SHIFT, 0, movetoworkspace, 10"

      # Scroll through existing workspaces with mainMod + scroll
      "$mainMod SHIFT, L, workspace, e+1"
      "$mainMod SHIFT, H, workspace, e-1"
      "$mainMod, mouse_down, workspace, e+1"
      "$mainMod, mouse_up, workspace, e-1"

      # Example special workspace (scratchpad)down
      "$mainMod, S, togglespecialworkspace, magic"
      "$mainMod, M, movetoworkspace, special:magic"

      "$ALT, SPACE, exec, walker"

      # Resize windows
      "$mainMod, left, resizeactive, -20 0"
      "$mainMod, right, resizeactive, 20 0"
      "$mainMod, up, resizeactive, 0 -20"
      "$mainMod, down, resizeactive, 0 20"

      ", XF86AudioPlay, exec, ${runOnce "spotify"}"

      "$mainMod, Print, exec, grimblast --notify --cursor copysave output" # copy all active outputs
      "$ALTSHIFT, S, exec, grimblast --notify --cursor copysave screen" # copy active screen
      "$ALTSHIFT, R, exec, grimblast --notify --cursor copysave area" # copy selection area
      ", Print, exec, $screenshotarea" # screenshot selection area
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

      # volume
      ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
      ", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
    ];
    bindle = [
      # volume
      ", XF86AudioRaiseVolume, exec, wpctl set-volume -l '1.0' @DEFAULT_AUDIO_SINK@ 6%+"
      ", XF86AudioLowerVolume, exec, wpctl set-volume -l '1.0' @DEFAULT_AUDIO_SINK@ 6%-"

      # backlight
      ", XF86MonBrightnessUp, exec, brillo -q -u 300000 -A 5"
      ", XF86MonBrightnessDown, exec, brillo -q -u 300000 -U 5"

      # Resize windows
      "$mainMod, left, resizeactive, -20 0"
      "$mainMod, right, resizeactive, 20 0"
      "$mainMod, up, resizeactive, 0 -20"
      "$mainMod, down, resizeactive, 0 20"
    ];

    bindr = [
      # launcher
      # "$mainMod, SUPER_L, exec, ${toggle "walker" false}"  # Fix toggle for walker
      # "$mainMod, SUPER_L, exec, walker"
    ];
  };
}
