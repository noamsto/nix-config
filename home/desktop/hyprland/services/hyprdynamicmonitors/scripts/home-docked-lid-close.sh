#!/usr/bin/env bash
# Home docked with lid closed - dual Samsung monitors, laptop screen disabled

# Reload Hyprland to apply new monitor configuration
hyprctl reload

# Load docked XWayland HiDPI settings (1.0 scale = 96 DPI for external monitors)
xrdb -merge ~/.Xresources.docked

# Disable laptop screen for lid-close setup
hyprctl keyword monitor "eDP-1,disable"

# Left monitor (Samsung H4ZM300138): workspaces 1-4
for ws in {1..4}; do
  hyprctl dispatch workspace "$ws" && hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Samsung Electric Company S27H85x H4ZM300138" || true
done

# Right monitor (Samsung H4ZKB00167): workspaces 5-8
for ws in {5..8}; do
  hyprctl dispatch workspace "$ws" && hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Samsung Electric Company S27H85x H4ZKB00167" || true
done

# Make workspaces 5-8 persistent for dual monitor setup
for ws in {5..8}; do
  hyprctl keyword workspace "$ws,persistent:true" || true
done

launch-dock &

# Stop fingerprint daemon when lid is closed
systemctl stop fprintd.service || true
