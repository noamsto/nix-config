{pkgs, ...}: let
  # Thermal watchdog that forces suspend if the laptop gets dangerously hot
  # while `system-awake` is active. HDM-profile-aware: the "sustained high
  # temp" trip only fires when undocked + lid closed (i.e. likely in a bag).
  # The "critical" trip fires unconditionally as a last resort.
  #
  # Thresholds:
  #   - 98 °C for 20 s → suspend (any state) — tolerates brief spikes
  #   - 85 °C for 60 s → suspend (only if undocked + lid closed)
  #
  # Started/stopped by the `system-awake` toggle; does not run otherwise.
  thermal-guard = pkgs.writeShellScriptBin "system-awake-thermal-guard" ''
    #!/usr/bin/env bash
    set -uo pipefail

    TAG="noams-system-awake"
    LOG="/tmp/system-awake-thermal-guard.log"
    POLL_INTERVAL=10               # seconds
    BAG_THRESHOLD=85000            # millicelsius
    BAG_SUSTAIN_TICKS=6            # 6 * 10s = 60s
    CRITICAL_THRESHOLD=98000       # millicelsius
    CRITICAL_SUSTAIN_TICKS=2       # 2 * 10s = 20s — tolerate brief spikes

    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG" >&2
    }

    max_temp_mC() {
      # Print highest current temp across all thermal zones, in millicelsius.
      local max=0 t
      for f in /sys/class/thermal/thermal_zone*/temp; do
        [[ -r "$f" ]] || continue
        t=$(cat "$f" 2>/dev/null || echo 0)
        (( t > max )) && max=$t
      done
      echo "$max"
    }

    is_lid_closed() {
      ${pkgs.glib}/bin/gdbus call --system \
        --dest org.freedesktop.UPower \
        --object-path /org/freedesktop/UPower \
        --method org.freedesktop.DBus.Properties.Get \
        org.freedesktop.UPower LidIsClosed 2>/dev/null | grep -q 'true'
    }

    has_external_monitors() {
      local status connector name
      for status in /sys/class/drm/card*/status; do
        [[ -f "$status" ]] || continue
        connector=$(basename "$(dirname "$status")")
        name=''${connector#card?-}
        if [[ "$(cat "$status")" == "connected" && \
              "$name" != "eDP-1" && \
              "$name" != "Writeback-1" ]]; then
          return 0
        fi
      done
      return 1
    }

    emergency_suspend() {
      local reason="$1" temp_c="$2"
      log "EMERGENCY: $reason (max=''${temp_c}°C) — forcing suspend"
      ${pkgs.libnotify}/bin/notify-send -u critical -i dialog-warning \
        "Thermal Protection" \
        "System too hot (''${temp_c}°C) — suspending to protect hardware" \
        -t 5000 || true

      # Drop our own sleep inhibitors so systemctl suspend is not blocked.
      pkill -f "systemd-inhibit.*$TAG" 2>/dev/null || true
      sleep 0.3

      ${pkgs.systemd}/bin/loginctl lock-session || true
      sleep 0.5
      ${pkgs.systemd}/bin/systemctl suspend
    }

    log "Thermal guard started (poll=''${POLL_INTERVAL}s, bag=''${BAG_THRESHOLD}mC/60s, critical=''${CRITICAL_THRESHOLD}mC/20s)"

    bag_sustained=0
    crit_sustained=0
    while true; do
      temp=$(max_temp_mC)
      temp_c=$(( temp / 1000 ))

      if (( temp >= CRITICAL_THRESHOLD )); then
        crit_sustained=$(( crit_sustained + 1 ))
        log "Critical temp: ''${temp_c}°C (tick $crit_sustained/$CRITICAL_SUSTAIN_TICKS)"
        if (( crit_sustained >= CRITICAL_SUSTAIN_TICKS )); then
          emergency_suspend "sustained critical temperature" "$temp_c"
          exit 0
        fi
      else
        if (( crit_sustained > 0 )); then
          log "Critical recovered (''${temp_c}°C) — resetting critical counter"
        fi
        crit_sustained=0
      fi

      if (( temp >= BAG_THRESHOLD )) && is_lid_closed && ! has_external_monitors; then
        bag_sustained=$(( bag_sustained + 1 ))
        log "Hot + lid-closed + undocked: ''${temp_c}°C (tick $bag_sustained/$BAG_SUSTAIN_TICKS)"
        if (( bag_sustained >= BAG_SUSTAIN_TICKS )); then
          emergency_suspend "sustained high temp while undocked+lid-closed" "$temp_c"
          exit 0
        fi
      else
        if (( bag_sustained > 0 )); then
          log "Recovered (''${temp_c}°C) — resetting bag counter"
        fi
        bag_sustained=0
      fi

      sleep "$POLL_INTERVAL"
    done
  '';
in {
  home.packages = [thermal-guard];

  systemd.user.services.system-awake-thermal-guard = {
    Unit = {
      Description = "Thermal watchdog for system-awake (force suspend if overheating)";
      # Not part of graphical-session so toggling system-awake off cleanly stops it.
    };
    Service = {
      Type = "simple";
      ExecStart = "${thermal-guard}/bin/system-awake-thermal-guard";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    # Intentionally no [Install] — started/stopped imperatively by `system-awake`.
  };
}
