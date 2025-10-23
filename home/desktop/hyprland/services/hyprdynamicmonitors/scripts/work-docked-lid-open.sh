#!/usr/bin/env bash
# Work docked with lid open - dual Dell monitors + laptop screen

# Load docked XWayland HiDPI settings (1.0 scale = 96 DPI for external monitors)
xrdb -merge ~/.Xresources.docked

# Enable laptop screen for lid-open setup
hyprctl keyword monitor "eDP-1,2880x1800@120,1280x1440,2.0"

# Make workspaces 5-8 persistent for dual monitor setup
for ws in {5..8}; do
  hyprctl keyword workspace "$ws,persistent:true" || true
done

# Left monitor (Dell CC7FH14): workspaces 1-4
for ws in {1..4}; do
  hyprctl dispatch workspace "$ws" && hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Dell Inc. DELL P2723DE CC7FH14" || true
done

# Right monitor (Dell 4C7FH14): workspaces 5-8
for ws in {5..8}; do
  hyprctl dispatch workspace "$ws" && hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Dell Inc. DELL P2723DE 4C7FH14" || true
done

# Laptop screen: workspace 9
hyprctl dispatch workspace 9 && hyprctl dispatch moveworkspacetomonitor 9 eDP-1 || true

launch-dock &

# Start fingerprint daemon when lid is open
systemctl start fprintd.service || true
