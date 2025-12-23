{
  pkgs,
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";
in {
  config = lib.mkIf isLaptop {
    # Suppress spurious wakes from AC plug/unplug events
    # With acpi.ec_no_wakeup removed (to allow dock wake), AC events can wake the laptop
    # This service detects if wake was from docking (external monitors) or just AC
    # If no dock detected and lid is closed, immediately re-suspend
    systemd.services.suppress-ac-wake = {
      description = "Re-suspend if woken by AC plug event (not dock)";
      after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "suppress-ac-wake" ''
          # Wait for hardware to stabilize after wake
          sleep 3

          # Check if any external DisplayPort monitors are connected (indicates dock)
          for status_file in /sys/class/drm/card*-DP-*/status /sys/class/drm/card*-HDMI-*/status; do
            if [ -f "$status_file" ] && [ "$(cat "$status_file" 2>/dev/null)" = "connected" ]; then
              # External monitor connected - dock is attached, stay awake
              ${pkgs.systemd}/bin/logger -t suppress-ac-wake "External monitor detected - staying awake"
              exit 0
            fi
          done

          # Check USB4/Thunderbolt for connected devices (dock attached but monitors not yet detected)
          if ${pkgs.coreutils}/bin/ls /sys/bus/thunderbolt/devices/*/device 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q .; then
            ${pkgs.systemd}/bin/logger -t suppress-ac-wake "Thunderbolt device detected - staying awake"
            exit 0
          fi

          # No dock detected - check if this is a spurious wake (lid closed = user not active)
          if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
            ${pkgs.systemd}/bin/logger -t suppress-ac-wake "Spurious wake (no dock, lid closed) - re-suspending in 2s"
            sleep 2
            # Double-check lid is still closed before suspending
            if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
              ${pkgs.systemd}/bin/systemctl suspend
            fi
          else
            ${pkgs.systemd}/bin/logger -t suppress-ac-wake "Lid is open - staying awake"
          fi
        '';
      };
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };

    # Restart hyprdynamicmonitors after resume to fix phantom monitor detection
    # When laptop is undocked while asleep, Hyprland keeps phantom monitors
    # Restarting HDM forces fresh monitor detection
    systemd.services.hyprdynamicmonitors-resume = {
      description = "Clear phantom monitors and restart hyprdynamicmonitors after system resume";
      after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
      serviceConfig = {
        Type = "oneshot";
        # Clear phantom monitors by checking DRM status and disabling disconnected ones in Hyprland
        ExecStart = pkgs.writeShellScript "hdm-resume" ''
          export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ 2>/dev/null | head -1)

          # Disable monitors that DRM reports as disconnected (these are phantoms in Hyprland)
          for status_file in /sys/class/drm/card*/status; do
            if [ -f "$status_file" ]; then
              connector=$(basename $(dirname "$status_file"))
              connector_name=''${connector#card?-}
              status=$(cat "$status_file")

              # If DRM says disconnected, disable in Hyprland to clear phantom
              if [ "$status" = "disconnected" ] && [ "$connector_name" != "Writeback-1" ]; then
                ${pkgs.hyprland}/bin/hyprctl keyword monitor "$connector_name,disable" 2>/dev/null || true
              fi
            fi
          done

          sleep 1

          # Now restart HDM to re-detect actual monitors
          ${pkgs.systemd}/bin/systemctl --user --machine=${config.username}@.host restart hyprdynamicmonitors.service
        '';
      };
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
  };
}
