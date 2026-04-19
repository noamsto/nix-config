{pkgs, ...}: let
  # Keep-awake backend. Cycles of states:
  #   off | {partial,full} × {30m, 1h, 2h, 4h, 8h, unlimited}
  #
  # Subcommands:
  #   start <seconds|unlimited> --scope=<partial|full>
  #   extend <seconds>
  #   off
  #   status [--json]
  #   label
  #   toggle-last     (activate last {duration,scope} combo, or off if already on)
  #   toggle          (legacy: cycle 30m→2h→8h→∞→off in partial scope; kept during plugin rollout)
  #
  # State lives in two files:
  #   $XDG_RUNTIME_DIR/system-awake.state.json  (active session, cleared on reboot)
  #   $XDG_STATE_HOME/system-awake/last.json    (last {duration_seconds,scope}, persists across reboots)
  system-awake = pkgs.writeShellScriptBin "system-awake" ''
    #!/usr/bin/env bash
    set -euo pipefail

    STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}"
    STATE_FILE="$STATE_DIR/system-awake.state.json"
    PERSIST_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/system-awake"
    LAST_FILE="$PERSIST_DIR/last.json"
    TAG="noams-system-awake"
    SCHEMA_VERSION=1

    mkdir -p "$PERSIST_DIR"

    notify() {
      ${pkgs.libnotify}/bin/notify-send -i "$1" "Keep Awake" "$2" -t 2500 || true
    }

    guard_start() {
      ${pkgs.systemd}/bin/systemctl --user start system-awake-thermal-guard.service 2>/dev/null || true
    }
    guard_stop() {
      ${pkgs.systemd}/bin/systemctl --user stop system-awake-thermal-guard.service 2>/dev/null || true
    }

    # Write the state JSON atomically.
    write_state() {
      local scope="$1" duration_label="$2" end_epoch="$3" pid="$4" started="$5"
      local tmp
      tmp=$(mktemp "$STATE_FILE.XXXXXX")
      ${pkgs.jq}/bin/jq -n \
        --arg schema "$SCHEMA_VERSION" \
        --arg scope "$scope" \
        --arg duration_label "$duration_label" \
        --argjson end_epoch "$end_epoch" \
        --argjson pid "$pid" \
        --argjson started "$started" \
        '{active:true, schema:($schema|tonumber), scope:$scope, duration_label:$duration_label, end_epoch:$end_epoch, pid:$pid, started_epoch:$started}' \
        > "$tmp"
      mv "$tmp" "$STATE_FILE"
    }

    write_last() {
      local duration_seconds="$1" scope="$2" duration_label="$3"
      local tmp
      tmp=$(mktemp "$LAST_FILE.XXXXXX")
      ${pkgs.jq}/bin/jq -n \
        --argjson duration_seconds "$duration_seconds" \
        --arg scope "$scope" \
        --arg duration_label "$duration_label" \
        '{duration_seconds:$duration_seconds, scope:$scope, duration_label:$duration_label}' \
        > "$tmp"
      mv "$tmp" "$LAST_FILE"
    }

    # Format seconds as a compact duration label.
    format_label() {
      local seconds="$1"
      if [[ "$seconds" == "unlimited" ]]; then
        echo "∞"
      elif (( seconds >= 3600 )); then
        local h=$(( seconds / 3600 )) m=$(( (seconds % 3600) / 60 ))
        if (( m == 0 )); then
          printf '%dh\n' "$h"
        else
          printf '%dh%02dm\n' "$h" "$m"
        fi
      else
        printf '%dm\n' $(( seconds / 60 ))
      fi
    }

    # Returns 0 if a tagged inhibitor process is alive, 1 otherwise.
    # Uses pgrep on the unique tag instead of trusting a captured PID,
    # because `setsid -f` detaches the grandchild and $! is the dying parent.
    inhibitor_pid() {
      pgrep -f "systemd-inhibit.*$TAG" 2>/dev/null | head -1
    }

    is_active() {
      [[ -f "$STATE_FILE" ]] || return 1
      [[ -n "$(inhibitor_pid)" ]]
    }

    # Wait for any tagged inhibitor processes to actually die.
    # pgrep returns matches in ascending PID order, so if we race a dying
    # old process against a newly-spawned one, head -1 would pick the dying
    # PID. Callers must ensure cleanup is synchronous w.r.t. process death.
    wait_inhibitor_gone() {
      local _
      for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        pgrep -f "systemd-inhibit.*$TAG" >/dev/null 2>&1 || return 0
        sleep 0.05
      done
    }

    cleanup_inactive() {
      rm -f "$STATE_FILE"
      pkill -f "systemd-inhibit.*$TAG" 2>/dev/null || true
      wait_inhibitor_gone
      guard_stop
    }

    # Start a new inhibit session. Stops any existing session first.
    cmd_start() {
      local duration="$1" scope="$2"
      local label_duration start_epoch end_epoch pid

      if [[ "$scope" != "partial" && "$scope" != "full" ]]; then
        echo "error: --scope must be partial or full" >&2
        exit 2
      fi

      # Silent cleanup of any previous session (no "Disabled" notification).
      cleanup_inactive

      start_epoch=$(date +%s)
      if [[ "$duration" == "unlimited" ]]; then
        label_duration="unlimited"
        end_epoch="null"
        setsid -f ${pkgs.systemd}/bin/systemd-inhibit \
          --what=sleep:handle-lid-switch \
          --who=hyprland \
          --why="$TAG ($scope unlimited)" \
          --mode=block \
          sleep infinity >/dev/null 2>&1 &
        write_last -1 "$scope" "∞"
      else
        if ! [[ "$duration" =~ ^[0-9]+$ ]]; then
          echo "error: duration must be a positive integer (seconds) or 'unlimited'" >&2
          exit 2
        fi
        label_duration=$(format_label "$duration")
        end_epoch=$(( start_epoch + duration ))
        setsid -f ${pkgs.coreutils}/bin/timeout "''${duration}s" \
          ${pkgs.systemd}/bin/systemd-inhibit \
          --what=sleep:handle-lid-switch \
          --who=hyprland \
          --why="$TAG ($scope $label_duration)" \
          --mode=block \
          sleep infinity >/dev/null 2>&1 &
        write_last "$duration" "$scope" "$label_duration"
      fi

      # Wait briefly for setsid's grandchild to register, then capture the real PID.
      sleep 0.1
      pid=$(inhibitor_pid)
      if [[ -z "$pid" ]]; then
        echo "warning: failed to detect inhibitor PID; aborting" >&2
        cleanup_inactive
        exit 1
      fi

      write_state "$scope" "$label_duration" "$end_epoch" "$pid" "$start_epoch"
      guard_start
      notify "weather-clear" "Enabled: $scope · $label_duration"
    }

    # Extend the active session by N seconds. Does NOT update last.json
    # (user's original picked duration is preserved for toggle-last).
    cmd_extend() {
      local delta="$1"
      if ! is_active; then
        echo "error: no active session to extend" >&2
        exit 1
      fi
      if ! [[ "$delta" =~ ^[0-9]+$ ]]; then
        echo "error: extend expects a positive integer (seconds)" >&2
        exit 2
      fi

      local end_epoch scope started_epoch
      end_epoch=$(${pkgs.jq}/bin/jq -r '.end_epoch' "$STATE_FILE")
      scope=$(${pkgs.jq}/bin/jq -r '.scope' "$STATE_FILE")
      started_epoch=$(${pkgs.jq}/bin/jq -r '.started_epoch' "$STATE_FILE")

      if [[ "$end_epoch" == "null" ]]; then
        notify "weather-clear" "Already unlimited"
        return 0
      fi

      local now new_end new_duration new_label pid
      now=$(date +%s)
      new_end=$(( end_epoch + delta ))
      new_duration=$(( new_end - now ))
      if (( new_duration <= 0 )); then
        cmd_off
        return 0
      fi
      new_label=$(format_label "$(( new_end - started_epoch ))")

      # Terminate old inhibitor process without touching last.json/notification.
      # Wait for it to actually die so the post-spawn pgrep sees only the new
      # process(es) — otherwise head -1 would return the dying PID.
      pkill -f "systemd-inhibit.*$TAG" 2>/dev/null || true
      wait_inhibitor_gone

      setsid -f ${pkgs.coreutils}/bin/timeout "''${new_duration}s" \
        ${pkgs.systemd}/bin/systemd-inhibit \
        --what=sleep:handle-lid-switch \
        --who=hyprland \
        --why="$TAG ($scope $new_label extended)" \
        --mode=block \
        sleep infinity >/dev/null 2>&1 &

      sleep 0.1
      pid=$(inhibitor_pid)
      if [[ -z "$pid" ]]; then
        echo "warning: failed to detect inhibitor PID after extend" >&2
        cleanup_inactive
        exit 1
      fi

      write_state "$scope" "$new_label" "$new_end" "$pid" "$started_epoch"
      # Defensive: guard service should already be running, but restart if crashed.
      guard_start
      notify "weather-clear" "Extended to $new_label"
    }

    cmd_off() {
      if [[ -f "$STATE_FILE" ]]; then
        notify "weather-clear-night" "Disabled"
      fi
      cleanup_inactive
    }

    cmd_status() {
      local json=0
      if [[ "''${1:-}" == "--json" ]]; then json=1; fi

      # Self-heal: if state file says active but PID is gone, wipe it.
      if [[ -f "$STATE_FILE" ]] && ! is_active; then
        cleanup_inactive
      fi

      if [[ ! -f "$STATE_FILE" ]]; then
        if (( json )); then
          echo '{"active":false}'
        else
          echo "off"
        fi
        return 0
      fi

      # Self-heal: timeout ticked past end_epoch but process is still alive
      # (shouldn't happen with `timeout Ns`, but guard anyway).
      local now end_epoch
      now=$(date +%s)
      end_epoch=$(${pkgs.jq}/bin/jq -r '.end_epoch' "$STATE_FILE")
      if [[ "$end_epoch" != "null" ]] && (( now >= end_epoch )); then
        cleanup_inactive
        if (( json )); then
          echo '{"active":false}'
        else
          echo "off"
        fi
        return 0
      fi

      if (( json )); then
        cat "$STATE_FILE"
      else
        local scope duration_label
        scope=$(${pkgs.jq}/bin/jq -r '.scope' "$STATE_FILE")
        duration_label=$(${pkgs.jq}/bin/jq -r '.duration_label' "$STATE_FILE")
        if [[ "$end_epoch" == "null" ]]; then
          printf '%s unlimited\n' "$scope"
        else
          local mins=$(( (end_epoch - now) / 60 ))
          printf '%s %s (%dm left)\n' "$scope" "$duration_label" "$mins"
        fi
      fi
    }

    cmd_label() {
      if [[ ! -f "$STATE_FILE" ]] || ! is_active; then
        cleanup_inactive
        return 0
      fi
      local end_epoch now remaining mins
      end_epoch=$(${pkgs.jq}/bin/jq -r '.end_epoch' "$STATE_FILE")
      if [[ "$end_epoch" == "null" ]]; then
        echo "∞"
        return 0
      fi
      now=$(date +%s)
      remaining=$(( end_epoch - now ))
      if (( remaining <= 0 )); then
        cleanup_inactive
        return 0
      fi
      mins=$(( remaining / 60 ))
      if (( mins >= 60 )); then
        printf '%dh%02dm\n' $(( mins / 60 )) $(( mins % 60 ))
      else
        printf '%dm\n' "$mins"
      fi
    }

    cmd_toggle_last() {
      if is_active; then
        cmd_off
        return 0
      fi
      if [[ ! -f "$LAST_FILE" ]]; then
        # No history — sensible first-time default.
        cmd_start 1800 partial
        return 0
      fi
      local seconds scope
      seconds=$(${pkgs.jq}/bin/jq -r '.duration_seconds' "$LAST_FILE")
      scope=$(${pkgs.jq}/bin/jq -r '.scope' "$LAST_FILE")
      if [[ "$seconds" == "-1" ]]; then
        cmd_start unlimited "$scope"
      else
        cmd_start "$seconds" "$scope"
      fi
    }

    # Back-compat for the Hyprland bind during plugin rollout. Remove in phase 5.
    cmd_toggle_legacy() {
      if is_active; then
        local label
        label=$(${pkgs.jq}/bin/jq -r '.duration_label' "$STATE_FILE")
        case "$label" in
          "30m") cmd_start  7200 partial ;;  # → 2h
          "2h")  cmd_start 28800 partial ;;  # → 8h
          "8h")  cmd_start unlimited partial ;;
          "∞")   cmd_off ;;
          *)     cmd_off ;;
        esac
      else
        cmd_start 1800 partial              # off → 30m
      fi
    }

    # --- Dispatch ----------------------------------------------------------

    if (( $# == 0 )); then
      set -- toggle
    fi

    cmd="$1"; shift || true

    case "$cmd" in
      start)
        __duration=""; __scope=""
        for arg in "$@"; do
          case "$arg" in
            --scope=*) __scope="''${arg#--scope=}" ;;
            *)         __duration="$arg" ;;
          esac
        done
        if [[ -z "$__duration" || -z "$__scope" ]]; then
          echo "usage: system-awake start <seconds|unlimited> --scope=<partial|full>" >&2
          exit 2
        fi
        cmd_start "$__duration" "$__scope"
        ;;
      extend)
        [[ $# -ge 1 ]] || { echo "usage: system-awake extend <seconds>" >&2; exit 2; }
        cmd_extend "$1"
        ;;
      off)            cmd_off ;;
      status)         cmd_status "''${1:-}" ;;
      label)          cmd_label ;;
      toggle-last)    cmd_toggle_last ;;
      toggle)         cmd_toggle_legacy ;;
      *)
        echo "usage: system-awake [start|extend|off|status|label|toggle-last|toggle] [args]" >&2
        exit 2
        ;;
    esac
  '';
in {
  home.packages = [system-awake];
}
