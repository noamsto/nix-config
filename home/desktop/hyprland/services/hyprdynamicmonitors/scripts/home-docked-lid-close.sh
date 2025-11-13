#!/usr/bin/env bash
# Home docked with lid closed - dual Samsung monitors, laptop screen disabled
#
# This script handles docking at home with the lid closed. It configures the two
# external displays and disables the laptop screen.

set -euo pipefail

# Constants
readonly LOG_FILE="/tmp/home-docked-lid-close.log"

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG_FILE"
}

log "=== Home docked event triggered (lid closed) ==="

# Apply monitor configuration using fast hyprctl keyword commands
# (HDM links the config but Hyprland won't read it due to disable_autoreload=true)
log "Configuring two external monitors and disabling laptop screen"
hyprctl keyword monitor "desc:Samsung Electric Company S27H85x H4ZM300138,2560x1440@60,0x0,1.0" 2>/dev/null || log "Failed to configure left Samsung"
hyprctl keyword monitor "desc:Samsung Electric Company S27H85x H4ZKB00167,2560x1440@60,2560x0,1.0" 2>/dev/null || log "Failed to configure right Samsung"
hyprctl keyword monitor "eDP-1,disable" 2>/dev/null || log "Failed to disable laptop screen"

# Give monitors a moment to stabilize after configuration
sleep 0.5

# Load docked XWayland HiDPI settings (1.0 scale = 96 DPI for external monitors)
xrdb -merge ~/.Xresources.docked 2>/dev/null &

# Background the workspace setup to avoid blocking HDM
(
  # Small delay to ensure monitors are fully ready
  sleep 1

  # Left monitor (Samsung H4ZM300138): workspaces 1-4
  log "Configuring workspaces 1-4 for left Samsung"
  for ws in {1..4}; do
    # Set default monitor for this workspace
    hyprctl keyword workspace "$ws,monitor:desc:Samsung Electric Company S27H85x H4ZM300138" 2>/dev/null || log "Failed to set workspace $ws rule"
    # Move existing workspace if it exists
    hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Samsung Electric Company S27H85x H4ZM300138" 2>/dev/null || true
  done

  # Right monitor (Samsung H4ZKB00167): workspaces 5-9 (lid closed)
  log "Configuring workspaces 5-9 for right Samsung"
  for ws in {5..9}; do
    # Set default monitor for this workspace
    hyprctl keyword workspace "$ws,monitor:desc:Samsung Electric Company S27H85x H4ZKB00167" 2>/dev/null || log "Failed to set workspace $ws rule"
    # Move existing workspace if it exists
    hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Samsung Electric Company S27H85x H4ZKB00167" 2>/dev/null || true
  done

  # Make workspaces 5-9 persistent for dual monitor setup
  log "Making workspaces 5-9 persistent"
  for ws in {5..9}; do
    hyprctl keyword workspace "$ws,persistent:true" 2>/dev/null || log "Failed to make workspace $ws persistent"
  done

  # Clean up extra workspaces (10+)
  log "Cleaning up extra workspaces"
  for ws in {10..20}; do
    hyprctl keyword workspace "$ws,persistent:false" 2>/dev/null || true
  done

  # Return to workspace 1 on left monitor
  log "Focusing workspace 1"
  hyprctl dispatch workspace 1 2>/dev/null || log "Failed to focus workspace 1"

  log "Home docked configuration complete (lid closed)"
) &

# Stop fingerprint daemon when lid is closed (before backgrounding other tasks)
log "Stopping fingerprint daemon"
systemctl stop fprintd.service 2>/dev/null || log "Failed to stop fprintd"

# Launch dock in background
launch-dock &
