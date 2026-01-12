# Noctalia Shell - minimal desktop shell for Wayland
# Replaces: waybar, swaync, nwg-dock, wlogout, hyprlock
# Keeps: vicinae (launcher), theme-toggle system
#
# Theme switching: Noctalia is the source of truth for dark/light mode.
# When toggled (via keybind or GUI), Noctalia triggers theme-toggle via hook.
#
# Screen recording: ScreenRecorder widget saves to ~/Videos. The recording-post-processor
# service watches for new recordings and offers GIF conversion via vicinae dmenu.
#
# TODO: Dock icons missing for flatpak apps and NixOS-wrapped binaries
#   - Issue: Window class doesn't match icon name (e.g., "BambuStudio" vs "com.bambulab.BambuStudio")
#   - Tracking: https://github.com/noctalia-dev/noctalia-shell/issues/1172
#   - Fix: Noctalia needs to use heuristicLookup instead of exact byId matching
#   - Workaround if needed: Create icon symlinks in xdg.dataFile
#
# NOTE: This module is only imported when desktop.mode == "hyprland"
# (see home/desktop/default.nix), so no runtime check needed here.
{
  inputs,
  pkgs,
  lib,
  ...
}: let
  # Helper script for Noctalia IPC commands (qs may not be in PATH)
  noctalia-ipc = pkgs.writeShellScriptBin "noctalia-ipc" ''
    pid=$(${pkgs.procps}/bin/pgrep -f 'quickshell.*noctalia-shell' | head -1)
    if [ -n "$pid" ]; then
      ${pkgs.quickshell}/bin/qs ipc --pid "$pid" call "$@"
    else
      echo "Noctalia not running" >&2
      exit 1
    fi
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

  # Noctalia plugins from flake input (update with: nix flake update noctalia-plugins)
  inherit (inputs) noctalia-plugins;

  # Plugins to enable
  enabledPlugins = [
    "privacy-indicator"
    # "network-indicator" # Removed due to contrast issues
    "mini-docker"
    "catwalk"
  ];

  # Generate plugins.json with enabled states
  pluginsJson = builtins.toJSON {
    version = 1;
    sources = [
      {
        enabled = true;
        name = "Official Noctalia Plugins";
        url = "https://github.com/noctalia-dev/noctalia-plugins";
      }
    ];
    states = lib.genAttrs enabledPlugins (_: {enabled = true;});
  };
in {
  imports = [
    inputs.noctalia.homeModules.default
    # Noctalia bundles Catppuccin, so we don't need custom colorscheme files
    # ./colorscheme.nix
    # ./terminal-themes.nix
  ];

  config = {
    # Add helper scripts to PATH
    home.packages = [noctalia-ipc restore-wallpaper];

    # Profile picture for Noctalia (symlinked to ~/.face)
    home.file.".face".source = ./assets/avatar.png;

    # Add icon theme environment to Noctalia service for proper icon lookup
    systemd.user.services.noctalia-shell.Service.Environment = lib.mkForce [
      "NOCTALIA_SETTINGS_FALLBACK=%h/.config/noctalia/gui-settings.json"
      "QS_ICON_THEME=Papirus-Dark"
    ];

    # Systemd service to restore wallpaper after Noctalia starts
    systemd.user.services.noctalia-restore-wallpaper = {
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

    # Install plugins via xdg.configFile
    xdg.configFile = lib.mkMerge [
      # plugins.json with enabled states (force to overwrite existing)
      {
        "noctalia/plugins.json" = {
          text = pluginsJson;
          force = true;
        };
      }
      # Copy each enabled plugin directory
      (lib.listToAttrs (map (plugin: {
          name = "noctalia/plugins/${plugin}";
          value = {
            source = "${noctalia-plugins}/${plugin}";
            # Use recursive for privacy-indicator so we can add settings.json
            recursive = plugin == "privacy-indicator";
          };
        })
        enabledPlugins))
      # Plugin settings (privacy-indicator)
      {
        "noctalia/plugins/privacy-indicator/settings.json".text = builtins.toJSON {
          hideInactive = false;
          removeMargins = false;
        };
      }
    ];

    programs.noctalia-shell = {
      enable = true;

      # Use systemd for auto-start
      systemd.enable = true;

      settings = {
        # Use predefined Monochrome colorscheme (plural key!)
        colorSchemes = {
          useWallpaperColors = false;
          predefinedScheme = "Monochrome";
          darkMode = true;
        };

        # Bar configuration - top position like current waybar
        bar = {
          position = "top";
          floating = false;
          density = "comfortable";
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
              }
            ];
            # Right side: rarely used -> frequent -> critical -> hub
            right = [
              {id = "ScreenRecorder";}
              {id = "plugin:privacy-indicator";}
              {id = "Tray";}
              {id = "DarkMode";}
              {
                id = "NotificationHistory";
                showUnreadBadge = true;
              }
              {
                id = "Network";
                displayMode = "onhover";
              }
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

        # Disable Noctalia's launcher - keep Vicinae
        # But set terminal for any launcher usage
        appLauncher = {
          enable = false;
          terminalCommand = "kitty -e";
        };

        # Wallpaper settings
        wallpaper = {
          enabled = true;
          directory = "/home/noams/Pictures/Wallpapers";
          fillMode = "crop";
          setWallpaperOnAllMonitors = true;
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
  };
}
