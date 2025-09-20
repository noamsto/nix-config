#!/bin/bash

STATE_FILE="/tmp/inhibitor-state"
END_FILE="/tmp/inhibitor-end"
PID_FILE="/tmp/inhibitor-pid"

# Function to cleanup inhibitor
cleanup_inhibitor() {
  if [[ -f $PID_FILE ]]; then
    local pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
    fi
    rm -f "$PID_FILE"
  fi
  rm -f "$STATE_FILE" "$END_FILE"
  # Restore WiFi power save
  nmcli radio wifi powersave on 2>/dev/null || true
}

# Function to start inhibitor
start_inhibitor() {
  local duration=$1
  local duration_text=$2

  cleanup_inhibitor

  # Disable WiFi power save
  nmcli radio wifi powersave off 2>/dev/null || true

  if [[ $duration == "unlimited" ]]; then
    systemd-inhibit --what=idle:sleep --who=waybar --why="Timed inhibitor ($duration_text)" \
      sleep infinity &
    echo $! >"$PID_FILE"
    echo "unlimited" >"$STATE_FILE"
  else
    local seconds
    case $duration in
    "30m") seconds=1800 ;;
    "2h") seconds=7200 ;;
    "8h") seconds=28800 ;;
    esac

    timeout ${seconds}s systemd-inhibit --what=idle:sleep --who=waybar --why="Timed inhibitor ($duration_text)" \
      sleep infinity &
    echo $! >"$PID_FILE"
    echo "$duration" >"$STATE_FILE"
    echo $(($(date +%s) + seconds)) >"$END_FILE"
  fi
}

# Handle toggle action
if [[ $1 == "toggle" ]]; then
  current_state="off"
  if [[ -f $STATE_FILE ]]; then
    current_state=$(cat "$STATE_FILE")
  fi

  case "$current_state" in
  "off" | "") start_inhibitor "30m" "30 minutes" ;;
  "30m") start_inhibitor "2h" "2 hours" ;;
  "2h") start_inhibitor "8h" "8 hours" ;;
  "8h") start_inhibitor "unlimited" "unlimited" ;;
  "unlimited") cleanup_inhibitor ;;
  esac
  exit 0
fi

# Generate status output
current_state="off"
tooltip="Idle inhibitor OFF - Click to enable"
icon="󰒲"
class="inactive"

if [[ -f $STATE_FILE ]]; then
  current_state=$(cat "$STATE_FILE")

  case "$current_state" in
  "30m" | "2h" | "8h")
    if [[ -f $END_FILE ]]; then
      end_time=$(cat "$END_FILE")
      now=$(date +%s)
      remaining=$((end_time - now))

      if [[ $remaining -gt 0 ]]; then
        hours=$((remaining / 3600))
        minutes=$(((remaining % 3600) / 60))

        if [[ $hours -gt 0 ]]; then
          time_str="${hours}h ${minutes}m"
        else
          time_str="${minutes}m"
        fi

        tooltip="Idle & WiFi power save disabled ($time_str remaining)"
        case "$current_state" in
        "30m")
          icon="󰒳  ³⁰ᵐ"
          class="active-30m"
          ;;
        "2h")
          icon="󰒳  ²ʰ"
          class="active-2h"
          ;;
        "8h")
          icon="󰒳  ⁸ʰ"
          class="active-8h"
          ;;
        esac
      else
        # Timer expired, clean up
        cleanup_inhibitor
        tooltip="Idle inhibitor OFF - Click to enable"
        icon="󰒲 "
        class="inactive"
      fi
    else
      # No end time file, cleanup
      cleanup_inhibitor
    fi
    ;;
  "unlimited")
    tooltip="Idle & WiFi power save disabled (unlimited)"
    icon="󰒳  ∞"
    class="active-unlimited"
    ;;
  esac
fi

# Check if inhibitor process is still running
if [[ $current_state != "off" && -f $PID_FILE ]]; then
  pid=$(cat "$PID_FILE")
  if ! kill -0 "$pid" 2>/dev/null; then
    # Process died, cleanup
    cleanup_inhibitor
    tooltip="Idle inhibitor OFF - Click to enable"
    icon="󰒲"
    class="inactive"
  fi
fi

echo "{\"text\": \"$icon\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"
