#!/usr/bin/env bash
# Home docked with lid open - dual Samsung monitors + laptop screen

# Reload Hyprland to apply new monitor configuration
hyprctl reload

# Load docked XWayland HiDPI settings (1.0 scale = 96 DPI for external monitors)
xrdb -merge ~/.Xresources.docked

# Enable laptop screen for lid-open setup
hyprctl keyword monitor "eDP-1,2880x1800@120,2560x1440,2.0"

# Make workspaces 5-8 persistent for dual monitor setup
for ws in {5..8}; do
  hyprctl keyword workspace "$ws,persistent:true" || true
done

# Left monitor (Samsung H4ZM300138): workspaces 1-4
for ws in {1..4}; do
  hyprctl dispatch workspace "$ws" && hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Samsung Electric Company S27H85x H4ZM300138" || true
done

# Right monitor (Samsung H4ZKB00167): workspaces 5-8
for ws in {5..8}; do
  hyprctl dispatch workspace "$ws" && hyprctl dispatch moveworkspacetomonitor "$ws" "desc:Samsung Electric Company S27H85x H4ZKB00167" || true
done

# Laptop screen: workspace 9
hyprctl dispatch workspace 9 && hyprctl dispatch moveworkspacetomonitor 9 eDP-1 || true

launch-dock &

# Start fingerprint daemon when lid is open
systemctl start fprintd.service || true
