{
  pkgs,
  lib,
  ...
}: {
  # libinput-gestures systemd service
  systemd.user.services.libinput-gestures = {
    Unit = {
      Description = "Libinput Gestures - Advanced touchpad gesture daemon";
      Documentation = "https://github.com/bulletmark/libinput-gestures";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };

    Service = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.libinput-gestures} -d";
      Restart = "on-failure";
      RestartSec = "1s";
      # Prevent shutdown hang
      TimeoutStopSec = "3s";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };

  # libinput-gestures configuration file
  xdg.configFile."libinput-gestures.conf".text = ''
    # Libinput-gestures configuration for Hyprland
    # Format: gesture GESTURE COMMAND

    # === 4-FINGER GESTURES ===
    # Application launcher
    gesture swipe up 4 hyprctl dispatch exec "vicinae vicinae://toggle"

    # Show all windows (hyprexpo overview) - disabled: hyprexpo plugin not loaded
    # gesture swipe down 4 hyprctl dispatch hyprexpo:expo toggle

    # Move window to adjacent non-empty workspace (r = relative, skips empty)
    gesture swipe left 4 hyprctl dispatch movetoworkspace r-1
    gesture swipe right 4 hyprctl dispatch movetoworkspace r+1

    # === PINCH GESTURES ===
    # Optional: Window opacity control with pinch
    # Uncomment if you want this feature
    # gesture pinch in 2 hyprctl dispatch exec "hyprctl setprop active alpha 0.8"
    # gesture pinch out 2 hyprctl dispatch exec "hyprctl setprop active alpha 1.0"

    # === GESTURE SENSITIVITY ===
    # Adjust these if gestures are too sensitive or not sensitive enough
    # Default is 0, increase for less sensitive, decrease for more sensitive
    # gesture_threshold 0
  '';
}
