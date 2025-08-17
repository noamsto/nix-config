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
    echo $(brightnessctl -m | cut -d, -f4)
}

# Get appropriate brightness icon based on current level
get_icon() {
    local current=$(get_brightness | sed 's/%//')
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

# Function to send brightness notification with progress bar
send_brightness_notification() {
    local brightness_percent=$(get_brightness | sed 's/%//')
    local icon=$(get_icon)

    # Use same notification system as hyprdots for consistency
    notify-send -e -h string:x-canonical-private-synchronous:brightness_notif \
        -h int:value:"$brightness_percent" \
        -u low \
        -i "$icon" \
        " Brightness: ${brightness_percent}%"
}

# Function to check if ddcutil is available and working
check_ddcutil() {
    command -v ddcutil >/dev/null 2>&1 && ddcutil detect >/dev/null 2>&1
}

# Function to get current external brightness percentage
get_external_brightness() {
    local display=$1
    ddcutil getvcp 10 --display "$display" 2>/dev/null | grep -o 'current value = [0-9]*' | awk '{print $4}'
}

# Change brightness function (simplified from hyprdots approach)
change_brightness() {
    local action=$1
    local step=${2:-$STEP_SIZE}

    case "$action" in
    inc)
        brightnessctl set "+${step}%" && get_icon && send_brightness_notification
        ;;
    dec)
        # Check minimum brightness before decreasing
        local current=$(get_brightness | sed 's/%//')
        local new_value=$((current - step))

        if [ "$new_value" -lt "$MIN_BRIGHTNESS_INTERNAL" ]; then
            brightnessctl set "${MIN_BRIGHTNESS_INTERNAL}%" && get_icon && send_brightness_notification
        else
            brightnessctl set "${step}%-" && get_icon && send_brightness_notification
        fi
        ;;
    set)
        local value=$step
        if [ "$value" -lt "$MIN_BRIGHTNESS_INTERNAL" ]; then
            echo "Warning: Setting brightness to minimum ${MIN_BRIGHTNESS_INTERNAL}%"
            brightnessctl set "${MIN_BRIGHTNESS_INTERNAL}%" && get_icon && send_brightness_notification
        else
            brightnessctl set "${value}%" && get_icon && send_brightness_notification
        fi
        ;;
    esac

    # Handle external displays with ddcutil if available
    if check_ddcutil; then
        displays=$(ddcutil detect | grep "Display" | awk '{print $2}')

        if [ -n "$displays" ]; then
            for display in $displays; do
                case "$action" in
                inc)
                    ddcutil setvcp 10 + "$step" --display "$display" 2>/dev/null &
                    ;;
                dec)
                    current_brightness=$(get_external_brightness "$display")
                    if [ -n "$current_brightness" ] && [ "$((current_brightness - step))" -lt "$MIN_BRIGHTNESS_EXTERNAL" ]; then
                        ddcutil setvcp 10 "$MIN_BRIGHTNESS_EXTERNAL" --display "$display" 2>/dev/null &
                    else
                        ddcutil setvcp 10 - "$step" --display "$display" 2>/dev/null &
                    fi
                    ;;
                set)
                    local value=$step
                    if [ "$value" -lt "$MIN_BRIGHTNESS_EXTERNAL" ]; then
                        ddcutil setvcp 10 "$MIN_BRIGHTNESS_EXTERNAL" --display "$display" 2>/dev/null &
                    else
                        ddcutil setvcp 10 "$value" --display "$display" 2>/dev/null &
                    fi
                    ;;
                esac
            done
            wait
        fi
    fi
}

# Execute accordingly (following hyprdots pattern)
case "$1" in
"--get")
    get_brightness
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
    echo "Usage: $0 [--get|--inc|--dec|--set|--get-icon] [value]"
    echo "  --get      - Get current brightness percentage"
    echo "  --inc      - Increase brightness by value% (default: 5)"
    echo "  --dec      - Decrease brightness by value% (default: 5)"
    echo "  --set      - Set brightness to value%"
    echo "  --get-icon - Get appropriate brightness icon path"
    echo ""
    echo "Legacy support:"
    echo "  up/down/set - Same as --inc/--dec/--set"
    exit 1
    ;;
esac
