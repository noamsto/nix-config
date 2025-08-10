#!/usr/bin/env bash

# Unified brightness control script for internal and external monitors
# Usage: brightness-control.sh [up|down|set] [value]

# Minimum brightness percentages
MIN_BRIGHTNESS_INTERNAL=5
MIN_BRIGHTNESS_EXTERNAL=10

# Function to check if ddcutil is available and working
check_ddcutil() {
  command -v ddcutil >/dev/null 2>&1 && ddcutil detect >/dev/null 2>&1
}

# Function to get current internal brightness percentage
get_internal_brightness() {
  brightnessctl get | awk '{print int($1)}'
}

# Function to get maximum internal brightness
get_internal_max_brightness() {
  brightnessctl max | awk '{print int($1)}'
}

# Function to get current internal brightness as percentage
get_internal_brightness_percent() {
  local current
  local max
  current=$(get_internal_brightness)
  max=$(get_internal_max_brightness)
  echo $((current * 100 / max))
}

# Function to get current external brightness percentage
get_external_brightness() {
  local display=$1
  ddcutil getvcp 10 --display "$display" 2>/dev/null | grep -o 'current value = [0-9]*' | awk '{print $4}'
}

# Function to adjust brightness
adjust_brightness() {
  local action=$1
  local value=${2:-5}

  # Handle internal display with brightnessctl
  case "$action" in
  up)
    brightnessctl set "+${value}%"
    ;;
  down)
    local current_percent=$(get_internal_brightness_percent)
    local new_percent=$((current_percent - value))

    if [ "$new_percent" -lt "$MIN_BRIGHTNESS_INTERNAL" ]; then
      echo "Warning: Cannot decrease internal brightness below ${MIN_BRIGHTNESS_INTERNAL}%"
      brightnessctl set "${MIN_BRIGHTNESS_INTERNAL}%"
    else
      brightnessctl set "${value}%-"
    fi
    ;;
  set)
    if [ "$value" -lt "$MIN_BRIGHTNESS_INTERNAL" ]; then
      echo "Warning: Setting internal brightness to minimum ${MIN_BRIGHTNESS_INTERNAL}% instead of ${value}%"
      brightnessctl set "${MIN_BRIGHTNESS_INTERNAL}%"
    else
      brightnessctl set "${value}%"
    fi
    ;;
  esac

  # Handle external displays with ddcutil if available
  if check_ddcutil; then
    # Get list of detected displays
    displays=$(ddcutil detect | grep "Display" | awk '{print $2}')

    if [ -n "$displays" ]; then
      for display in $displays; do
        case "$action" in
        up)
          ddcutil setvcp 10 + "$value" --display "$display" 2>/dev/null &
          ;;
        down)
          # Get current brightness for this external display
          current_brightness=$(get_external_brightness "$display")
          if [ -n "$current_brightness" ]; then
            new_brightness=$((current_brightness - value))

            if [ "$new_brightness" -lt "$MIN_BRIGHTNESS_EXTERNAL" ]; then
              echo "Warning: Cannot decrease external display $display brightness below ${MIN_BRIGHTNESS_EXTERNAL}%"
              ddcutil setvcp 10 "$MIN_BRIGHTNESS_EXTERNAL" --display "$display" 2>/dev/null &
            else
              ddcutil setvcp 10 - "$value" --display "$display" 2>/dev/null &
            fi
          else
            # Fallback if we can't get current brightness
            ddcutil setvcp 10 - "$value" --display "$display" 2>/dev/null &
          fi
          ;;
        set)
          if [ "$value" -lt "$MIN_BRIGHTNESS_EXTERNAL" ]; then
            echo "Warning: Setting external display $display brightness to minimum ${MIN_BRIGHTNESS_EXTERNAL}% instead of ${value}%"
            ddcutil setvcp 10 "$MIN_BRIGHTNESS_EXTERNAL" --display "$display" 2>/dev/null &
          else
            ddcutil setvcp 10 "$value" --display "$display" 2>/dev/null &
          fi
          ;;
        esac
      done

      # Wait for all background ddcutil commands to complete
      wait
    fi
  fi
}

# Main script logic
case "${1:-}" in
up | down | set)
  adjust_brightness "$1" "$2"
  ;;
*)
  echo "Usage: $0 [up|down|set] [value]"
  echo "  up   - Increase brightness by value% (default: 5)"
  echo "  down - Decrease brightness by value% (default: 5)"
  echo "  set  - Set brightness to value%"
  exit 1
  ;;
esac
