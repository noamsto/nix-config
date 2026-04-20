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
  osConfig,
  pkgs,
  lib,
  ...
}: let
  noctaliaPackage = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    calendarSupport = true;
  };

  # Helper script for Noctalia IPC commands
  # Quickshell's IPC auto-discovers the running instance via /run/user/$UID/quickshell/
  noctalia-ipc = pkgs.writeShellScriptBin "noctalia-ipc" ''
    exec ${noctaliaPackage}/bin/noctalia-shell ipc call "$@"
  '';

  # Script to restore wallpaper from saved state
  restore-wallpaper = pkgs.writeShellScriptBin "noctalia-restore-wallpaper" ''
    LAST_WP="$HOME/.config/noctalia/last-wallpaper"
    if [ -f "$LAST_WP" ]; then
      WP_PATH=$(cat "$LAST_WP")
      if [ -f "$WP_PATH" ]; then
        # Wait for Noctalia to be ready
        sleep 2
        ${noctalia-ipc}/bin/noctalia-ipc wallpaper set "$WP_PATH" ""
        echo "Restored wallpaper: $WP_PATH"
      fi
    fi
  '';

  pluginSource = "https://github.com/noctalia-dev/noctalia-plugins";
  ownPluginSource = "https://github.com/noamsto/noctalia-plugin-keep-awake";

  # Noctalia keys 3rd-party plugin state as "<6-char-sha256-of-url>:<id>"
  # (see PluginRegistry.generateCompositeKey). Official plugins get the
  # plain id. Mirror that here so Home-Manager-generated plugins.json
  # matches what Noctalia writes at install time — otherwise every
  # restart re-triggers an install and the widget gets wiped.
  pluginComposite = name: sourceUrl:
    if sourceUrl == pluginSource
    then name
    else "${builtins.substring 0 6 (builtins.hashString "sha256" sourceUrl)}:${name}";

  pluginSourceFor = name:
    if name == "keep-awake-plus"
    then ownPluginSource
    else pluginSource;

  # Terminal for transient windows (SSH, ping, app launcher)
  # foot --  : lightweight, opens, runs command, closes when done
  # kitty -e : feature-rich but heavier
  transientTerminal = "foot --";

  # Plugins to enable (Noctalia auto-installs from source URL on startup)
  enabledPlugins = [
    # "privacy-indicator" # Removed: webcam detection script burns 450% CPU scanning /proc/*/fd
    # "network-indicator" # Removed due to contrast issues
    "mini-docker"
    "weekly-calendar"
    "catwalk"
    "screen-recorder"
    "tailscale"
    "valent-connect"
    "keep-awake-plus"
  ];
in {
  imports = [
    inputs.noctalia.homeModules.default
    inputs.aegis-lock.homeModules.default
  ];

  config = {
    # Add helper scripts to PATH
    # gpu-screen-recorder is required by the screen-recorder plugin
    # gnome-calendar is used to add Google Calendar accounts to evolution-data-server
    # glib.bin provides gdbus, required by valent-connect plugin for D-Bus queries
    home.packages = [noctalia-ipc restore-wallpaper pkgs.gpu-screen-recorder pkgs.gnome-calendar pkgs.gnome-control-center pkgs.glib.bin];

    # Profile picture for Noctalia (symlinked to ~/.face)
    home.file.".face".source = ./assets/avatar.png;

    systemd.user.services = {
      # Add icon theme environment to Noctalia service for proper icon lookup
      noctalia-shell.Service.Environment = lib.mkForce [
        "QS_ICON_THEME=${config.gtk.iconTheme.name}"
      ];

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
      noctalia-restore-wallpaper = {
        Unit = {
          Description = "Restore Noctalia wallpaper from saved state";
          After = ["noctalia-shell.service"];
          PartOf = ["noctalia-shell.service"];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${restore-wallpaper}/bin/noctalia-restore-wallpaper";
        };
        Install = {
          WantedBy = ["noctalia-shell.service"];
        };
      };

      # Systemd service to monitor Noctalia shell and log crashes
      noctalia-crash-monitor = {
        Unit = {
          Description = "Monitor Noctalia for crashes and log events";
          After = ["noctalia-shell.service"];
          PartOf = ["noctalia-shell.service"];
        };
        Service = {
          Type = "simple";
          ExecStart = pkgs.writeShellScript "noctalia-crash-monitor" ''
            LOG="/tmp/noctalia-shell.log"
            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [crash-monitor] $*" | tee -a "$LOG"
            }

            log "Crash monitor started"

            # Wait for Noctalia to start
            while ! ${pkgs.procps}/bin/pgrep -f 'quickshell.*noctalia-shell' >/dev/null 2>&1; do
              sleep 0.5
            done

            NOCTALIA_PID=$(${pkgs.procps}/bin/pgrep -f 'quickshell.*noctalia-shell' | head -1)
            log "Monitoring Noctalia (PID: $NOCTALIA_PID)"

            # Monitor the process
            while true; do
              if ! ${pkgs.procps}/bin/kill -0 "$NOCTALIA_PID" 2>/dev/null; then
                log "!!! NOCTALIA DIED (was PID: $NOCTALIA_PID) !!!"

                # Log system state at time of crash
                log "Monitor state at crash:"
                ${pkgs.hyprland}/bin/hyprctl monitors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[] | "  \(.name): \(.width)x\(.height) disabled=\(.disabled)"' >> "$LOG" 2>&1 || log "  (failed to get monitors)"

                # Check if lid is closed
                if ${pkgs.glib}/bin/gdbus call --system \
                    --dest org.freedesktop.UPower \
                    --object-path /org/freedesktop/UPower \
                    --method org.freedesktop.DBus.Properties.Get \
                    org.freedesktop.UPower LidIsClosed 2>/dev/null | grep -q "true"; then
                  log "Lid state: CLOSED"
                else
                  log "Lid state: OPEN"
                fi

                # Check DRM connectors
                log "DRM connectors:"
                for status_file in /sys/class/drm/card*/status; do
                  if [ -f "$status_file" ]; then
                    connector=$(basename $(dirname "$status_file"))
                    connector_name=''${connector#card?-}
                    status=$(cat "$status_file")
                    log "  $connector_name: $status"
                  fi
                done

                # Wait for Noctalia to restart (if it does)
                sleep 2
                NEW_PID=$(${pkgs.procps}/bin/pgrep -f 'quickshell.*noctalia-shell' | head -1)
                if [ -n "$NEW_PID" ]; then
                  log "Noctalia restarted (new PID: $NEW_PID)"
                  NOCTALIA_PID="$NEW_PID"
                else
                  log "Noctalia has NOT restarted - monitor exiting"
                  exit 1
                fi
              fi
              sleep 1
            done
          '';
          Restart = "on-failure";
          RestartSec = "2s";
        };
        Install = {
          WantedBy = ["noctalia-shell.service"];
        };
      };
    }; # systemd.user.services

    programs.noctalia-shell = {
      enable = true;
      package = noctaliaPackage;

      # Use systemd for auto-start
      systemd.enable = true;

      # Plugin registry - Noctalia auto-installs enabled plugins from sourceUrl
      plugins = {
        version = 2;
        sources = [
          {
            enabled = true;
            name = "Official Noctalia Plugins";
            url = pluginSource;
          }
          {
            enabled = true;
            name = "Keep Awake+ (noamsto)";
            url = ownPluginSource;
          }
        ];
        states = lib.listToAttrs (map (name: let
            sourceUrl = pluginSourceFor name;
          in {
            name = pluginComposite name sourceUrl;
            value = {
              enabled = true;
              inherit sourceUrl;
            };
          })
          enabledPlugins);
      };

      # Per-plugin settings (only non-defaults)
      pluginSettings = {
        tailscale = {
          compactMode = true;
          terminalCommand = transientTerminal;
          defaultPeerAction = "ssh";
          sshUsername = "noams";
        };
      };

      settings = {
        # Auto-update plugins on startup
        plugins.autoUpdate = true;

        # Use predefined Catppuccin colorscheme (plural key!)
        colorSchemes = {
          useWallpaperColors = false;
          predefinedScheme = "Catppuccin";
          darkMode = true;
        };

        # Bar configuration - top position like current waybar
        bar = {
          position = "top";
          barType = "simple";
          density =
            if osConfig.hostname == "thinkpad-p14s-g5"
            then "spacious"
            else "comfortable";
          backgroundOpacity = 0.93;
          outerCorners = true;
          widgets = {
            # Left side: clock, system monitor, active window
            left = [
              {id = "plugin:catwalk";}
              {
                id = "Clock";
                formatHorizontal = "HH:mm";
              }
              {id = "plugin:weekly-calendar";}
              {
                id = "SystemMonitor";
                compactMode = true;
                showCpuUsage = true;
                showCpuTemp = true;
                showMemoryUsage = true;
                useMonospaceFont = true;
              }
              {
                id = "ActiveWindow";
                colorizeIcons = false;
                maxWidth = 145;
                hideMode = "hidden";
                scrollingMode = "hover";
              }
              {
                id = "MediaMini";
                showAlbumArt = true;
                showProgressRing = true;
                hideMode = "hidden";
                scrollingMode = "hover";
                maxWidth = 145;
              }
            ];
            # Center: workspace indicator
            center = [
              {
                id = "Workspace";
                labelMode = "index";
                showLabelsOnlyWhenOccupied = true;
                characterCount = 2;
                colorizeIcons = false;
                emptyColor = "secondary";
                enableScrollWheel = true;
                focusedColor = "primary";
                followFocusedScreen = false;
                fontWeight = "bold";
                groupedBorderOpacity = 1;
                hideUnoccupied = false;
                iconScale = 0.8;
                occupiedColor = "secondary";
                pillSize = 0.6;
                showApplications = true;
                showApplicationsHover = true;
                showBadge = true;
                unfocusedIconsOpacity = 1;
              }
            ];
            # Right side: rarely used -> frequent -> critical -> hub
            right = [
              {id = "Tray";}
              {id = "plugin:mini-docker";}
              {id = "plugin:screen-recorder";}
              {id = "plugin:tailscale";}
              {id = "plugin:privacy-indicator";}
              {id = "DarkMode";}
              {id = "plugin:${pluginComposite "keep-awake-plus" ownPluginSource}";}
              {
                id = "NotificationHistory";
                showUnreadBadge = true;
              }
              {
                id = "Network";
                displayMode = "onhover";
              }
              {id = "plugin:valent-connect";}
              {
                id = "Bluetooth";
                displayMode = "onhover";
              }
              {
                id = "Brightness";
                displayMode = "onhover";
              }
              {
                id = "Volume";
                displayMode = "onhover";
              }
              {
                id = "KeyboardLayout";
                displayMode = "forceOpen";
                showIcon = true;
              }
              {
                id = "Battery";
                displayMode = "onhover";
                showPowerProfiles = true;
              }
              {
                id = "ControlCenter";
                useDistroLogo = true;
              }
            ];
          };
        };

        # Location settings
        location = {
          name = "Tel Aviv";
        };

        # Notification settings - disable keyboard layout toast
        notifications = {
          enableKeyboardLayoutToast = false;
        };

        # Session menu - use aegis-lock for lock action
        sessionMenu = {
          powerOptions = [
            {
              action = "lock";
              enabled = true;
              command = "aegis-lock";
              keybind = "1";
            }
            {
              action = "suspend";
              enabled = true;
              keybind = "2";
            }
            {
              action = "hibernate";
              enabled = false;
            }
            {
              action = "reboot";
              enabled = true;
              keybind = "3";
            }
            {
              action = "rebootToUefi";
              enabled = true;
              keybind = "4";
            }
            {
              action = "logout";
              enabled = true;
              keybind = "5";
            }
            {
              action = "shutdown";
              enabled = true;
              keybind = "6";
            }
          ];
        };

        # General UI settings
        general = {
          animationSpeed = 1.0;
          lockOnSuspend = false; # Managed by hypridle's before_sleep_cmd
        };

        # UI fonts and panel settings
        ui = {
          fontDefault = "Inter Nerd Font";
          fontFixed = "FiraCode Nerd Font";
          panelBackgroundOpacity = 0.93;
          panelsAttachedToBar = true;
        };

        # Brightness - enable DDC/CI for external monitors
        brightness = {
          enableDdcSupport = true;
        };

        # Night light - auto blue light filter
        nightLight = {
          enabled = true;
          autoSchedule = true;
          dayTemp = "6500";
          nightTemp = "4000";
        };

        # System monitoring - enable GPU
        systemMonitor = {
          enableDgpuMonitoring = true;
        };

        # Launcher terminal command (Vicinae is the primary launcher)
        appLauncher = {
          terminalCommand = transientTerminal;
        };

        # Wallpaper settings
        wallpaper = {
          enabled = true;
          directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
          fillMode = "crop";
          setWallpaperOnAllMonitors = true;
          automationEnabled = true;
          randomIntervalSec = 1800;
          wallpaperChangeMode = "random";
        };

        # Hooks
        hooks = {
          enabled = true;
          # Save wallpaper path when changed
          wallpaperChange = "echo \"$1\" > ~/.config/noctalia/last-wallpaper";
          # Trigger theme-toggle when dark mode changes
          darkModeChange = "theme-toggle apply $([ \"$1\" = \"true\" ] && echo dark || echo light)";
        };
      };
    };

    # Aegis Lock - standalone Wayland lockscreen (replaces Noctalia's built-in lock)
    # Uses WlSessionLock protocol, supports PAM + fingerprint, syncs MD3 colors with Noctalia
    programs.aegis-lock = {
      enable = true;
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

    # Noctalia modifies settings.json at runtime (dark mode, wallpaper, etc.).
    # Force-overwrite so HM never tries to create a .bak — Nix config is source of truth.
    xdg.configFile."noctalia/settings.json".force = true;

    # Symlink aegis-lock colors.json to noctalia's runtime-generated colors.json
    # so the lockscreen uses the same MD3 color scheme as the shell
    xdg.configFile."aegis-lock/colors.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/noctalia/colors.json";
  };
}
