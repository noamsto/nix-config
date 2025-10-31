#!/usr/bin/env bash
# Work docked with lid open - dual Dell monitors + laptop screen

# Apply monitor configuration using fast hyprctl keyword commands
# (HDM links the config but Hyprland won't read it due to disable_autoreload=true)
hyprctl keyword monitor "desc:Dell Inc. DELL P2723DE CC7FH14,2560x1440@60,0x0,1.0" 2>/dev/null
hyprctl keyword monitor "desc:Dell Inc. DELL P2723DE 4C7FH14,2560x1440@60,2560x0,1.0" 2>/dev/null
hyprctl keyword monitor "eDP-1,2880x1800@120,1280x1440,2.0" 2>/dev/null

# Give monitors a moment to stabilize after configuration
sleep 0.5

# Load docked XWayland HiDPI settings (1.0 scale = 96 DPI for external monitors)
xrdb -merge ~/.Xresources.docked &

# Background the workspace setup to avoid blocking HDM
(
  # Small delay to ensure monitors are fully ready
  sleep 1

  # Make workspaces 5-8 persistent for dual monitor setup
  for ws in {5..8}; do
    hyprctl keyword workspace "$ws,persistent:true" 2>/dev/null || true
  done

  # Left monitor (Dell CC7FH14): workspaces 1-4
  for ws in {1..4}; do
    hyprctl dispatch workspace "$ws" 2>/dev/null || true
    hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Dell Inc. DELL P2723DE CC7FH14" 2>/dev/null || true
  done

  # Right monitor (Dell 4C7FH14): workspaces 5-8
  for ws in {5..8}; do
    hyprctl dispatch workspace "$ws" 2>/dev/null || true
    hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Dell Inc. DELL P2723DE 4C7FH14" 2>/dev/null || true
  done

  # Laptop screen: workspace 9
  hyprctl dispatch workspace 9 2>/dev/null || true
  hyprctl dispatch moveworkspacetomonitor 9 eDP-1 2>/dev/null || true

  # Return to workspace 1 on left monitor
  hyprctl dispatch workspace 1 2>/dev/null || true

) &

# Launch dock in background
launch-dock &

# Start fingerprint daemon when lid is open (in background)
systemctl start fprintd.service 2>/dev/null &
