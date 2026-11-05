#!/usr/bin/env bash

# Unified brightness control script for internal and external monitors
# Usage: brightness-control.sh [--get|--inc|--dec|--set] [value]

# Configuration
MIN_BRIGHTNESS_INTERNAL=5
MIN_BRIGHTNESS_EXTERNAL=10
STEP_SIZE=5
iDIR="${HOME}/.config/swaync/icons"

# Get current brightness percentage using brightnessctl -m format
get_brightness() {
  brightnessctl -m | cut -d, -f4
}

# Get appropriate brightness icon based on current level
get_icon() {
  local current
  current=$(get_brightness | sed 's/%//')
  if [ "$current" -le "20" ]; then
    echo "$iDIR/brightness-20.png"
  elif [ "$current" -le "40" ]; then
    echo "$iDIR/brightness-40.png"
  elif [ "$current" -le "60" ]; then
    echo "$iDIR/brightness-60.png"
  elif [ "$current" -le "80" ]; then
    echo "$iDIR/brightness-80.png"
  else
    echo "$iDIR/brightness-100.png"
  fi
}

# Function to check if ddcutil is available and working
check_ddcutil() {
  command -v ddcutil >/dev/null 2>&1 && timeout 2s ddcutil detect >/dev/null 2>&1
}

# Function to get external displays
get_external_displays() {
  if check_ddcutil; then
    ddcutil detect 2>/dev/null | grep "Display" | awk '{print $2}' | head -5 # Limit to 5 displays max
  fi
}

# Function to get current external brightness percentage for a display
get_external_brightness() {
  local display=$1
  timeout 2s ddcutil getvcp 10 --display "$display" 2>/dev/null | grep -o 'current value = [0-9]*' | awk '{print $4}'
}

# Function to get unified brightness (average of all displays)
get_unified_brightness() {
  local internal_brightness
  local total_brightness=0
  local display_count=0

  # Get internal brightness
  internal_brightness=$(get_brightness | sed 's/%//')
  if [ -n "$internal_brightness" ] && [ "$internal_brightness" -gt 0 ]; then
    total_brightness=$internal_brightness
    display_count=1
  fi

  # Get external brightness from all displays
  local displays
  displays=$(get_external_displays)
  if [ -n "$displays" ]; then
    for display in $displays; do
      local ext_brightness
      ext_brightness=$(get_external_brightness "$display")
      if [ -n "$ext_brightness" ] && [ "$ext_brightness" -ge 0 ]; then
        total_brightness=$((total_brightness + ext_brightness))
        display_count=$((display_count + 1))
      fi
    done
  fi

  if [ "$display_count" -gt 0 ]; then
    echo $((total_brightness / display_count))
  else
    echo "0"
  fi
}

# Function to set external monitor brightness with error handling
set_external_brightness() {
  local display=$1
  local action=$2
  local value=$3

  case "$action" in
  "inc")
    timeout 2s ddcutil setvcp 10 + "$value" --display "$display" 2>/dev/null
    ;;
  "dec")
    # Get current brightness to check minimum
    local current
    current=$(get_external_brightness "$display")
    if [ -n "$current" ] && [ $((current - value)) -lt $MIN_BRIGHTNESS_EXTERNAL ]; then
      timeout 2s ddcutil setvcp 10 "$MIN_BRIGHTNESS_EXTERNAL" --display "$display" 2>/dev/null
    else
      timeout 2s ddcutil setvcp 10 - "$value" --display "$display" 2>/dev/null
    fi
    ;;
  "set")
    if [ "$value" -lt "$MIN_BRIGHTNESS_EXTERNAL" ]; then
      value=$MIN_BRIGHTNESS_EXTERNAL
    fi
    timeout 2s ddcutil setvcp 10 "$value" --display "$display" 2>/dev/null
    ;;
  esac
}

# Main brightness change function with synchronized control
change_brightness() {
  local action=$1
  local step=${2:-$STEP_SIZE}

  # Handle internal display first
  case "$action" in
  inc)
    brightnessctl set "+${step}%"
    ;;
  dec)
    # Check minimum brightness before decreasing
    local current
    current=$(get_brightness | sed 's/%//')
    local new_value=$((current - step))

    if [ "$new_value" -lt "$MIN_BRIGHTNESS_INTERNAL" ]; then
      brightnessctl set "${MIN_BRIGHTNESS_INTERNAL}%"
    else
      brightnessctl set "${step}%-"
    fi
    ;;
  set)
    local value=$step
    if [ "$value" -lt "$MIN_BRIGHTNESS_INTERNAL" ]; then
      value=$MIN_BRIGHTNESS_INTERNAL
    fi
    brightnessctl set "${value}%"
    ;;
  esac

  # Handle external displays synchronously
  local displays
  displays=$(get_external_displays)
  if [ -n "$displays" ]; then
    for display in $displays; do
      set_external_brightness "$display" "$action" "$step"
    done
  fi
}

# Execute accordingly (following hyprdots pattern)
case "$1" in
"--get")
  get_brightness
  ;;
"--get-unified")
  echo "$(get_unified_brightness)%"
  ;;
"--inc")
  change_brightness "inc" "${2:-$STEP_SIZE}"
  ;;
"--dec")
  change_brightness "dec" "${2:-$STEP_SIZE}"
  ;;
"--set")
  change_brightness "set" "$2"
  ;;
"--get-icon")
  get_icon
  ;;
# Legacy support for existing bindings
"up")
  change_brightness "inc" "${2:-$STEP_SIZE}"
  ;;
"down")
  change_brightness "dec" "${2:-$STEP_SIZE}"
  ;;
"set")
  change_brightness "set" "$2"
  ;;
*)
  echo "Usage: $0 [--get|--get-unified|--inc|--dec|--set|--get-icon] [value]"
  echo "  --get         - Get current internal brightness percentage"
  echo "  --get-unified - Get average brightness across all displays"
  echo "  --inc         - Increase brightness by value% (default: 5)"
  echo "  --dec         - Decrease brightness by value% (default: 5)"
  echo "  --set         - Set brightness to value%"
  echo "  --get-icon    - Get appropriate brightness icon path"
  echo ""
  echo "Legacy support:"
  echo "  up/down/set   - Same as --inc/--dec/--set"
  exit 1
  ;;
esac
