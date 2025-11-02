#!/usr/bin/env bash
# Undocked with lid closed - configure then suspend

# Apply monitor configuration using fast hyprctl keyword
hyprctl keyword monitor "eDP-1,2880x1800@120,0x0,2.0" 2>/dev/null

# Give monitor a moment to stabilize
sleep 0.5

# Load laptop XWayland HiDPI settings (2.0 scale = 192 DPI)
xrdb -merge ~/.Xresources.laptop &

# Launch dock and services before suspend (so they're ready on wake)
launch-dock &
systemctl start fprintd.service 2>/dev/null &

# Background cleanup and suspend to avoid HDM timeout
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

  # Brief delay then suspend
  sleep 1
  systemctl suspend
) &
