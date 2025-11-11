#!/usr/bin/env bash
# Undocked - laptop screen only (lid open)
#
# This script handles undocking with the lid open. It consolidates workspaces
# from external monitors (5-10) into the mobile workspace layout (1-4).

set -euo pipefail

# Constants
readonly LOG_FILE="/tmp/undocked.log"

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

log "=== Undocked event triggered (lid open) ==="

# Apply monitor configuration using fast hyprctl keyword
log "Configuring laptop monitor"
hyprctl keyword monitor "eDP-1,2880x1800@120,0x0,2.0" 2>/dev/null || log "Failed to configure monitor"

# Give monitor a moment to stabilize
sleep 0.5

# Load laptop XWayland HiDPI settings (2.0 scale = 192 DPI)
xrdb -merge ~/.Xresources.laptop 2>/dev/null &

# Background workspace cleanup to avoid HDM timeout
(
  sleep 1

  # Consolidate workspaces 5-10 into 1-4 (move windows, not just workspaces)
  log "Consolidating workspaces 5-10 into 1-4"
  for src_ws in {5..10}; do
    # Get list of windows on source workspace
    windows=$(hyprctl clients -j 2>/dev/null | jq -r ".[] | select(.workspace.id == $src_ws) | .address" 2>/dev/null || echo "")

    if [ -n "$windows" ]; then
      # Calculate target workspace (5→1, 6→2, 7→3, 8→4, 9→1, 10→2)
      target_ws=$((((src_ws - 5) % 4) + 1))
      log "Moving windows from workspace $src_ws to workspace $target_ws"

      # Move each window individually
      while IFS= read -r window; do
        if [ -n "$window" ]; then
          hyprctl dispatch movetoworkspacesilent "$target_ws,address:$window" 2>/dev/null || log "Failed to move window $window"
        fi
      done <<<"$windows"
    fi

    # Make workspace non-persistent
    hyprctl keyword workspace "$src_ws,persistent:false" 2>/dev/null || true
  done

  # Move workspaces 1-4 to laptop screen
  log "Moving workspaces 1-4 to laptop screen"
  for ws in {1..4}; do
    hyprctl dispatch workspace "$ws" 2>/dev/null || log "Failed to switch to workspace $ws"
    hyprctl dispatch moveworkspacetomonitor "$ws" eDP-1 2>/dev/null || log "Failed to move workspace $ws to eDP-1"
  done

  # Focus laptop monitor and workspace 1
  log "Focusing laptop monitor and workspace 1"
  hyprctl dispatch focusmonitor eDP-1 2>/dev/null || log "Failed to focus eDP-1"
  hyprctl dispatch workspace 1 2>/dev/null || log "Failed to switch to workspace 1"

  # Remove any disconnected monitors from Hyprland's state (cleanup)
  log "Cleaning up disconnected monitors"
  hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null | while read -r monitor; do
    if [ "$monitor" != "eDP-1" ]; then
      hyprctl keyword monitor "$monitor,disable" 2>/dev/null || true
    fi
  done

  log "Undocked configuration complete"
) &

# Launch dock in background
launch-dock &

# Start fingerprint daemon for undocked usage
systemctl start fprintd.service 2>/dev/null &
