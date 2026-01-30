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

    # Clear phantom monitors and prepare display after resume
    # When laptop is undocked while asleep, Hyprland keeps phantom monitors
    # This service ensures lockscreen has a valid monitor before DPMS turns on
    systemd.services.hyprdynamicmonitors-resume = {
      description = "Clear phantom monitors after system resume";
      after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "hdm-resume" ''
          # Run as user to access Hyprland socket
          export XDG_RUNTIME_DIR=/run/user/1000

          # Find the ACTIVE Hyprland socket (most recently modified, not alphabetically first)
          # Old stale sockets may exist; ls -t sorts by modification time
          export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr/ 2>/dev/null | head -1)

          if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
            exit 0  # Hyprland not running
          fi

          # Verify socket is actually accessible
          if ! ${pkgs.hyprland}/bin/hyprctl monitors &>/dev/null; then
            echo "Hyprland socket not responding, skipping resume actions"
            exit 0
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

          # CRITICAL: Enable laptop monitor BEFORE turning on display
          # The lockscreen is already active and will render as soon as DPMS turns on.
          # If eDP-1 was disabled (docked with lid closed), we must enable it first
          # to prevent lockscreen crash. HDM will refine the config afterward.
          ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-1,preferred,auto,2.0" 2>/dev/null || true

          sleep 0.3

          # Turn displays on - lockscreen can now render safely on eDP-1
          ${pkgs.hyprland}/bin/hyprctl dispatch dpms on 2>/dev/null || true

          sleep 0.2

          # Restart HDM to detect actual hardware state and apply correct profile
          # This runs after DPMS is on so any profile changes happen smoothly
          ${pkgs.systemd}/bin/systemctl --user --machine=${config.username}@.host restart hyprdynamicmonitors.service 2>/dev/null || true
        '';
      };
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
  };
}
