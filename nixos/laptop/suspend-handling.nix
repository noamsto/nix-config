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
          LOG="/tmp/noctalia-lock.log"
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [hdm-resume] $*" | tee -a "$LOG"
          }

          log "=== Resume handler started ==="

          # Run as user to access Hyprland socket
          export XDG_RUNTIME_DIR=/run/user/1000

          # Find the ACTIVE Hyprland socket (most recently modified, not alphabetically first)
          # Old stale sockets may exist; ls -t sorts by modification time
          export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr/ 2>/dev/null | head -1)

          if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
            log "No Hyprland socket found, exiting"
            exit 0  # Hyprland not running
          fi
          log "Using Hyprland socket: $HYPRLAND_INSTANCE_SIGNATURE"

          # Verify socket is actually accessible
          if ! ${pkgs.hyprland}/bin/hyprctl monitors &>/dev/null; then
            log "ERROR: Hyprland socket not responding, skipping resume actions"
            exit 0
          fi

          # Check Noctalia status
          noctalia_pid=$(${pkgs.procps}/bin/pgrep -f 'quickshell.*noctalia-shell' | head -1)
          if [ -n "$noctalia_pid" ]; then
            log "Noctalia running (PID: $noctalia_pid)"
          else
            log "WARNING: Noctalia NOT running at resume!"
          fi

          # Log current monitor state
          log "Monitor state at resume (Hyprland):"
          ${pkgs.hyprland}/bin/hyprctl monitors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[] | "  \(.name): \(.width)x\(.height) disabled=\(.disabled)"' 2>&1 | while read line; do log "$line"; done

          # Log DRM connector status
          log "DRM connector status:"
          for status_file in /sys/class/drm/card*/status; do
            if [ -f "$status_file" ]; then
              connector=$(basename $(dirname "$status_file"))
              connector_name=''${connector#card?-}
              status=$(cat "$status_file")
              log "  $connector_name: $status"
            fi
          done

          # Disable monitors that DRM reports as disconnected (phantoms in Hyprland)
          log "Disabling phantom monitors..."
          for status_file in /sys/class/drm/card*/status; do
            if [ -f "$status_file" ]; then
              connector=$(basename $(dirname "$status_file"))
              connector_name=''${connector#card?-}
              status=$(cat "$status_file")

              if [ "$status" = "disconnected" ] && [ "$connector_name" != "Writeback-1" ]; then
                log "  Disabling phantom: $connector_name"
                ${pkgs.hyprland}/bin/hyprctl keyword monitor "$connector_name,disable" 2>/dev/null || true
              fi
            fi
          done

          # CRITICAL: Enable laptop monitor BEFORE turning on display
          # The lockscreen is already active and will render as soon as DPMS turns on.
          # If eDP-1 was disabled (docked with lid closed), we must enable it first
          # to prevent lockscreen crash. HDM will refine the config afterward.
          log "Enabling eDP-1 before DPMS on..."
          ${pkgs.hyprland}/bin/hyprctl keyword monitor "eDP-1,preferred,auto,2.0" 2>/dev/null || true

          sleep 0.3

          # Check monitor state after enabling eDP-1
          log "Monitor state after eDP-1 enable:"
          ${pkgs.hyprland}/bin/hyprctl monitors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[] | "  \(.name): \(.width)x\(.height) disabled=\(.disabled)"' 2>&1 | while read line; do log "$line"; done

          # Turn displays on - lockscreen can now render safely on eDP-1
          log "Turning DPMS on..."
          ${pkgs.hyprland}/bin/hyprctl dispatch dpms on 2>/dev/null || true

          sleep 0.2

          # Check Noctalia status after DPMS on
          noctalia_pid=$(${pkgs.procps}/bin/pgrep -f 'quickshell.*noctalia-shell' | head -1)
          if [ -n "$noctalia_pid" ]; then
            log "Noctalia still running (PID: $noctalia_pid)"
          else
            log "ERROR: Noctalia DIED after DPMS on!"
          fi

          # Restart HDM to detect actual hardware state and apply correct profile
          # This runs after DPMS is on so any profile changes happen smoothly
          log "Restarting hyprdynamicmonitors.service..."
          ${pkgs.systemd}/bin/systemctl --user --machine=${config.username}@.host restart hyprdynamicmonitors.service 2>/dev/null || true

          log "=== Resume handler completed ==="
        '';
      };
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
  };
}
