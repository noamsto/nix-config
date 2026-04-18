{pkgs, ...}: let
  # System-only idle inhibitor with a cycle of preset durations:
  # off → 30m → 2h → 8h → unlimited → off.
  #
  # Uses systemd-inhibit with --what=sleep:handle-lid-switch so the laptop
  # stays on but hypridle's dim/lock/DPMS-off listeners still fire — i.e.
  # the monitor can sleep. This complements Noctalia's "Keep Awake" (which
  # blocks everything via the Wayland idle-inhibit protocol).
  system-awake = pkgs.writeShellScriptBin "system-awake" ''
    #!/usr/bin/env bash
    set -euo pipefail

    STATE_FILE="''${XDG_RUNTIME_DIR:-/tmp}/system-awake.state"
    END_FILE="''${XDG_RUNTIME_DIR:-/tmp}/system-awake.end"
    PID_FILE="''${XDG_RUNTIME_DIR:-/tmp}/system-awake.pid"
    TAG="noams-system-awake"

    notify() {
      ${pkgs.libnotify}/bin/notify-send -i "$1" "System Awake" "$2" -t 2500 || true
    }

    guard_start() {
      ${pkgs.systemd}/bin/systemctl --user start system-awake-thermal-guard.service 2>/dev/null || true
    }
    guard_stop() {
      ${pkgs.systemd}/bin/systemctl --user stop system-awake-thermal-guard.service 2>/dev/null || true
    }

    cleanup() {
      if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
      fi
      pkill -f "systemd-inhibit.*$TAG" 2>/dev/null || true
      rm -f "$STATE_FILE" "$END_FILE" "$PID_FILE"
      guard_stop
    }

    start() {
      local duration="$1"  # seconds, or "unlimited"
      local label="$2"

      cleanup

      if [[ "$duration" == "unlimited" ]]; then
        setsid -f ${pkgs.systemd}/bin/systemd-inhibit \
          --what=sleep:handle-lid-switch \
          --who=hyprland \
          --why="$TAG ($label)" \
          --mode=block \
          sleep infinity >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        echo "unlimited" > "$STATE_FILE"
      else
        setsid -f ${pkgs.coreutils}/bin/timeout "''${duration}s" \
          ${pkgs.systemd}/bin/systemd-inhibit \
          --what=sleep:handle-lid-switch \
          --who=hyprland \
          --why="$TAG ($label)" \
          --mode=block \
          sleep infinity >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        echo "$label" > "$STATE_FILE"
        echo $(( $(date +%s) + duration )) > "$END_FILE"
      fi

      guard_start
      notify "weather-clear" "Enabled for $label — monitor may still sleep"
    }

    current_state="off"
    [[ -f "$STATE_FILE" ]] && current_state=$(cat "$STATE_FILE")

    # Validate the inhibitor process is alive; if not, reset state.
    if [[ "$current_state" != "off" && -f "$PID_FILE" ]]; then
      pid=$(cat "$PID_FILE")
      if ! kill -0 "$pid" 2>/dev/null; then
        cleanup
        current_state="off"
      fi
    fi

    case "''${1:-toggle}" in
      toggle)
        case "$current_state" in
          off|"")       start 1800       "30m" ;;
          30m)          start 7200       "2h"  ;;
          2h)           start 28800      "8h"  ;;
          8h)           start unlimited  "unlimited" ;;
          unlimited)    cleanup; notify "weather-clear-night" "Disabled" ;;
          *)            cleanup; notify "weather-clear-night" "Disabled" ;;
        esac
        ;;
      off)
        cleanup
        notify "weather-clear-night" "Disabled"
        ;;
      status|label)
        # `status` prints verbose state; `label` is compact for bar widgets
        # and prints an empty string when off (so expandWithOutput collapses).
        mode="''${1:-status}"
        if [[ "$current_state" == "off" || -z "$current_state" ]]; then
          [[ "$mode" == "status" ]] && echo "off"
        elif [[ "$current_state" == "unlimited" ]]; then
          [[ "$mode" == "label" ]] && echo "∞" || echo "unlimited"
        else
          now=$(date +%s)
          end=$(cat "$END_FILE" 2>/dev/null || echo "$now")
          remaining=$(( end - now ))
          if (( remaining <= 0 )); then
            cleanup
            [[ "$mode" == "status" ]] && echo "off"
          else
            mins=$(( remaining / 60 ))
            if [[ "$mode" == "label" ]]; then
              if (( mins >= 60 )); then
                printf "%dh%02dm\n" $(( mins / 60 )) $(( mins % 60 ))
              else
                printf "%dm\n" "$mins"
              fi
            else
              printf "%s (%dm left)\n" "$current_state" "$mins"
            fi
          fi
        fi
        ;;
      *)
        echo "usage: system-awake [toggle|off|status|label]" >&2
        exit 2
        ;;
    esac
  '';
in {
  home.packages = [system-awake];
}
