{config, ...}: let
  pointer = config.home.pointerCursor;
  cursorName = pointer.name;
  iconThemeName = config.gtk.iconTheme.name;
in {
  imports = [./bindings.nix ./window_rule.nix ./animations.nix];
  wayland.windowManager.hyprland = {
    settings = {
      source = ["~/.config/hypr/monitors.conf"];
      monitor = [",preferred,auto,auto"];

      env = [
        "XCURSOR_SIZE,${toString pointer.size}"
        "HYPRCURSOR_SIZE,${toString pointer.size}"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "HYPRCURSOR_THEME,${cursorName}"
        "XDG_CURRENT_DESKTOP,Hyprland"
        "XDG_SESSION_TYPE,wayland"
        "XDG_SESSION_DESKTOP,Hyprland"
        "MOZ_ENABLE_WAYLAND,1"
        "MOZ_ENABLE_XDG_DIRS,1"
        "GTK_THEME,Adwaita:dark" # theme-toggle updates at runtime

        # --disable-accelerated-2d-canvas: AMD Radeon 780M PDF rendering artifacts
        # https://issues.chromium.org/40184451
        "BRAVE_USER_FLAGS,--disable-accelerated-2d-canvas"
        "CHROMIUM_USER_FLAGS,--disable-accelerated-2d-canvas"

        "QS_ICON_THEME,${iconThemeName}"
      ];

      # SW cursors render the cursor into the framebuffer so it is captured by
      # every screencopy path. WLR_NO_HARDWARE_CURSORS was a wlroots env var and
      # is a no-op under Hyprland's aquamarine backend — this is the live knob.
      cursor.no_hardware_cursors = true;

      exec-once = [
        "hyprctl setcursor ${cursorName} ${toString pointer.size}"
        "theme-toggle restore"
        "xrdb -merge ~/.Xresources"

        # Propagate Wayland env to fish (universal vars) and tmux (global env)
        "fish -c 'set -Ux HYPRLAND_INSTANCE_SIGNATURE $HYPRLAND_INSTANCE_SIGNATURE; set -Ux WAYLAND_DISPLAY $WAYLAND_DISPLAY'"
        "tmux setenv -g HYPRLAND_INSTANCE_SIGNATURE \"$HYPRLAND_INSTANCE_SIGNATURE\""
        "tmux setenv -g WAYLAND_DISPLAY \"$WAYLAND_DISPLAY\""
        "tmux setenv -g XDG_RUNTIME_DIR \"$XDG_RUNTIME_DIR\""

        "kitty --single-instance --instance-group=hypr"

        # Noctalia shell (upstream deprecated systemd autostart)
        "noctalia-shell"
      ];

      input = {
        kb_layout = "us,il";
        kb_options = "grp:win_space_toggle";
        follow_mouse = 1;
        accel_profile = "adaptive";
        sensitivity = 0;

        touchpad = {
          natural_scroll = true;
          scroll_factor = 0.6;
          disable_while_typing = true;
          tap-to-click = true;
          # Note: clickfinger and drag_lock are configured at system level in nixos/desktop/default.nix
        };
      };

      # External mice: flat for 1:1 movement, trackpoint: adaptive with reduced speed
      device = [
        {
          name = "logitech-wireless-mouse-*";
          accel_profile = "flat";
        }
        {
          name = "logitech-usb-receiver-mouse";
          accel_profile = "flat";
        }
        {
          name = "tpps/2-elan-trackpoint";
          sensitivity = -0.4;
          accel_profile = "adaptive";
        }
      ];

      general = {
        gaps_in = 5;
        gaps_out = 15;
        border_size = 2;
        "col.active_border" = "rgba(89b4fa66) rgba(cba6f766) 45deg";
        "col.inactive_border" = "rgba(31324455)";

        allow_tearing = true;
        resize_on_border = true;
        extend_border_grab_area = 15;
        hover_icon_on_border = true;
        no_focus_fallback = true;
        layout = "dwindle";
      };

      decoration = {
        rounding = 10;
        # Terminals (kitty/foot/ghostty) override these back to 1.0 in window_rule.nix —
        # they manage their own background_opacity so glyphs stay fully opaque.
        active_opacity = 0.97;
        inactive_opacity = 0.92;
        fullscreen_opacity = 1.0;

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
          render_power = 3;
          color = "rgba(00000099)";
        };
      };
      dwindle = {
        preserve_split = true;
      };

      master = {
        new_status = "slave";
      };

      misc = {
        disable_autoreload = true;
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
        animate_mouse_windowdragging = false;

        vrr = 2;

        enable_swallow = true;
        swallow_regex = "^(foot|kitty|com\\.mitchellh\\.ghostty)$";

        layers_hog_keyboard_focus = true;

        # Honor xdg-activation tokens from launchers (walker/vicinae), browsers
        # opening links, password managers, etc. — switches workspace + focuses
        # the requesting window instead of dropping the request.
        focus_on_activate = true;

        # Allow a new lockscreen to take over if the previous one crashed
        # (e.g. Noctalia dies during monitor topology change on undock)
        allow_session_lock_restore = true;
      };
      render = {
        direct_scanout = true;
      };

      gesture = [
        "3, horizontal, workspace"
      ];

      # 0 = every scroll tick is matched against binds and consumed when one
      # matches. Default 300ms makes consecutive fast scrolls bypass keybind
      # matching and leak through to the focused app (e.g. browser scrolls
      # while Super+Ctrl scroll is zooming).
      binds.scroll_event_delay = 0;

      xwayland.force_zero_scaling = true;
      debug.disable_logs = false;
    };
  };

  # AMD DCC screencast workaround — two parts. On AMD GFX10+/11, portal screen
  # recording (gpu-screen-recorder via xdph) aborts with "no more input formats":
  # the captured DMA-BUF arrives with a DCC-tiled modifier (e.g. 0x20000001046bb04)
  # that Mesa's EGL import cannot consume ("failed to create egl image with
  # modifier"), so gsr renegotiates until the producer runs out of formats.
  #
  # Part 1: AQ_NO_MODIFIERS=1 makes aquamarine *advertise* the linear (0x0)
  # modifier for screencast/screencopy buffers. Necessary but NOT sufficient — it
  # only controls what's offered, not what xdph's gbm actually allocates, which
  # still picks DCC-tiled buffers.
  # MUST live in uwsm's pre-launch env: aquamarine reads it at backend init, which
  # happens before Hyprland parses `env =`. Setting it via `env =` reaches child
  # apps but is too late for the backend. uwsm sources this file before launch.
  xdg.configFile."uwsm/env-hyprland".text = ''
    export AQ_NO_MODIFIERS=1
  '';

  # Part 2: AMD_DEBUG=nodcc on the portal backend makes its gbm allocation skip
  # DCC so gsr can EGL-import the buffer. Scoped to the portal alone (drop-in on
  # the NixOS-provided user unit) to keep DCC on for the compositor and every
  # other GL app; verified that restarting only the portal with this fixes it.
  #
  # TODO: revisit — drop both parts once Mesa fixes EGL import of AMD DCC
  # modifiers. Upstream tracking: https://github.com/hyprwm/Hyprland/discussions/14467
  xdg.configFile."systemd/user/xdg-desktop-portal-hyprland.service.d/nodcc.conf".text = ''
    [Service]
    Environment=AMD_DEBUG=nodcc
  '';
}
