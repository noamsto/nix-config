#!/usr/bin/env bash

# Custom keyboard layout indicator for waybar with Hebrew support
# This script monitors the current keyboard layout and outputs JSON for waybar

get_layout() {
  # Get current keyboard layout from xremap device specifically
  layout=$(hyprctl devices -j | jq -r '.keyboards[] | select(.name == "xremap") | .active_keymap' 2>/dev/null)

  # If xremap not found, fallback to physical keyboard
  if [ -z "$layout" ] || [ "$layout" = "null" ]; then
    layout=$(hyprctl devices -j | jq -r '.keyboards[] | select(.name == "at-translated-set-2-keyboard") | .active_keymap' 2>/dev/null)
  fi

  # If still no layout found, try to get it from hyprctl directly
  if [ -z "$layout" ] || [ "$layout" = "null" ]; then
    layout=$(hyprctl getoption input:kb_layout | grep -o '".*"' | tr -d '"' 2>/dev/null || echo "unknown")
  fi

  # Map layout names to short display names
  case "$layout" in
  *"English"* | *"english"* | *"US"* | *"us"*)
    echo "EN"
    ;;
  *"Hebrew"* | *"hebrew"* | *"il"* | *"IL"*)
    echo "עב"
    ;;
  *)
    # Try to extract first 2 letters of layout name
    echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]'
    ;;
  esac
}

output_layout() {
  local layout="$1"
  local tooltip="Keyboard layout: $layout"

  # Add click hint to tooltip
  if [ "$layout" = "EN" ]; then
    tooltip="$tooltip\nClick to switch to Hebrew"
  elif [ "$layout" = "עב" ]; then
    tooltip="$tooltip\nClick to switch to English"
  fi

  echo "{\"text\": \"$layout\", \"tooltip\": \"$tooltip\", \"class\": \"keyboard-layout-$layout\"}"
}

# Output initial state
layout=$(get_layout)
output_layout "$layout"

# Monitor for layout changes using socat from XDG_RUNTIME_DIR
# This will update immediately when layout changes
socat -u UNIX-CONNECT:"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/hypr/"$HYPRLAND_INSTANCE_SIGNATURE"/.socket2.sock - 2>/dev/null | while read -r line; do
  if [[ $line == *"activelayout"* ]]; then
    layout=$(get_layout)
    output_layout "$layout"
  fi
done
