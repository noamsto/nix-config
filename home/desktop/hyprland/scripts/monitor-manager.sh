#!/usr/bin/env bash
# Unified Monitor Manager for Hyprland
# Handles monitor hotplug AND lid events with proper state tracking
# Replaces hyprdynamicmonitors + separate lid handler

set -euo pipefail

STATEFILE="/tmp/hyprland-monitor-state"
LOCKFILE="/tmp/hyprland-monitor-manager.lock"

# Prevent concurrent executions
exec 200>"$LOCKFILE"
flock -n 200 || exit 0

# Read current lid state from ACPI
get_lid_state() {
  cat /proc/acpi/button/lid/LID/state 2>/dev/null | awk '{print $2}' || echo "open"
}

# Get enabled monitors (excluding laptop screen if disabled in config)
get_monitors() {
  hyprctl monitors -j | jq -r '.[] | select(.name != "eDP-1") | .name + "|" + (.x | tostring) + "|" + .description'
}

# Get laptop monitor status
get_laptop_monitor() {
  hyprctl monitors -j | jq -r '.[] | select(.name == "eDP-1") | .name'
}

# Apply monitor configuration
apply_monitor_config() {
  local config_file=$1
  local profile_name=$2

  # Apply monitor configuration
  hyprctl keyword monitor "$(cat "$config_file" | grep "^monitor=" | sed 's/^monitor=//')" 2>/dev/null || true

  # Reload to apply all settings
  hyprctl reload

  notify-send "Monitor Profile" "$profile_name" -t 3000
}

# Assign workspaces to monitors based on position
assign_workspaces() {
  local monitor_count=$1
  local external_monitors=$2

  if [ "$monitor_count" -ge 2 ]; then
    # Two or more external monitors
    # Sort by X position and assign workspaces
    local left_monitor
    left_monitor=$(echo "$external_monitors" | sort -t'|' -k2 -n | head -1 | cut -d'|' -f1)
    local right_monitor
    right_monitor=$(echo "$external_monitors" | sort -t'|' -k2 -n | tail -1 | cut -d'|' -f1)

    # Move workspaces to monitors by position
    for ws in 1 2 3 4; do
      hyprctl dispatch moveworkspacetomonitor "$ws" "$left_monitor" 2>/dev/null || true
    done

    for ws in 5 6 7 8; do
      hyprctl dispatch moveworkspacetomonitor "$ws" "$right_monitor" 2>/dev/null || true
    done

    # Laptop screen gets workspaces 9-10 (if enabled)
    if [ -n "$(get_laptop_monitor)" ]; then
      hyprctl dispatch moveworkspacetomonitor 9 eDP-1 2>/dev/null || true
      hyprctl dispatch moveworkspacetomonitor 10 eDP-1 2>/dev/null || true
    fi
  elif [ "$monitor_count" -eq 1 ]; then
    # One external monitor
    local ext_monitor
    ext_monitor=$(echo "$external_monitors" | cut -d'|' -f1)

    for ws in 1 2 3 4 5 6 7 8; do
      hyprctl dispatch moveworkspacetomonitor "$ws" "$ext_monitor" 2>/dev/null || true
    done

    if [ -n "$(get_laptop_monitor)" ]; then
      hyprctl dispatch moveworkspacetomonitor 9 eDP-1 2>/dev/null || true
      hyprctl dispatch moveworkspacetomonitor 10 eDP-1 2>/dev/null || true
    fi
  fi
  # If monitor_count == 0, all workspaces stay on eDP-1 by default
}

# Main logic
main() {
  local lid_state
  lid_state=$(get_lid_state)
  local external_monitors
  external_monitors=$(get_monitors)

  # Count monitors properly (empty string = 0, not 1)
  local monitor_count
  if [ -z "$external_monitors" ]; then
    monitor_count=0
  else
    monitor_count=$(echo "$external_monitors" | wc -l)
  fi

  # Read last known state
  local last_state
  last_state=$(cat "$STATEFILE" 2>/dev/null || echo "")
  local current_state="${lid_state}:${monitor_count}"

  # If state hasn't changed, exit (debounce spurious events)
  if [ "$current_state" = "$last_state" ]; then
    exit 0
  fi

  # Save new state
  echo "$current_state" >"$STATEFILE"

  # Determine appropriate action based on combined state
  if [ "$lid_state" = "closed" ] && [ "$monitor_count" -eq 0 ]; then
    # Undocked with lid closed - lock and suspend
    notify-send "Suspending" "Lid closed, no external monitors" -t 2000
    loginctl lock-session
    sleep 2
    systemctl suspend

  elif [ "$lid_state" = "closed" ] && [ "$monitor_count" -ge 1 ]; then
    # Docked with lid closed - disable laptop screen
    hyprctl keyword monitor "eDP-1,disable"
    notify-send "Monitor Profile" "Docked (Lid Closed) - $monitor_count external monitors" -t 3000
    assign_workspaces "$monitor_count" "$external_monitors"

  elif [ "$lid_state" = "open" ] && [ "$monitor_count" -ge 2 ]; then
    # Docked with lid open - enable laptop screen + external monitors
    hyprctl keyword monitor "eDP-1,2880x1800@120,1280x1440,2.0"
    notify-send "Monitor Profile" "Docked (Lid Open) - $monitor_count external monitors" -t 3000
    assign_workspaces "$monitor_count" "$external_monitors"

  elif [ "$lid_state" = "open" ] && [ "$monitor_count" -eq 1 ]; then
    # One external + laptop
    hyprctl keyword monitor "eDP-1,2880x1800@120,0x1440,2.0"
    notify-send "Monitor Profile" "Single External + Laptop" -t 3000
    assign_workspaces "$monitor_count" "$external_monitors"

  else
    # Laptop only (undocked, lid open)
    hyprctl keyword monitor "eDP-1,2880x1800@120,0x0,2.0"
    notify-send "Monitor Profile" "Laptop Only" -t 3000
  fi
}

main "$@"
