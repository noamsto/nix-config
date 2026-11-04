#!/bin/bash
set -euo pipefail

case "${1:-menu}" in
"wifi")
  wifi_status=$(rfkill list wifi | grep -i -o "Soft blocked: yes" || echo "")
  if [ -z "$wifi_status" ]; then
    rfkill block wifi
    notify-send -i network-wireless-offline "WiFi" "WiFi disabled" -t 1500
  else
    rfkill unblock wifi
    notify-send -i network-wireless-signal-excellent "WiFi" "WiFi enabled" -t 1500
  fi
  ;;
"bluetooth")
  bt_status=$(rfkill list bluetooth | grep -i -o "Soft blocked: yes" || echo "")
  if [ -z "$bt_status" ]; then
    rfkill block bluetooth
    notify-send -i bluetooth-disabled "Bluetooth" "Bluetooth disabled" -t 1500
  else
    rfkill unblock bluetooth
    notify-send -i bluetooth "Bluetooth" "Bluetooth enabled" -t 1500
  fi
  ;;
"night-mode")
  # Control hyprsunset via hyprctl commands
  # Check current state and toggle
  if hyprctl hyprsunset identity >/dev/null 2>&1; then
    notify-send -i weather-clear "Night Mode" "Night mode disabled" -t 1500
  else
    # Apply 3000K temperature filter
    hyprctl hyprsunset temperature 3000 >/dev/null 2>&1
    notify-send -i weather-clear-night "Night Mode" "Night mode enabled (3000K)" -t 1500
  fi
  ;;
"airplane")
  backup_file="$HOME/.cache/airplane_backup"
  if [ -e "$backup_file" ]; then
    # Restore from airplane mode
    rfkill unblock wifi bluetooth
    rm -f "$backup_file"
    notify-send -i airplane-mode-off "Airplane Mode" "Airplane mode disabled" -t 1500
  else
    # Enable airplane mode
    touch "$backup_file"
    rfkill block wifi bluetooth
    notify-send -i airplane-mode "Airplane Mode" "Airplane mode enabled" -t 1500
  fi
  ;;
"menu" | *)
  # Show toggle menu
  choice=$(echo -e "WiFi Toggle\nBluetooth Toggle\nNight Mode\nAirplane Mode" |
    vicinae dmenu -p "System Toggles")
  case "$choice" in
  "WiFi Toggle") system-toggles wifi ;;
  "Bluetooth Toggle") system-toggles bluetooth ;;
  "Night Mode") system-toggles night-mode ;;
  "Airplane Mode") system-toggles airplane ;;
  esac
  ;;
esac
