# Noctalia Shell - minimal desktop shell for Wayland
# Replaces: waybar, swaync, nwg-dock, wlogout
# Keeps: vicinae (launcher), hyprlock, theme-toggle system
#
# Theme switching: Noctalia is the source of truth for dark/light mode.
# When toggled (via keybind or GUI), Noctalia triggers theme-toggle via hook.
#
# NOTE: This module is only imported when desktop.mode == "hyprland"
# (see home/desktop/default.nix), so no runtime check needed here.
{
  inputs,
  pkgs,
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
in {
  imports = [
    inputs.noctalia.homeModules.default
    # Noctalia bundles Catppuccin, so we don't need custom colorscheme files
    # ./colorscheme.nix
    # ./terminal-themes.nix
  ];

  config = {
    # Add helper script to PATH
    home.packages = [noctalia-ipc];

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
            # Left side: clock, system monitor, active window
            left = [
              {id = "Clock";}
              {id = "SystemMonitor";}
              {id = "ActiveWindow";}
              {id = "MediaMini";}
            ];
            # Right side: rarely used -> frequent -> critical -> hub
            right = [
              {id = "ScreenRecorder";} # Rarely used
              {id = "Tray";} # Background apps
              {id = "DarkMode";} # Occasional toggle
              {id = "NotificationHistory";} # Check unread
              {id = "Brightness";} # Hardware control
              {id = "Volume";} # Frequent hardware control
              {
                id = "KeyboardLayout";
                displayMode = "forceOpen"; # Always show current layout
              }
              {id = "Battery";} # Critical status
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

        # Hooks - trigger theme-toggle when dark mode changes
        # Noctalia calls the hook with "true" or "false" as argument
        hooks = {
          enabled = true;
          # Convert Noctalia's boolean to theme-toggle's dark/light
          darkModeChange = "theme-toggle apply $([ \"$1\" = \"true\" ] && echo dark || echo light)";
        };
      };
    };
  };
}
