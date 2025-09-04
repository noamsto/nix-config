{
  config,
  lib,
  pkgs,
  ...
}: let
  isLaptop = config.machine.type == "laptop";

  # Simple script to switch power profiles based on AC adapter status
  powerProfileScript = pkgs.writeShellScript "auto-power-profile" ''
    #!/bin/bash

    # Check if AC adapter is connected
    if [ "$(cat /sys/class/power_supply/AC/online)" = "1" ]; then
      # AC connected - use performance mode
      ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance
    else
      # On battery - check battery level for smart switching
      battery_level=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null || echo 100)

      if [ "$battery_level" -le 20 ]; then
        # Low battery - use power-saver
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver
      else
        # Normal battery - use balanced
        ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set balanced
      fi
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
