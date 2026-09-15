{
  pkgs,
  config,
  lib,
  ...
}: let
  inherit (config.machine) isLaptop;
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
          LOG="/tmp/hdm-resume.log"
          log() {
            echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [hdm-resume] $*" | tee -a "$LOG"
          }

          log "=== Resume handler started ==="

          # Run as user to access Hyprland socket
          USER_UID=$(id -u ${config.username})
          export XDG_RUNTIME_DIR=/run/user/$USER_UID

          # Find the ACTIVE Hyprland socket (most recently modified, not alphabetically first)
          # Old stale sockets may exist; ls -t sorts by modification time
          export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/$USER_UID/hypr/ 2>/dev/null | head -1)

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

          # Outputs re-enumerate over several seconds after resume, and HDM matches
          # profiles against whatever exists at that instant — so it can apply a
          # profile for a topology this handler is still correcting. Park it for
          # the window. The trap covers every exit path, since leaving HDM stopped
          # loses monitor management entirely.
          start_hdm() {
            log "Starting hyprdynamicmonitors.service..."
            ${pkgs.systemd}/bin/systemctl --user --machine=${config.username}@.host start hyprdynamicmonitors.service 2>/dev/null || true
          }
          trap start_hdm EXIT

          log "Stopping hyprdynamicmonitors.service for the resume window..."
          ${pkgs.systemd}/bin/systemctl --user --machine=${config.username}@.host stop hyprdynamicmonitors.service 2>/dev/null || true

          # Check Noctalia status
          # Noctalia's binary is wrapped (exec -a); comm is truncated, so match argv[0] instead.
          noctalia_pid=$(${pkgs.procps}/bin/pgrep -f '/bin/noctalia$' | head -1)
          if [ -n "$noctalia_pid" ]; then
            log "Noctalia running (PID: $noctalia_pid)"
          else
            log "WARNING: Noctalia NOT running at resume!"
          fi

          # Log current monitor state and count monitors
          log "Monitor state at resume (Hyprland):"
          initial_monitor_count=$(${pkgs.hyprland}/bin/hyprctl monitors -j 2>/dev/null | ${pkgs.jq}/bin/jq 'length' 2>/dev/null || echo 0)
          ${pkgs.hyprland}/bin/hyprctl monitors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[] | "  \(.name): \(.width)x\(.height) disabled=\(.disabled)"' 2>&1 | while read line; do log "$line"; done
          log "Initial Hyprland monitor count: $initial_monitor_count"

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
                ${pkgs.hyprland}/bin/hyprctl eval "hl.monitor({ output = \"$connector_name\", disabled = true })" 2>/dev/null || true
              fi
            fi
          done

          # Enable laptop monitor BEFORE turning on display, but only when appropriate.
          # When lid is closed and external monitors are connected, skip enabling eDP-1
          # to avoid wrong layout / rendering on the closed screen before HDM applies the profile.
          # Only force-enable eDP-1 as fallback when no other monitors are connected.
          lid_closed=false
          if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
            lid_closed=true
          fi

          # Count non-eDP connected monitors from DRM
          other_connected=0
          for status_file in /sys/class/drm/card*/status; do
            if [ -f "$status_file" ]; then
              connector=$(basename $(dirname "$status_file"))
              connector_name=''${connector#card?-}
              status=$(cat "$status_file")
              if [ "$status" = "connected" ] && [ "$connector_name" != "eDP-1" ] && [ "$connector_name" != "Writeback-1" ]; then
                other_connected=$((other_connected + 1))
              fi
            fi
          done

          log "Lid closed: $lid_closed, other connected monitors: $other_connected"

          if [ "$lid_closed" = "true" ] && [ "$other_connected" -gt 0 ]; then
            log "Lid closed with external monitors present, skipping eDP-1 enable"
          else
            log "Enabling eDP-1 before DPMS on (lid open or no other monitors)..."
            ${pkgs.hyprland}/bin/hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "preferred", position = "auto", scale = ${config.laptop-scale} })' 2>/dev/null || true
          fi

          sleep 0.3

          # Check monitor state after adjustment
          log "Monitor state after resume adjustment:"
          ${pkgs.hyprland}/bin/hyprctl monitors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[] | "  \(.name): \(.width)x\(.height) disabled=\(.disabled)"' 2>&1 | while read line; do log "$line"; done

          # Turn displays on
          log "Turning DPMS on..."
          ${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.dpms({ action = "on" })' 2>/dev/null || true

          sleep 0.2

          # HDM is started by the EXIT trap above.
          log "=== Resume handler completed ==="
        '';
      };
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
  };
}
