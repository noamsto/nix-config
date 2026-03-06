{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config.machine) isLaptop;

  # Battery threshold management script
  batteryThresholdScript = pkgs.writeShellScript "battery-threshold-setup" ''
    #!/usr/bin/env bash

    # Battery Threshold Management for ThinkPads
    # Sets charge start/stop thresholds directly via kernel interfaces

    set -euo pipefail

    # Configuration
    START_THRESHOLD=75
    STOP_THRESHOLD=80

    # Function to set battery thresholds
    set_battery_thresholds() {
      local battery="$1"
      local start_threshold="$2"
      local stop_threshold="$3"

      echo "Setting battery thresholds for $battery: start=$start_threshold%, stop=$stop_threshold%"

      # Try different paths for ThinkPad battery threshold control
      local threshold_paths=(
        "/sys/class/power_supply/$battery/charge_control_start_threshold"
        "/sys/class/power_supply/$battery/charge_control_end_threshold"
        "/sys/devices/platform/smapi/$battery/start_charge_thresh"
        "/sys/devices/platform/smapi/$battery/stop_charge_thresh"
      )

      # Set start threshold
      for start_path in "/sys/class/power_supply/$battery/charge_control_start_threshold" \
                        "/sys/devices/platform/smapi/$battery/start_charge_thresh"; do
        if [[ -w "$start_path" ]]; then
          echo "$start_threshold" > "$start_path" && \
            echo "✓ Set start threshold via $start_path" || \
            echo "✗ Failed to set start threshold via $start_path"
          break
        fi
      done

      # Set stop threshold
      for stop_path in "/sys/class/power_supply/$battery/charge_control_end_threshold" \
                       "/sys/devices/platform/smapi/$battery/stop_charge_thresh"; do
        if [[ -w "$stop_path" ]]; then
          echo "$stop_threshold" > "$stop_path" && \
            echo "✓ Set stop threshold via $stop_path" || \
            echo "✗ Failed to set stop threshold via $stop_path"
          break
        fi
      done
    }

    # Function to check current thresholds
    check_battery_thresholds() {
      echo "=== Battery Charge Thresholds ==="

      for battery in BAT0 BAT1; do
        if [[ -d "/sys/class/power_supply/$battery" ]]; then
          echo "Battery: $battery"

          # Check start threshold
          for start_path in "/sys/class/power_supply/$battery/charge_control_start_threshold" \
                            "/sys/devices/platform/smapi/$battery/start_charge_thresh"; do
            if [[ -r "$start_path" ]]; then
              local start_val
              start_val=$(cat "$start_path" 2>/dev/null || echo "unknown")
              echo "  Start threshold: $start_val% (via $start_path)"
              break
            fi
          done

          # Check stop threshold
          for stop_path in "/sys/class/power_supply/$battery/charge_control_end_threshold" \
                           "/sys/devices/platform/smapi/$battery/stop_charge_thresh"; do
            if [[ -r "$stop_path" ]]; then
              local stop_val
              stop_val=$(cat "$stop_path" 2>/dev/null || echo "unknown")
              echo "  Stop threshold: $stop_val% (via $stop_path)"
              break
            fi
          done
          echo ""
        fi
      done
    }

    # Main execution
    case "''${1:-setup}" in
      "setup"|"set")
        echo "Setting up battery thresholds..."
        for battery in BAT0 BAT1; do
          if [[ -d "/sys/class/power_supply/$battery" ]]; then
            set_battery_thresholds "$battery" "$START_THRESHOLD" "$STOP_THRESHOLD"
          fi
        done
        check_battery_thresholds
        ;;
      "check"|"status")
        check_battery_thresholds
        ;;
      *)
        echo "Usage: $0 [setup|check]"
        echo "  setup - Set battery charge thresholds (75-80%)"
        echo "  check - Display current thresholds"
        exit 1
        ;;
    esac
  '';
in {
  config = lib.mkIf isLaptop {
    # Enable ThinkPad-specific modules for battery threshold control
    boot.kernelModules = [
      "thinkpad_acpi" # ThinkPad ACPI support
      "tp_smapi" # ThinkPad SMAPI support (if available)
    ];

    # Extra kernel parameters for ThinkPad battery management
    boot.kernelParams = [
      "thinkpad_acpi.battery_control=1" # Enable battery control
    ];

    # Create systemd service to set battery thresholds at boot
    systemd.services.battery-threshold = {
      description = "Set ThinkPad Battery Charge Thresholds";
      documentation = ["Battery charge thresholds for longevity (75-80%)"];

      wantedBy = ["multi-user.target"];
      after = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${batteryThresholdScript} setup";
        RemainAfterExit = true;

        # Security settings
        User = "root"; # Required for writing to sysfs
        CapabilityBoundingSet = "";
        NoNewPrivileges = true;

        # Filesystem access
        ReadWritePaths = [
          "/sys/class/power_supply"
          "/sys/devices/platform/smapi"
        ];
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = false; # Need access to power supply devices
        PrivateNetwork = true;

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "battery-threshold";
      };
    };

    # Make the script available for manual use
    environment.systemPackages = with pkgs; [
      (writeScriptBin "battery-threshold" batteryThresholdScript)

      # Add useful battery monitoring tools
      acpi
      powertop
    ];

    # Udev rules for battery threshold persistence (optional)
    services.udev.extraRules = ''
      # ThinkPad battery threshold persistence
      # Automatically set thresholds when battery is detected
      SUBSYSTEM=="power_supply", KERNEL=="BAT*", ACTION=="add", RUN+="${batteryThresholdScript} setup"
    '';
  };
}
