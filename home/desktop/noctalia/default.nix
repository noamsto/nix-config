# Noctalia Shell - minimal desktop shell for Wayland
# Replaces: waybar, swaync, nwg-dock, wlogout
# Keeps: vicinae (launcher), hyprlock, theme-toggle system
#
# Theme switching: Noctalia is the source of truth for dark/light mode.
# When toggled (via keybind or GUI), Noctalia triggers theme-toggle via hook.
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

  # Fetch Noctalia plugins from official repo
  noctalia-plugins = pkgs.fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "noctalia-plugins";
    rev = "main";
    sha256 = "sha256-wmWUjG9jQS0eygjWUKnKsTqMTXC6iYEqmz08OhvW1Yg=";
  };

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
          value = {source = "${noctalia-plugins}/${plugin}";};
        })
        enabledPlugins))
    ];

    programs.noctalia-shell = {
      enable = true;

      # Use systemd for auto-start
      systemd.enable = true;

      settings = {
        # Use predefined Catppuccin colorscheme (plural key!)
        colorSchemes = {
          useWallpaperColors = false;
          predefinedScheme = "Catppuccin";
          darkMode = true;
        };

        # Bar configuration - top position like current waybar
        bar = {
          position = "top";
          floating = false;
          widgets = {
            # Left side: clock, system monitor, network, active window
            left = [
              {id = "plugin:catwalk";} # 🐱
              {id = "Clock";}
              {id = "SystemMonitor";}
              # Network indicator removed due to contrast issues
              {id = "ActiveWindow";}
              {id = "MediaMini";}
            ];
            # Right side: rarely used -> frequent -> critical -> hub
            right = [
              {id = "ScreenRecorder";} # Rarely used
              {id = "plugin:privacy-indicator";} # Mic/camera/screen sharing
              {id = "Tray";} # Background apps
              {id = "DarkMode";} # Occasional toggle
              {id = "NotificationHistory";} # Check unread
              {id = "Brightness";} # Hardware control
              {id = "Volume";} # Frequent hardware control
              {
                id = "KeyboardLayout";
                displayMode = "forceOpen"; # Always show current layout
              }
              {
                id = "Battery";
                showPowerProfiles = true;
              } # Critical status
              {id = "ControlCenter";} # Settings hub at edge
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
        };

        # UI fonts
        ui = {
          fontDefault = "Inter Nerd Font";
          fontFixed = "FiraCode Nerd Font";
        };

        # Brightness - enable DDC/CI for external monitors
        brightness = {
          enableDdcSupport = true;
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
