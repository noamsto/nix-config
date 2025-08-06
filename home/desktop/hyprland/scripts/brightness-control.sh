#!/usr/bin/env bash

# Unified brightness control script for internal and external monitors
# Usage: brightness-control.sh [up|down|set] [value]

# Function to check if ddcutil is available and working
check_ddcutil() {
    command -v ddcutil >/dev/null 2>&1 && ddcutil detect >/dev/null 2>&1
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
        brightnessctl set "${value}%-"
        ;;
    set)
        brightnessctl set "${value}%"
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
                    ddcutil setvcp 10 - "$value" --display "$display" 2>/dev/null &
                    ;;
                set)
                    ddcutil setvcp 10 "$value" --display "$display" 2>/dev/null &
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
