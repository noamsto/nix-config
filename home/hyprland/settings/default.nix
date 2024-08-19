{
  pkgs,
  config,
  ...
}: let
  pointer = config.home.pointerCursor;
  cursorName = "Bibata-Modern-Ice";
  # cursorPackage = pkgs.callPackage ./../bibata-hyprcursor {}; # Move to flake parts for this!
  variant = "dark";
  c = config.programs.matugen.theme.colors.colors.${variant};
in {
  imports = [./bindings.nix ./window_rule.nix];
  # xdg.dataFile."icons/${cursorName}".source = "${cursorPackage}/share/icons/${cursorName}";
  wayland.windowManager.hyprland = {
    settings = let
      laptop-monitor = "eDP-1";
      laptop-monitor-pos = "${laptop-monitor},2880x1800, 2048x1152,1.40625";
      home-ext-monitor-left = "desc:Samsung Electric Company S27H85x H4ZM300138";
      home-ext-monitor-right = "desc:Samsung Electric Company S27H85x H4ZKB00167";
    in {
      monitor = [
        "${home-ext-monitor-left},2560x1440,0x0, 1.25" # Left External Monitor
        "${home-ext-monitor-right},2560x1440, 2048x0,1.25" # Right External Monitor Home
        laptop-monitor-pos # Laptop Monitor
        ",preferred,auto,auto"
      ];
      # bindl = [
      #   # trigger when the switch is turning on
      #   ", switch:on:Lid Switch, exec, hyprctl keyword monitor \"${laptop-monitor}, disable\""
      #   # trigger when the switch is turning off
      #   ", switch:off:Lid Switch, exec, hyprctl keyword monitor \"${laptop-monitor-pos}\""
      # ];
      workspace = [
        "1,default:true,monitor:${home-ext-monitor-left},persistent:true"
        "2,monitor:${home-ext-monitor-right},persistent:true"
        "3,monitor:${laptop-monitor},persistent:true"
      ];

      env = [
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "HYPRCURSOR_THEME,${cursorName}"
        "HYPRCURSOR_SIZE,${toString pointer.size}"
      ];

      exec-once = [
        # set cursor for HL itself
        "hyprctl setcursor ${cursorName} ${toString pointer.size}"
        "hyprlock"

        # Tmux wayland integration
        "tmux setenv -g HYPRLAND_INSTANCE_SIGNATURE \"$HYPRLAND_INSTANCE_SIGNATURE\""
        "tmux setenv -g WAYLAND_DISPLAY \"$WAYLAND_DISPLAY\""
        "tmux setenv -g XDG_RUNTIME_DIR \"$XDG_RUNTIME_DIR\""
      ];

      input = {
        kb_layout = "us,il";
        kb_options = "grp:win_space_toggle";
        # focus change on cursor move
        follow_mouse = 1;
        accel_profile = "flat";
        touchpad.scroll_factor = 0.1;
      };

      general = {
        gaps_in = 5;
        gaps_out = 5;
        border_size = 1;
        "col.active_border" = "rgba(88888888)";
        "col.inactive_border" = "rgba(00000088)";

        allow_tearing = true;
        resize_on_border = true;
      };

      decoration = {
        rounding = 16;
        blur = {
          enabled = true;
          brightness = 1.0;
          contrast = 1.0;
          noise = 0.01;

          vibrancy = 0.2;
          vibrancy_darkness = 0.5;

          passes = 4;
          size = 7;

          popups = true;
          popups_ignorealpha = 0.2;
        };

        drop_shadow = true;
        shadow_ignore_window = true;
        shadow_offset = "0 15";
        shadow_range = 100;
        shadow_render_power = 2;
        shadow_scale = 0.97;
        "col.shadow" = "rgba(00000055)";
      };
      dwindle = {
        # keep floating dimensions while tiling
        pseudotile = true;
        preserve_split = true;
      };

      misc = {
        # disable auto polling for config file changes
        disable_autoreload = true;

        force_default_wallpaper = 0;

        # disable dragging animation
        animate_mouse_windowdragging = false;

        # enable variable refresh rate (effective depending on hardware)
        vrr = 1;
      };
      render.direct_scanout = true;

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
            "rgb(${c.error}), 16, 󰖭, hyprctl dispatch killactive"
            # maximize
            "rgb(${c.primary}), 16, 󰖯, hyprctl dispatch fullscreen 1"
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
