#!/usr/bin/env bash
# Work docked - dual Dell monitors with lid-aware configuration

# Reload Hyprland to apply new monitor configuration
hyprctl reload

# Check lid state
LID_STATE=$(cat /proc/acpi/button/lid/LID/state | awk '{print $2}')

# Load docked XWayland HiDPI settings (1.0 scale = 96 DPI for external monitors)
xrdb -merge ~/.Xresources.docked

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

# Lid-aware laptop screen configuration
if [ "$LID_STATE" = "open" ]; then
  # Laptop screen: workspace 9 (only when lid is open)
  hyprctl dispatch workspace 9 && hyprctl dispatch moveworkspacetomonitor 9 eDP-1 || true

  # Start fingerprint daemon when lid is open
  systemctl start fprintd.service || true
else
  # Lid closed: ensure workspace 9 is not persistent
  hyprctl keyword workspace "9,persistent:false" || true
fi

launch-dock &
