#!/usr/bin/env bash

# Custom keyboard layout indicator for waybar with Hebrew support
# This script monitors the current keyboard layout and outputs JSON for waybar

get_layout() {
    # Get current keyboard layout from hyprctl
    layout=$(hyprctl devices -j | jq -r '.keyboards[] | select(.name == "at-translated-set-2-keyboard") | .active_keymap' 2>/dev/null || echo "unknown")
    
    # Map layout names to short display names
    case "$layout" in
        *"English"*|*"english"*|*"US"*|*"us"*)
            echo "EN"
            ;;
        *"Hebrew"*|*"hebrew"*|*"il"*|*"IL"*)
            echo "עב"
            ;;
        *)
            # Try to extract first 2 letters of layout name
            echo "${layout:0:2}" | tr '[:lower:]' '[:upper:]'
            ;;
    esac
}

# Output JSON for waybar
while true; do
    layout=$(get_layout)
    tooltip="Keyboard layout: $layout"
    
    # Add click hint to tooltip
    if [ "$layout" = "EN" ]; then
        tooltip="$tooltip\nClick to switch to Hebrew"
    elif [ "$layout" = "עב" ]; then
        tooltip="$tooltip\nClick to switch to English"
    fi
    
    echo "{\"text\": \"$layout\", \"tooltip\": \"$tooltip\", \"class\": \"keyboard-layout-$layout\"}"
    
    # Monitor for layout changes using socat
    # This will update immediately when layout changes
    socat -u UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - 2>/dev/null | while read -r line; do
        if [[ "$line" == *"activelayout"* ]]; then
            layout=$(get_layout)
            tooltip="Keyboard layout: $layout"
            
            if [ "$layout" = "EN" ]; then
                tooltip="$tooltip\nClick to switch to Hebrew"
            elif [ "$layout" = "עב" ]; then
                tooltip="$tooltip\nClick to switch to English"
            fi
            
            echo "{\"text\": \"$layout\", \"tooltip\": \"$tooltip\", \"class\": \"keyboard-layout-$layout\"}"
        fi
    done
done