#!/bin/bash

log_message() {
  logger -t "kanshi-lid-event" "$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

get_lid_status() {
  # Check both common lid paths
  for lid_path in /proc/acpi/button/lid/LID/state /proc/acpi/button/lid/LID0/state; do
    if [[ -f $lid_path ]]; then
      if grep -q open "$lid_path"; then
        echo "open"
        return
      else
        echo "closed"
        return
      fi
    fi
  done
  echo "unknown"
}

detect_monitors() {
  monitors=$(hyprctl monitors)
  if echo "$monitors" | grep -q "Samsung Electric Company S27H85x"; then
    echo "home"
  elif echo "$monitors" | grep -q "Dell Inc. DELL P2723DE"; then
    echo "work"
  else
    echo "undocked"
  fi
}

handle_lid_event() {
  local event="$1"
  local monitor_setup

  monitor_setup=$(detect_monitors)
  log_message "Lid $event - Monitor setup: $monitor_setup"

  case "$event" in
  "open")
    # Always enable eDP-1 when lid opens
    hyprctl keyword monitor "eDP-1,2880x1800@120,auto,2.0" || true

    case "$monitor_setup" in
    "home") kanshictl switch home-docked-lid-open ;;
    "work") kanshictl switch work-docked-lid-open ;;
    "undocked") kanshictl switch undocked ;;
    esac
    ;;
  "close")
    case "$monitor_setup" in
    "home" | "work")
      # Only disable eDP-1 if external monitors are present
      if hyprctl monitors | grep -q 'DP-\|HDMI-'; then
        hyprctl keyword monitor "eDP-1,disable" || true
        if [ "$monitor_setup" = "home" ]; then
          kanshictl switch home-docked-lid-close
        else
          kanshictl switch work-docked-lid-close
        fi
      else
        log_message "External monitors not detected, keeping eDP-1 enabled"
        kanshictl switch undocked
      fi
      ;;
    "undocked")
      # Never disable eDP-1 when undocked
      log_message "Undocked - keeping eDP-1 enabled"
      kanshictl switch undocked
      ;;
    esac
    ;;
  esac
}

# Initial state - handle current lid status
log_message "Starting lid event monitoring"
initial_lid_status=$(get_lid_status)
handle_lid_event "$initial_lid_status"

# Monitor systemd-logind for lid switch events via D-Bus
log_message "Starting D-Bus monitoring for lid events"
gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 2>/dev/null |
  while read -r line; do
    if echo "$line" | grep -q "LidClosed.*true"; then
      handle_lid_event "close"
    elif echo "$line" | grep -q "LidClosed.*false"; then
      handle_lid_event "open"
    fi
  done

# Fallback: if D-Bus monitoring fails, exit
log_message "D-Bus monitoring failed, exiting"
exit 1
