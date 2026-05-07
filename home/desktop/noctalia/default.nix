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
  # Wrap the upstream noctalia-shell to add calendar support at runtime
  # instead of using .override { calendarSupport = true; }. The override
  # would fork the derivation hash and miss noctalia.cachix.org; the
  # wrapper keeps the upstream hash intact so the cache is hit.
  upstreamNoctalia = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  calendarTypelibPath = lib.makeSearchPath "lib/girepository-1.0" (with pkgs; [
    evolution-data-server
    libical
    glib.out
    libsoup_3
    json-glib
    gobject-introspection
  ]);
  calendarBinPath = lib.makeBinPath [
    (pkgs.python3.withPackages (pp: [pp.pygobject3]))
  ];
  noctaliaPackage = pkgs.symlinkJoin {
    name = "noctalia-shell-with-calendar";
    paths = [upstreamNoctalia];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      rm $out/bin/noctalia-shell
      makeWrapper ${upstreamNoctalia}/bin/noctalia-shell $out/bin/noctalia-shell \
        --prefix PATH : ${calendarBinPath} \
        --prefix GI_TYPELIB_PATH : ${calendarTypelibPath}
    '';
    inherit (upstreamNoctalia) meta;
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
      # Bound to graphical-session.target since noctalia-shell.service no longer exists;
      # the helper script pgrep-waits for noctalia internally.
      noctalia-restore-wallpaper = {
        Unit = {
          Description = "Restore Noctalia wallpaper from saved state";
          After = ["graphical-session.target"];
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

      # Systemd service to monitor Noctalia shell and log crashes
      noctalia-crash-monitor = {
        Unit = {
          Description = "Monitor Noctalia for crashes and log events";
          After = ["graphical-session.target"];
          PartOf = ["graphical-session.target"];
        };
        Service = {
          Type = "simple";
          ExecStart = pkgs.writeShellScript "noctalia-crash-monitor" ''
            LOG="/tmp/noctalia-shell.log"
            log() {
              echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [crash-monitor] $*" | tee -a "$LOG"
            }

            # Crash-loop guard: cap restarts per rolling window to avoid busy spawning
            # if noctalia segfaults immediately (e.g. broken plugin).
            # Upstream open issue #1323 (settings reset on systemd restart) is why we
            # relaunch via `hyprctl dispatch exec` rather than a systemd unit.
            RESTART_COUNT=0
            WINDOW_START=$(date +%s)
            MAX_RESTARTS=5
            WINDOW_SECONDS=60

            # Use `noctalia-shell list` for detection: upstream renamed the binary to
            # noctalia-qs, so its argv is just "quickshell" with no recognizable suffix
            # — pgrep regexes can't distinguish it from a hypridle/other quickshell.
            # `list` walks /run/user/$UID/quickshell/ and reports the actual instance.
            get_noctalia_pid() {
              ${noctaliaPackage}/bin/noctalia-shell list 2>/dev/null \
                | ${pkgs.gawk}/bin/awk '/Process ID:/ {print $3; exit}'
            }

            relaunch_noctalia() {
              ${pkgs.hyprland}/bin/hyprctl dispatch exec noctalia-shell >/dev/null 2>&1 \
                || log "hyprctl dispatch exec noctalia-shell failed"
            }

            log "Crash monitor started"

            # No self-heal on startup. After `nh os switch`, the new binary's
            # `noctalia-shell list` filters by its own shell.qml path and can't
            # see old-generation instances, so a self-heal here would launch a
            # duplicate while the old bar is still painting. Crashes during
            # this session are still handled by the monitor loop below.

            # Wait for Noctalia to appear
            NOCTALIA_PID=""
            while [ -z "$NOCTALIA_PID" ]; do
              sleep 0.5
              NOCTALIA_PID=$(get_noctalia_pid)
            done
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

                # Crash-loop protection: roll the window every WINDOW_SECONDS
                NOW=$(date +%s)
                if [ $((NOW - WINDOW_START)) -ge "$WINDOW_SECONDS" ]; then
                  WINDOW_START=$NOW
                  RESTART_COUNT=0
                fi
                RESTART_COUNT=$((RESTART_COUNT + 1))
                if [ "$RESTART_COUNT" -gt "$MAX_RESTARTS" ]; then
                  log "Crash loop: $RESTART_COUNT restarts within $WINDOW_SECONDS s — giving up (systemd will retry)"
                  exit 1
                fi

                log "Relaunching noctalia-shell (attempt #$RESTART_COUNT in window)"
                relaunch_noctalia

                # Wait up to 30s for new instance to register in /run/user/$UID/quickshell.
                # Startup can be slow on the first run after boot when QML is JITed.
                NEW_PID=""
                for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
                  sleep 0.5
                  NEW_PID=$(get_noctalia_pid)
                  [ -n "$NEW_PID" ] && break
                done

                if [ -n "$NEW_PID" ]; then
                  log "Noctalia restarted (new PID: $NEW_PID)"
                  NOCTALIA_PID="$NEW_PID"
                else
                  log "Failed to relaunch noctalia after 30s — monitor exiting"
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
          WantedBy = ["graphical-session.target"];
        };
      };
    }; # systemd.user.services

    programs.noctalia-shell = {
      enable = true;
      package = noctaliaPackage;

      # Auto-start via Hyprland exec-once (upstream deprecated systemd integration:
      # https://docs.noctalia.dev/getting-started/nixos/#running-the-shell)
      systemd.enable = false;

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
              # Disabled — flaky behavior, revisit later (plugin still installed via enabledPlugins)
              # {id = "plugin:valent-connect";}
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

        # ControlCenter cards + quick-action shortcuts.
        # Mirrors Noctalia's runtime defaults so this attrset is the full
        # source of truth; cards we don't list here would be wiped by Nix.
        controlCenter = {
          cards = [
            {
              id = "profile-card";
              enabled = true;
            }
            {
              id = "shortcuts-card";
              enabled = true;
            }
            {
              id = "audio-card";
              enabled = true;
            }
            {
              id = "brightness-card";
              enabled = false;
            }
            {
              id = "weather-card";
              enabled = true;
            }
            {
              id = "media-sysmon-card";
              enabled = true;
            }
          ];
          diskPath = "/";
          position = "close_to_bar_button";
          shortcuts = {
            left = [
              {id = "Network";}
              {id = "Bluetooth";}
              {id = "WallpaperSelector";}
              {id = "NoctaliaPerformance";}
            ];
            right = [
              {id = "Notifications";}
              {id = "PowerProfile";}
              # keep-awake-plus supersedes the built-in KeepAwake (richer scope/duration UI)
              {id = "plugin:${pluginComposite "keep-awake-plus" ownPluginSource}";}
              {id = "NightLight";}
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
