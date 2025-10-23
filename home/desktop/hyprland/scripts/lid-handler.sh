#!/usr/bin/env bash
# Lid event handler for Hyprland - handles spurious keyboard events
# Checks actual ACPI state instead of trusting event type

STATEFILE="/tmp/hypr-lid-last-state"

# Read ACTUAL lid state from ACPI (source of truth)
ACPI_STATE=$(cat /proc/acpi/button/lid/LID/state | awk '{print $2}')

# Check if state actually changed since last run
LAST_STATE=$(cat "$STATEFILE" 2>/dev/null || echo "unknown")

if [ "$ACPI_STATE" = "$LAST_STATE" ]; then
  # State hasn't changed - spurious event from keyboard, ignore it
  exit 0
fi

# Save new state
echo "$ACPI_STATE" >"$STATEFILE"

# Get current connected monitors
MONITORS=$(hyprctl monitors -j | jq -r '.[].description')
HAS_SAMSUNG=$(echo "$MONITORS" | grep -c "Samsung Electric Company S27H85x")
HAS_DELL=$(echo "$MONITORS" | grep -c "Dell Inc. DELL P2723DE")

if [ "$ACPI_STATE" = "closed" ]; then
  # Lid is actually closed
  if [ "$HAS_SAMSUNG" -eq 2 ]; then
    ln -sf ~/.config/hypr/hyprdynamicmonitors/profiles/home-docked-lid-close.conf ~/.config/hypr/monitors.conf
    hyprctl reload
    notify-send "Monitor Profile" "Home Docked (Lid Closed)" -t 3000
  elif [ "$HAS_DELL" -eq 2 ]; then
    ln -sf ~/.config/hypr/hyprdynamicmonitors/profiles/work-docked-lid-close.conf ~/.config/hypr/monitors.conf
    hyprctl reload
    notify-send "Monitor Profile" "Work Docked (Lid Closed)" -t 3000
  else
    # No external monitors - suspend
    ln -sf ~/.config/hypr/hyprdynamicmonitors/profiles/undocked-lid-closed.conf ~/.config/hypr/monitors.conf
    notify-send "Suspending" "No external monitors" -t 2000
    sleep 2
    systemctl suspend
  fi
else
  # Lid is actually open
  if [ "$HAS_SAMSUNG" -eq 2 ]; then
    ln -sf ~/.config/hypr/hyprdynamicmonitors/profiles/home-docked-lid-open.conf ~/.config/hypr/monitors.conf
    hyprctl reload
    # Move workspaces 9-10 back to laptop screen
    hyprctl dispatch moveworkspacetomonitor 9 eDP-1
    hyprctl dispatch moveworkspacetomonitor 10 eDP-1
    notify-send "Monitor Profile" "Home Docked (Lid Open)" -t 3000
  elif [ "$HAS_DELL" -eq 2 ]; then
    ln -sf ~/.config/hypr/hyprdynamicmonitors/profiles/work-docked-lid-open.conf ~/.config/hypr/monitors.conf
    hyprctl reload
    # Move workspaces 9-10 back to laptop screen
    hyprctl dispatch moveworkspacetomonitor 9 eDP-1
    hyprctl dispatch moveworkspacetomonitor 10 eDP-1
    notify-send "Monitor Profile" "Work Docked (Lid Open)" -t 3000
  else
    ln -sf ~/.config/hypr/hyprdynamicmonitors/profiles/undocked.conf ~/.config/hypr/monitors.conf
    hyprctl reload
    notify-send "Monitor Profile" "Undocked" -t 3000
  fi
fi
