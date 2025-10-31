#!/usr/bin/env bash
# Undocked - laptop screen only (lid open)

# Apply monitor configuration using fast hyprctl keyword
hyprctl keyword monitor "eDP-1,2880x1800@120,0x0,2.0" 2>/dev/null

# Give monitor a moment to stabilize
sleep 0.5

# Load laptop XWayland HiDPI settings (2.0 scale = 192 DPI)
xrdb -merge ~/.Xresources.laptop &

# Background workspace cleanup to avoid HDM timeout
(
  sleep 1

  # Reset workspace persistence
  for ws in {5..10}; do
    hyprctl keyword workspace "$ws,persistent:false" 2>/dev/null || true
  done

  # Move workspaces 1-4 to laptop screen
  for ws in {1..4}; do
    hyprctl dispatch workspace "$ws" 2>/dev/null || true
    hyprctl dispatch moveworkspacetomonitor "$ws" eDP-1 2>/dev/null || true
  done

  # Focus workspace 1
  hyprctl dispatch workspace 1 2>/dev/null || true
) &

# Launch dock in background
launch-dock &

# Start fingerprint daemon for undocked usage
systemctl start fprintd.service 2>/dev/null &
