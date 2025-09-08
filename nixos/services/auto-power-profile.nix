{
  config,
  lib,
  pkgs,
  ...
}: let
  isLaptop = config.machine.type == "laptop";

  # Simplified script that only responds to AC state changes
  powerProfileScript = pkgs.writeShellScript "auto-power-profile" ''
    #!/bin/bash

    LAST_AC_STATE_FILE="/tmp/power-profile-last-ac-state"

    # Function to log actions
    log_action() {
      echo "$(date): $1" | ${pkgs.systemd}/bin/systemd-cat -t auto-power-profile
    }

    # Get current AC state
    current_ac_state=$(cat /sys/class/power_supply/AC/online)

    # Get last handled AC state
    if [ -f "$LAST_AC_STATE_FILE" ]; then
      last_ac_state=$(cat "$LAST_AC_STATE_FILE")
    else
      last_ac_state=""
    fi

    # Only take action if AC state has changed (or this is first run)
    if [ "$current_ac_state" != "$last_ac_state" ]; then
      battery_level=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 100)

      # Determine target profile based on new AC state
      if [ "$current_ac_state" = "1" ]; then
        target_profile="performance"
        reason="AC connected"
      else
        if [ "$battery_level" -le 20 ]; then
          target_profile="power-saver"
          reason="AC disconnected, low battery ($battery_level%)"
        else
          target_profile="balanced"
          reason="AC disconnected, battery at $battery_level%"
        fi
      fi

      # Set the profile
      current_profile=$(${pkgs.power-profiles-daemon}/bin/powerprofilesctl get)
      if [ "$current_profile" != "$target_profile" ]; then
        log_action "AC state changed ($last_ac_state -> $current_ac_state): switching to $target_profile ($reason)"
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$target_profile"
      else
        log_action "AC state changed ($last_ac_state -> $current_ac_state): profile already set to $target_profile"
      fi

      # Update the last handled AC state
      echo "$current_ac_state" > "$LAST_AC_STATE_FILE"
    else
      # AC state hasn't changed, preserve any manual changes
      log_action "AC state unchanged ($current_ac_state), preserving current profile"
    fi
  '';
in {
  config = lib.mkIf isLaptop {
    # Enable power-profiles-daemon for profile management
    services.power-profiles-daemon.enable = true;

    # Udev rules to automatically switch power profiles
    services.udev.extraRules = ''
      # AC adapter plugged in - switch to performance
      SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="1", RUN+="${powerProfileScript}"

      # AC adapter unplugged - switch based on battery level
      SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="0", RUN+="${powerProfileScript}"

      # Battery level changes - adjust profile if on battery
      SUBSYSTEM=="power_supply", KERNEL=="BAT0", ATTR{status}=="Discharging", RUN+="${powerProfileScript}"
    '';

    # Systemd service for periodic power profile checking
    systemd.services.auto-power-profile = {
      description = "Automatic Power Profile Switching";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${powerProfileScript}";
      };
    };

    # Systemd timer for periodic battery monitoring
    systemd.timers.auto-power-profile = {
      description = "Periodic Power Profile Check";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "2min"; # Start 2 minutes after boot
        OnUnitActiveSec = "2min"; # Check every 2 minutes
      };
    };

    # Optional: Set battery charge thresholds via kernel parameters (ThinkPad specific)
    # This is a cleaner way to handle battery care without TLP
    boot.extraModprobeConfig = ''
      options thinkpad_acpi charge_start_thresh=75 charge_stop_thresh=85
    '';
  };
}
