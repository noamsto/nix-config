{config, ...}: let
  pointer = config.home.pointerCursor;
  cursorName = "Bibata-Modern-Ice";
in {
  imports = [./bindings.nix ./window_rule.nix ./animations.nix];
  wayland.windowManager.hyprland = {
    settings = {
      # Source hyprdynamicmonitors generated config
      source = ["~/.config/hypr/monitors.conf"];

      monitor = [
        # Fallback for any monitor not configured by hyprdynamicmonitors
        ",preferred,auto,auto"
      ];
      workspace = [
        # Persistent workspaces - these will always exist even if empty
        "1, persistent:true"
        "2, persistent:true"
        "3, persistent:true"
        "4, persistent:true"
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

        # Chromium-based browser fixes:
        # 1. --disable-accelerated-2d-canvas: Fix AMD Radeon 780M PDF rendering artifacts
        #    Upstream bug: https://issues.chromium.org/40184451
        # 2. --disable-features=WaylandWpColorManagerV1: Fix crashes when moving between monitors
        #    Upstream bug: Chrome 141 Wayland regression (fixed in main, Oct 2025)
        #    Issue: https://github.com/brave/brave-browser/issues/49921
        "BRAVE_USER_FLAGS,--disable-accelerated-2d-canvas --disable-features=WaylandWpColorManagerV1"
        "CHROMIUM_USER_FLAGS,--disable-accelerated-2d-canvas --disable-features=WaylandWpColorManagerV1"

        "WLR_NO_HARDWARE_CURSORS,1"
      ];

      exec-once = [
        # set cursor for HL itself
        "hyprctl setcursor ${cursorName} ${toString pointer.size}"

        # Load XWayland HiDPI settings
        "xrdb -merge ~/.Xresources"

        # Tmux wayland integration
        "tmux setenv -g HYPRLAND_INSTANCE_SIGNATURE \"$HYPRLAND_INSTANCE_SIGNATURE\""
        "tmux setenv -g WAYLAND_DISPLAY \"$WAYLAND_DISPLAY\""
        "tmux setenv -g XDG_RUNTIME_DIR \"$XDG_RUNTIME_DIR\""

        "kitty --single-instance --instance-group=hypr"

        "launch-dock"

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
          scroll_factor = 0.6; # Reduced for finer control in 3D viewports
          disable_while_typing = true;
          tap-to-click = true;
          # Note: clickfinger and drag_lock are configured at system level in nixos/desktop/default.nix
        };
      };

      general = {
        gaps_in = 5;
        gaps_out = 15; # Increased for more margins in fullscreen mode
        border_size = 2; # Reduced for subtlety
        "col.active_border" = "rgba(89b4fa66) rgba(cba6f766) 45deg"; # Blue to mauve gradient with reduced opacity
        "col.inactive_border" = "rgba(31324455)"; # Even more subtle inactive border

        allow_tearing = true;
        resize_on_border = true;
        extend_border_grab_area = 15; # Extends border grab area (works on floating windows)
        hover_icon_on_border = true; # Shows resize cursor on border hover
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
          render_power = 3; # Increased from 2 for stronger shadow effect
          ignore_window = true;
          color = "rgba(00000099)"; # Increased opacity from 55 to 99 for darker shadow
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
        disable_hyprland_logo = true;

        # disable dragging animation
        animate_mouse_windowdragging = false;

        # enable variable refresh rate (effective depending on hardware)
        vrr = 2; # Improved VRR mode
        vfr = true;

        # enable window swallowing
        enable_swallow = true;
        swallow_regex = "^(foot|kitty)$";

        # Fullscreen behavior
        layers_hog_keyboard_focus = true; # Ensure fullscreen windows get keyboard focus
      };
      render = {
        direct_scanout = true;
        # explicit_sync is now default in Hyprland 0.50+, no need to configure
      };

      # Gesture bindings (Hyprland 0.51+ new syntax)
      # Format: fingers, direction, action
      # Note: Only workspace action is confirmed to work reliably in Hyprland 0.51
      gesture = [
        # === 3-FINGER GESTURES (Primary Workflow Navigation) ===
        # Horizontal swipe: Switch workspaces
        "3, horizontal, workspace"

        # === PINCH GESTURES ===
        # 2-finger pinch: Passed through to applications (Blender, Bambu Studio, browsers)
        # This allows native app zoom/rotate functionality

        # Note: Additional gestures can be added using libinput-gestures
        # See home/desktop/hyprland/services/libinput-gestures.nix
      ];

      xwayland.force_zero_scaling = true;
      debug.disable_logs = false;
      plugin = {
        hyprbars = {
          bar_height = 24;
          bar_precedence_over_border = true;
          bar_text_font = "FiraCode Nerd Font";
          "col.text" = "rgb(cdd6f4)"; # Light text color for better readability
          "bar_color" = "rgba(1e1e2ecc)"; # More opaque dark background
          "bar_text_size" = 12;

          # order is right-to-left
          hyprbars-button = [
            # close - red (catppuccin mocha)
            "rgb(f38ba8), 16, 󰖭, hyprctl dispatch killactive"
            # maximize - green (catppuccin mocha)
            "rgb(a6e3a1), 16, 󰖯, hyprctl dispatch fullscreen 1"
            # pin/unpin toggle - yellow (catppuccin mocha)
            "rgb(f9e2af), 16, 󰐃, hyprctl dispatch pin active"
          ];
        };

        hyprexpo = {
          columns = 3;
          gap_size = 4;
          bg_col = "rgb(000000)";

          enable_gesture = true;
          gesture_distance = 250; # More responsive overview activation
          gesture_positive = false;
        };
      };
    };
  };
}
