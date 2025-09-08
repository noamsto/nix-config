#!/usr/bin/env bash

# Simple power profile toggle script
# Cycles through performance -> balanced -> power-saver -> performance
# Manual changes are preserved until next AC adapter connect/disconnect

# Check if powerprofilesctl is available
if ! command -v powerprofilesctl >/dev/null 2>&1; then
  notify-send "Power Profile" "power-profiles-daemon not found" -i error
  exit 1
fi

# Get current power profile
current_profile=$(powerprofilesctl get 2>/dev/null || echo "unknown")

# Cycle to next profile
case "$current_profile" in
"performance")
  next_profile="balanced"
  icon="battery"
  message="Switched to Balanced"
  ;;
"balanced")
  next_profile="power-saver"
  icon="battery-caution"
  message="Switched to Power Saver"
  ;;
"power-saver" | *)
  next_profile="performance"
  icon="battery-full"
  message="Switched to Performance"
  ;;
esac

# Set the new profile directly
powerprofilesctl set "$next_profile"
notify-send "Power Profile" "$message\nWill reset when AC adapter changes" -i "$icon" -t 2000

# Brief delay to allow changes to take effect
sleep 0.5
