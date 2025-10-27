#!/usr/bin/env bash
# Undocked - laptop screen only with lid-aware suspend behavior

# Reload Hyprland to apply new monitor configuration
hyprctl reload

# Check lid state
LID_STATE=$(cat /proc/acpi/button/lid/LID/state | awk '{print $2}')

if [ "$LID_STATE" = "closed" ]; then
  # Lid closed while undocked: suspend the system
  # Brief delay to ensure profile fully applied
  sleep 2
  systemctl suspend
  exit 0
fi

# Lid open: normal undocked configuration
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

# Focus workspace 1
hyprctl dispatch workspace 1

launch-dock &

# Start fingerprint daemon for undocked usage
systemctl start fprintd.service || true
