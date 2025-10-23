#!/usr/bin/env bash
# Work docked with lid closed - dual Dell monitors, laptop screen disabled

# Load docked XWayland HiDPI settings (1.0 scale = 96 DPI for external monitors)
xrdb -merge ~/.Xresources.docked

# Disable laptop screen for lid-close setup
hyprctl keyword monitor "eDP-1,disable"

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

launch-dock &

# Stop fingerprint daemon when lid is closed
systemctl stop fprintd.service || true
