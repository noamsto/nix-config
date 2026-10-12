# Noctalia Shell - minimal desktop shell for Wayland
# Replaces: waybar, swaync, nwg-dock, wlogout, hyprlock
# Keeps: vicinae (launcher), theme-toggle system
#
# Theme switching: Noctalia is the source of truth for dark/light mode.
# When toggled (via keybind or GUI), Noctalia triggers theme-toggle via hook.
#
# NOTE: This module is only imported when desktop.mode == "hyprland"
# (see home/desktop/default.nix), so no runtime check needed here.
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  noctaliaPackage = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Thin alias kept so scripts and keybinds don't hardcode a store path.
  noctalia-ipc = pkgs.writeShellScriptBin "noctalia-ipc" ''
    exec ${noctaliaPackage}/bin/noctalia msg "$@"
  '';

  # Script to restore wallpaper from saved state
  restore-wallpaper = pkgs.writeShellScriptBin "noctalia-restore-wallpaper" ''
    LAST_WP="$HOME/.local/state/noctalia/last-wallpaper"
    if [ -f "$LAST_WP" ]; then
      WP_PATH=$(cat "$LAST_WP")
      if [ -f "$WP_PATH" ]; then
        # Wait for Noctalia to be ready
        sleep 2
        ${noctalia-ipc}/bin/noctalia-ipc wallpaper-set "$WP_PATH"
        echo "Restored wallpaper: $WP_PATH"
      fi
    fi
  '';
in {
  # Disable Home Manager's own `programs.noctalia` (path relative to its
  # modules directory) so the flake module below stays the sole owner.
  disabledModules = ["programs/noctalia"];

  imports = [
    inputs.noctalia.homeModules.default
    inputs.aegis-lock.homeModules.default
  ];

  config = {
    home = {
      # Add helper scripts to PATH
      # gpu-screen-recorder is required by the screen-recorder plugin
      # glib.bin provides gdbus, required by valent-connect plugin for D-Bus queries
      packages = [noctalia-ipc restore-wallpaper pkgs.gpu-screen-recorder pkgs.glib.bin];

      # Profile picture for Noctalia (symlinked to ~/.face)
      file.".face".source = ./assets/avatar.png;

      # The valent package ships its own XDG autostart entry, whose generated
      # app-…@autostart.service wins the ca.andyholmes.Valent bus name and leaves
      # the unit below exiting 1 and restarting every 3s for the whole session.
      # Hide it so that unit is the only starter.
      file.".config/autostart/ca.andyholmes.Valent-autostart.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Hidden=true
      '';
    };

    systemd.user.services = {
      # Valent daemon - auto-restarts if it crashes (replaces exec-once)
      valent = {
        Unit = {
          Description = "Valent - KDE Connect protocol implementation";
          After = ["graphical-session.target"];
          PartOf = ["graphical-session.target"];
        };
        Service = {
          ExecStart = "${pkgs.valent}/bin/valent --gapplication-service";
          Restart = "on-failure";
          RestartSec = "3s";
        };
        Install = {
          WantedBy = ["graphical-session.target"];
        };
      };

      # Systemd service to restore wallpaper after Noctalia starts
      # Ordered after noctalia.service (the upstream shell unit) instead of
      # racing on graphical-session.target alone; the script's sleep 2 remains
      # as a readiness margin (whether still needed is a separate question).
      noctalia-restore-wallpaper = {
        Unit = {
          Description = "Restore Noctalia wallpaper from saved state";
          After = ["graphical-session.target" "noctalia.service"];
          PartOf = ["graphical-session.target"];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${restore-wallpaper}/bin/noctalia-restore-wallpaper";
        };
        Install = {
          WantedBy = ["graphical-session.target"];
        };
      };

      # The deleted crash monitor capped restarts at 5 per 60s; the upstream
      # unit sets Restart=on-failure but no limit, so state it explicitly.
      noctalia.Unit = {
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };
    }; # systemd.user.services

    # nh home switch sometimes stops a PartOf=graphical-session.target unit
    # without restarting it. Same guard as vicinae's ensureVicinaeRunning.
    home.activation.ensureNoctaliaRunning = lib.hm.dag.entryAfter ["reloadSystemd"] ''
      if ! ${pkgs.systemd}/bin/systemctl --user is-active --quiet noctalia.service; then
        ${pkgs.systemd}/bin/systemctl --user start noctalia.service || true
      fi
    '';

    programs.noctalia = {
      enable = true;
      package = noctaliaPackage;

      systemd.enable = true;

      settings = {
        theme = {
          mode = "dark";
          source = "builtin";
          builtin = "Catppuccin";

          # Keys are aegis-lock's Theme.qml reader schema (unprefixed
          # `primary`, not Noctalia's `mPrimary`). Don't "correct" them.
          templates.user.aegis-lock = {
            input_path = "${./templates/aegis-lock-colors.json.tmpl}";
            output_path = "${config.xdg.configHome}/aegis-lock/colors.json";
          };
        };

        shell = {
          font_family = "Inter Nerd Font";
          avatar_path = "${config.home.homeDirectory}/.face";
          settings_show_advanced = true;
          # v4's shadowDirection was "bottom_right"; v5 names the same
          # direction "down_right" and does not validate this field, so the
          # v4 spelling would be silently ignored.
          shadow.direction = "down_right";
          launch_apps_as_systemd_services = true;
          animation.speed = 1.0;
        };

        location.address = "Tel Aviv";

        brightness.enable_ddcutil = true;

        nightlight = {
          enabled = true;
          temperature_day = 6500;
          temperature_night = 4000;
        };

        wallpaper = {
          enabled = true;
          directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
          fill_mode = "crop";
          automation = {
            enabled = true;
            interval_seconds = 1800;
            order = "random";
          };
        };

        plugins = {
          auto_update = "all";
          enabled = [
            "noctalia/bongocat"
            "8bury/mini-docker"
            "noctalia/screen_recorder"
            "davemhammer/tailscale"
          ];
        };

        # Hooks
        hooks = {
          # v5 passes payloads in the environment, not positionally.
          wallpaper_changed = ["echo \"$NOCTALIA_WALLPAPER_PATH\" > ~/.local/state/noctalia/last-wallpaper"];
          theme_mode_changed = ["theme-toggle apply \"$NOCTALIA_THEME_MODE\""];
          # The exec-once `theme-toggle restore` races noctalia.service; this
          # fires once IPC is up and retries whatever restore recorded failed.
          started = ["theme-toggle sync"];
        };

        osd = {
          kinds.keyboard_layout = false;
          position = "top_right";
        };

        bar.default = {
          position = "top";
          background_opacity = 0.93;
          # v4's density = "spacious" has no v5 equivalent; v5 splits it into
          # explicit thickness (bar height) and scale (content multiplier).
          thickness = 45;
          scale = 1.2;
          concave_edge_corners = true;
          capsule = true;
          widget_spacing = 6;
          padding = 14;
          margin_ends = 4;
          margin_edge = 4;
          radius = 12;
          # Not "overlay": Hyprland keeps only overlay-layer surfaces above a
          # true-fullscreen window, which would leave the bar on screen.
          start = ["bongocat" "clock" "group:sysmon" "active_window" "media"];
          center = ["workspaces"];
          end = [
            "tray"
            "mini_docker"
            "screen_recorder"
            "tailscale"
            "privacy"
            "caffeine"
            "notifications"
            "network"
            "bluetooth"
            "brightness"
            "output_volume"
            "keyboard_layout"
            "battery"
            "control-center"
          ];

          # v4's SystemMonitor was a single widget drawing three stats in one
          # pill. v5's sysmon renders one stat each, so regroup them into a
          # shared capsule.
          capsule_group = [
            {
              id = "sysmon";
              members = ["cpu" "temp" "ram"];
            }
          ];
        };

        widget = {
          clock = {
            type = "clock";
            format = "{:%H:%M}";
          };

          cpu = {
            type = "sysmon";
            show_value = false;
            stat = "cpu_usage";
          };

          temp = {
            type = "sysmon";
            show_value = false;
            stat = "cpu_temp";
          };

          ram = {
            type = "sysmon";
            show_value = false;
            stat = "ram_used";
          };

          active_window = {
            type = "active_window";
            max_length = 145.0;
            title_scroll = "on_hover";
          };

          media = {
            type = "media";
            max_length = 145.0;
            title_scroll = "on_hover";
          };

          workspaces = {
            type = "workspaces";
            label_source = "id";
            show_labels = true;
            labels_only_when_occupied = true;
            max_label_chars = 2;
            empty_color = "secondary";
            occupied_color = "secondary";
            focused_color = "primary";
            hide_when_empty = false;
            show_icons = true;
            # v4 displayMode="onhover" has no v5 equivalent (show_label is a
            # plain bool), so match v4's resting appearance: glyph only.
          };

          network.show_label = false;
          bluetooth.show_label = false;
          brightness.show_label = false;

          output_volume = {
            type = "volume";
            device = "output";
            show_label = false;
          };

          battery.show_label = false;

          bongocat.type = "noctalia/bongocat:cat";
          mini_docker.type = "8bury/mini-docker:mini-docker";
          screen_recorder.type = "noctalia/screen_recorder:recorder";

          tailscale = {
            type = "davemhammer/tailscale:status";
            show_counts = false;
          };

          # v4 showed a collapsed tray chevron; v5 defaults to bare inline
          # icons that ignore widget_spacing and crowd the neighbouring
          # capsule.
          tray = {
            drawer = true;
            drawer_columns = 3;
          };

          privacy.hide_inactive = true;
        };

        # Declaring any shortcut replaces v5's whole default set — list them all.
        control_center.shortcuts = [
          {type = "wifi";}
          {type = "bluetooth";}
          {type = "dark_mode";}
          {type = "wallpaper";}
          {type = "notification";}
          {type = "power_profile";}
          {type = "nightlight";}
          {type = "system";}
        ];

        # v4 disabled the brightness card; v5 restructured cards into tabs,
        # so the equivalent is hiding the `monitor` tab.
        control_center.hidden_tabs = ["monitor"];

        # v4 pluginSettings.tailscale.compactMode -> widget show_counts (see
        # widget.tailscale above); sshUsername -> ssh_user. v4's
        # terminalCommand and defaultPeerAction have no v5 setting.
        plugin_settings."davemhammer/tailscale".ssh_user = "noams";

        # Ported from the v4 GUI layer (gui-settings.json), not the
        # Nix-written settings.json — the dock only ever lived in the GUI
        # layer.
        dock = {
          enabled = true;
          position = "bottom";
          auto_hide = true;
          background_opacity = 1.0;
          active_monitor_only = true;
          # v5 dims and shrinks every non-focused app by default (0.85/0.85);
          # 1.0 disables that emphasis.
          inactive_opacity = 1.0;
          inactive_scale = 1.0;
          show_dots = false;
          launcher_position = "none";
          pinned = [];
          layer = "overlay";
          margin_edge = 8;
          reserve_space = false;
        };

        notification = {
          layer = "overlay";
          position = "top_right";
          background_opacity = 1.0;
        };

        # aegis-lock owns locking; hypridle owns the idle trigger.
        lockscreen.enabled = false;

        # Declaring any entry replaces v5's whole default action set — list
        # them all. Valid actions: lock, logout, suspend, lock_and_suspend,
        # reboot, shutdown, command. `config validate` does NOT check this
        # field, so a typo here fails silently at runtime.
        shell.session.actions = [
          {
            # NOT action = "lock": the panel drops the built-in lock action
            # when lockscreen.enabled is false, before it reads `command`,
            # so that combination renders no button at all.
            action = "command";
            command = "aegis-lock";
            label = "Lock";
            glyph = "lock";
            shortcut = "1";
          }
          {
            action = "suspend";
            shortcut = "2";
            countdown_seconds = 10.0;
          }
          {
            action = "reboot";
            shortcut = "3";
            countdown_seconds = 10.0;
          }
          {
            action = "logout";
            shortcut = "5";
            countdown_seconds = 10.0;
          }
          {
            action = "shutdown";
            shortcut = "6";
            variant = "destructive";
            countdown_seconds = 10.0;
          }
        ];
      };
    };

    # Aegis Lock - standalone Wayland lockscreen (replaces Noctalia's built-in lock)
    # Uses WlSessionLock protocol, supports PAM + fingerprint, syncs MD3 colors with Noctalia
    programs.aegis-lock = {
      enable = true;
      # Suspected: the threaded render loop stalls tearing down a lock surface
      # whose output appeared mid-unlock (dock + lid open), leaving
      # unlock_and_destroy unflushed and the session stuck locked. The basic
      # loop has no render thread to wait on. aegis-lock-recover keeps a
      # coredump of any client it aborts; drop this if one shows otherwise.
      package = inputs.aegis-lock.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
        preFixup =
          old.preFixup
          + ''
            qtWrapperArgs+=(--set QSG_RENDER_LOOP basic)
          '';
      });
      fingerprint.enable = true;
      settings = {
        general = {
          clockFormat = "HH:mm";
          dateFormat = "dddd, MMMM d";
          showSessionButtons = true;
          countdownEnabled = true;
          countdownDuration = 10000;
        };
      };
    };
  };
}
