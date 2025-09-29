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

handle_lid_change() {
  local lid_status
  local monitor_setup

  lid_status=$(get_lid_status)
  monitor_setup=$(detect_monitors)

  log_message "Lid event detected - Status: $lid_status, Monitor setup: $monitor_setup"

  case "$lid_status" in
  "open")
    case "$monitor_setup" in
    "home") kanshictl switch home-docked-lid-open ;;
    "work") kanshictl switch work-docked-lid-open ;;
    "undocked") kanshictl switch undocked ;;
    esac
    ;;
  "closed")
    case "$monitor_setup" in
    "home") kanshictl switch home-docked-lid-close ;;
    "work") kanshictl switch work-docked-lid-close ;;
    "undocked") kanshictl switch undocked ;;
    esac
    ;;
  esac
}

# Initial state
log_message "Starting lid event monitoring"
handle_lid_change

# Monitor lid state file for changes using inotifywait
# Try both common lid paths
for lid_path in /proc/acpi/button/lid/LID/state /proc/acpi/button/lid/LID0/state; do
  if [[ -f $lid_path ]]; then
    log_message "Monitoring $lid_path for changes"
    inotifywait -m -e modify "$lid_path" --format '%w%f' 2>/dev/null |
      while read -r _; do
        handle_lid_change
      done
    break
  fi
done

# Fallback: if no lid file found, exit
log_message "No lid state file found, exiting"
exit 1
