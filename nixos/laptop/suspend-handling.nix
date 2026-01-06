{
  pkgs,
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";
in {
  config = lib.mkIf isLaptop {
    # Note: Spurious AC-plug wakes are blocked by kernel param acpi.ec_no_wakeup=1
    # See docs/power-management.md for research on dock wake vs AC wake detection

    # Clear phantom monitors after resume
    # When laptop is undocked while asleep, Hyprland keeps phantom monitors
    # This service disables disconnected monitors and restarts HDM for fresh detection
    systemd.services.hyprdynamicmonitors-resume = {
      description = "Clear phantom monitors after system resume";
      after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "hdm-resume" ''
          # Run as user to access Hyprland socket
          export XDG_RUNTIME_DIR=/run/user/1000
          export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ 2>/dev/null | head -1)

          if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
            exit 0  # Hyprland not running
          fi

          # Disable monitors that DRM reports as disconnected (phantoms in Hyprland)
          for status_file in /sys/class/drm/card*/status; do
            if [ -f "$status_file" ]; then
              connector=$(basename $(dirname "$status_file"))
              connector_name=''${connector#card?-}
              status=$(cat "$status_file")

              if [ "$status" = "disconnected" ] && [ "$connector_name" != "Writeback-1" ]; then
                ${pkgs.hyprland}/bin/hyprctl keyword monitor "$connector_name,disable" 2>/dev/null || true
              fi
            fi
          done

          sleep 1

          # Restart HDM to re-detect actual monitors
          ${pkgs.systemd}/bin/systemctl --user --machine=${config.username}@.host restart hyprdynamicmonitors.service 2>/dev/null || true

          # Turn displays back on now that monitor configuration is stable
          # This prevents lockscreen from rendering while display config is changing
          ${pkgs.hyprland}/bin/hyprctl dispatch dpms on 2>/dev/null || true
        '';
      };
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
  };
}
