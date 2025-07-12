{config, ...}: let
  pointer = config.home.pointerCursor;
  cursorName = "Bibata-Modern-Ice";
in {
  imports = [./bindings.nix ./window_rule.nix ./animations.nix];
  wayland.windowManager.hyprland = {
    settings = {
      monitor = [
        ",preferred,auto,auto"
      ];
      bindl = [
        # trigger when the switch is turning on
        # ", switch:on:Lid Switch, exec, ${lib.getExe' pkgs.kanshi "kanshictl"} switch home-docked-lid-close"
        # trigger when the switch is turning off
        # ", switch:off:Lid Switch, exec, ${lib.getExe' pkgs.kanshi "kanshictl"} switch home-docked-lid-open"
      ];
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
      ];

      exec-once = [
        # start hyprlock first to handle authentication properly
        "hyprlock"

        # start quickshell for shell interface (kill existing first)
        "pkill quickshell || true; sleep 0.5; quickshell"

        # set cursor for HL itself
        "hyprctl setcursor ${cursorName} ${toString pointer.size}"

        # Tmux wayland integration
        "tmux setenv -g HYPRLAND_INSTANCE_SIGNATURE \"$HYPRLAND_INSTANCE_SIGNATURE\""
        "tmux setenv -g WAYLAND_DISPLAY \"$WAYLAND_DISPLAY\""
        "tmux setenv -g XDG_RUNTIME_DIR \"$XDG_RUNTIME_DIR\""

        "wl-paste -p -w wl-copy &" # Merge primary selection clipboard with regular clipboard
      ];

      input = {
        kb_layout = "us,il";
        kb_options = "grp:win_space_toggle";
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
        gaps_out = 5;
        border_size = 1;
        "col.active_border" = "rgba(88888888)";
        "col.inactive_border" = "rgba(00000088)";

        allow_tearing = true;
        resize_on_border = true;
        no_focus_fallback = true;
        layout = "dwindle";
      };

      decoration = {
        rounding = 16;
        active_opacity = 1.0;
        inactive_opacity = 1.0;

        blur = {
          enabled = true;
          brightness = 1.0;
          contrast = 1.0;
          noise = 0.01;

          vibrancy = 0.2;
          vibrancy_darkness = 0.5;

          passes = 3;
          size = 6;

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
      };
      render = {
        direct_scanout = true;
      };

      # touchpad gestures
      gestures = {
        workspace_swipe = true;
        workspace_swipe_forever = true;
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
