#!/usr/bin/env bash

# Power profile toggle script for waybar
# Cycles through power-profiles-daemon profiles manually

# Check if powerprofilesctl is available
if ! command -v powerprofilesctl >/dev/null 2>&1; then
  notify-send "Power Profile" "power-profiles-daemon not found" -i error
  exit 1
fi

# Get current power profile
current_profile=$(powerprofilesctl get 2>/dev/null || echo "unknown")

# Cycle through profiles: performance -> balanced -> power-saver -> performance
case "$current_profile" in
"performance")
  # Switch to balanced
  powerprofilesctl set balanced
  notify-send "Power Profile" "Switched to Balanced (Manual Override)" -i battery -t 2000
  ;;
"balanced")
  # Switch to power-saver
  powerprofilesctl set power-saver
  notify-send "Power Profile" "Switched to Power Saver (Manual Override)" -i battery-caution -t 2000
  ;;
"power-saver" | *)
  # Switch to performance (or default if unknown)
  powerprofilesctl set performance
  notify-send "Power Profile" "Switched to Performance (Manual Override)" -i battery-full -t 2000
  ;;
esac

# Brief delay to allow changes to take effect
sleep 0.5
