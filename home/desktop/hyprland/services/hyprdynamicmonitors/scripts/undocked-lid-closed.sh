#!/usr/bin/env bash
# Undocked with lid closed - configure workspaces, then suspend
#
# This script handles the critical case of closing the laptop lid while undocked.
# It must:
# 1. Verify the lid is actually closed (prevent bounce)
# 2. Move all workspaces (1-9) to laptop screen
# 3. Suspend reliably without race conditions

set -euo pipefail

# Constants
readonly LID_STATE_FILE="/proc/acpi/button/lid/LID/state"
readonly SUSPEND_LOCK_FILE="/tmp/hyprdynamicmonitors-suspend.lock"
readonly LOG_FILE="/tmp/undocked-lid-closed.log"

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

# Check if suspend is already in progress
if [ -f "$SUSPEND_LOCK_FILE" ]; then
  log "Suspend already in progress, exiting"
  exit 0
fi

log "=== Undocked lid closed event triggered ==="

# Apply monitor configuration using fast hyprctl keyword
log "Configuring laptop monitor"
hyprctl keyword monitor "eDP-1,2880x1800@120,0x0,2.0" 2>/dev/null || log "Failed to configure monitor"

# Give monitor a moment to stabilize
sleep 0.5

# Load laptop XWayland HiDPI settings (2.0 scale = 192 DPI)
xrdb -merge ~/.Xresources.laptop 2>/dev/null &

# Launch dock and services before suspend (so they're ready on wake)
launch-dock &
systemctl start fprintd.service 2>/dev/null &

# CRITICAL: Verify lid is actually closed for 2 seconds to prevent bounce
log "Verifying lid state..."
for _ in {1..4}; do
  if [ -f "$LID_STATE_FILE" ]; then
    lid_state=$(grep -oP 'state:\s*\K\w+' "$LID_STATE_FILE" 2>/dev/null || echo "unknown")
    if [ "$lid_state" != "closed" ]; then
      log "Lid not closed (state: $lid_state), aborting suspend"
      exit 0
    fi
  fi
  sleep 0.5
done

log "Lid confirmed closed, proceeding with workspace consolidation and suspend"

# Create suspend lock to prevent duplicate attempts
touch "$SUSPEND_LOCK_FILE"

# Move all workspaces 1-9 to laptop screen
log "Moving workspaces 1-9 to laptop screen"
for ws in {1..9}; do
  hyprctl dispatch moveworkspacetomonitor "$ws" eDP-1 2>/dev/null || log "Failed to move workspace $ws to eDP-1"
done

# Focus laptop monitor and workspace 1
log "Focusing laptop monitor and workspace 1"
hyprctl dispatch focusmonitor eDP-1 2>/dev/null || log "Failed to focus eDP-1"
hyprctl dispatch workspace 1 2>/dev/null || log "Failed to switch to workspace 1"

# Brief delay for screen fade (requested 2-3 second delay total, we've used ~2s for lid check)
log "Waiting before suspend..."
sleep 1

# Remove any disconnected monitors from Hyprland's state (cleanup)
log "Cleaning up disconnected monitors"
hyprctl monitors -j 2>/dev/null | jq -r '.[].name' 2>/dev/null | while read -r monitor; do
  if [ "$monitor" != "eDP-1" ]; then
    hyprctl keyword monitor "$monitor,disable" 2>/dev/null || true
  fi
done

# Suspend immediately (NOT backgrounded - this is the critical fix)
log "Initiating suspend..."
systemctl suspend

# This line runs after wake from suspend
log "=== Resumed from suspend ==="
rm -f "$SUSPEND_LOCK_FILE"
