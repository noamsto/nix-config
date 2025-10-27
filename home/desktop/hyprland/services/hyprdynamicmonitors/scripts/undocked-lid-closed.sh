#!/usr/bin/env bash
# Undocked with lid closed - configure then suspend

# Reload Hyprland to apply new monitor configuration
hyprctl reload

# Load laptop XWayland HiDPI settings (2.0 scale = 192 DPI)
xrdb -merge ~/.Xresources.laptop

# Reset workspace persistence
for ws in {5..10}; do
  hyprctl keyword workspace "$ws,persistent:false" || true
done

# Move workspaces 1-4 to laptop screen
for ws in {1..4}; do
  hyprctl dispatch workspace "$ws" && hyprctl dispatch moveworkspacetomonitor "$ws" eDP-1 || true
done

# Brief delay to ensure profile fully applied
sleep 2

# Suspend the system
systemctl suspend
