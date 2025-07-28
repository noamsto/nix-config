{
  config,
  lib,
  pkgs,
  ...
}: let
  pointer = config.home.pointerCursor;
  cursorName = "Bibata-Modern-Ice";

  # Import utility functions
  runOnce = program: let
    progName = builtins.baseNameOf program;
  in "pgrep ${progName} || ${program}";
in {
  imports = [./bindings.nix ./window_rule.nix ./animations.nix];
  wayland.windowManager.hyprland = {
    settings = {
      monitor = [
        # Fallback for any monitor not configured by kanshi
        ",preferred,auto,auto"
      ];
      # bindl = [
      #   # Lid closes - switch to appropriate lid-close profile
      #   ", switch:on:Lid Switch, exec, ${lib.getExe pkgs.bash} -c 'monitors=$(hyprctl monitors); if echo \"$monitors\" | grep -q \"Samsung Electric Company S27H85x\"; then kanshictl switch home-docked-lid-close; elif echo \"$monitors\" | grep -q \"Dell Inc. DELL P2723DE\"; then kanshictl switch work-docked-lid-close; else kanshictl switch undocked; fi'"
      #   # Lid opens - switch to appropriate lid-open profile
      #   ", switch:off:Lid Switch, exec, ${lib.getExe pkgs.bash} -c 'monitors=$(hyprctl monitors); if echo \"$monitors\" | grep -q \"Samsung Electric Company S27H85x\"; then kanshictl switch home-docked-lid-open; elif echo \"$monitors\" | grep -q \"Dell Inc. DELL P2723DE\"; then kanshictl switch work-docked-lid-open; else kanshictl switch undocked; fi'"
      # ];
      workspace = [
        "1,persistent:true"
        "2,persistent:true"
        "3,persistent:true"
      ];

      env = [
        "XCURSOR_SIZE,${toString pointer.size}"
        "HYPRCURSOR_SIZE,${toString pointer.size}"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "HYPRCURSOR_THEME,${cursorName}"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_TYPE,wayland"
        "XDG_SESSION_DESKTOP,Hyprland"
        "MOZ_ENABLE_WAYLAND,1"
        "WLR_NO_HARDWARE_CURSORS,1"
      ];

      exec-once = [
        # start waybar only if not already running
        "${runOnce "${lib.getExe pkgs.waybar}"}"

        # set cursor for HL itself
        "hyprctl setcursor ${cursorName} ${toString pointer.size}"

        # Tmux wayland integration
        "tmux setenv -g HYPRLAND_INSTANCE_SIGNATURE \"$HYPRLAND_INSTANCE_SIGNATURE\""
        "tmux setenv -g WAYLAND_DISPLAY \"$WAYLAND_DISPLAY\""
        "tmux setenv -g XDG_RUNTIME_DIR \"$XDG_RUNTIME_DIR\""

        # "wl-paste -p -w wl-copy &" # Merge primary selection clipboard with regular clipboard
      ];

      input = {
        kb_layout = "us,il";
        kb_options = "grp:win_space_toggle,caps:escape";
        # focus change on cursor move
        follow_mouse = 1;
        accel_profile = "flat";
        sensitivity = 0;

        touchpad = {
          natural_scroll = true;
          scroll_factor = 1.0;
          disable_while_typing = true;
          "tap-to-click" = true;
        };
      };

      general = {
        gaps_in = 5;
        gaps_out = 10; # Increased from 5 to add more space around windows
        border_size = 2; # Reduced for subtlety
        "col.active_border" = "rgba(89b4fa66) rgba(cba6f766) 45deg"; # Blue to mauve gradient with reduced opacity
        "col.inactive_border" = "rgba(31324455)"; # Even more subtle inactive border

        allow_tearing = true;
        resize_on_border = true;
        no_focus_fallback = true;
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
        active_opacity = 1.0;
        inactive_opacity = 1.0;

        blur = {
          enabled = true;
          brightness = 1.0;
          contrast = 1.0;
          noise = 0.01;

          vibrancy = 0.2;
          vibrancy_darkness = 0.5;

          passes = 2;
          size = 6;
          new_optimizations = true;

          popups = true;
          popups_ignorealpha = 0.2;
        };

        shadow = {
          enabled = true;
          offset = "0 15";
          range = 100;
          scale = 0.97;
          render_power = 2;
          ignore_window = true;
          color = "rgba(00000055)";
        };
      };
      dwindle = {
        # keep floating dimensions while tiling
        pseudotile = true;
        # preserve split orientation when toggling
        preserve_split = true;
      };

      master = {
        new_status = "slave";
      };

      misc = {
        # disable auto polling for config file changes
        disable_autoreload = true;

        force_default_wallpaper = 0;
        disable_hyprland_logo = false;

        # disable dragging animation
        animate_mouse_windowdragging = false;

        # enable variable refresh rate (effective depending on hardware)
        vrr = 1;
        vfr = true;

        # enable window swallowing
        enable_swallow = true;
        swallow_regex = "^(foot|kitty|Alacritty)$";

        # Fullscreen behavior
        layers_hog_keyboard_focus = true; # Ensure fullscreen windows get keyboard focus
      };
      render = {
        direct_scanout = true;
      };

      # touchpad gestures
      gestures = {
        workspace_swipe = true;
        workspace_swipe_forever = true;
        workspace_swipe_fingers = 4;
        workspace_swipe_distance = 150; # Reduced from 300 for more responsive swiping
        workspace_swipe_invert = true;
        workspace_swipe_min_speed_to_force = 20; # Reduced from 30 for easier triggering
        workspace_swipe_cancel_ratio = 0.5;
        workspace_swipe_create_new = true; # Create new workspaces when swiping past the last one
      };

      xwayland.force_zero_scaling = true;
      debug.disable_logs = false;
      plugin = {
        hyprbars = {
          bar_height = 24;
          bar_precedence_over_border = true;
          bar_text_font = "FiraCode Nerd Font";

          # order is right-to-left
          hyprbars-button = [
            # close
            "rgb(ff5555), 16, 󰖭, hyprctl dispatch killactive"
            # maximize
            "rgb(50fa7b), 16, 󰖯, hyprctl dispatch fullscreen 1"
          ];
        };

        hyprexpo = {
          columns = 3;
          gap_size = 4;
          bg_col = "rgb(000000)";

          enable_gesture = true;
          gesture_distance = 300;
          gesture_positive = false;
        };
      };
    };
  };
}
