#!/bin/bash
set -euo pipefail

# Screenshot helper script with automatic scaling detection and satty integration
# Usage: screenshot-helper.sh <type> [scale_factor]
# Types: area, output, screen, edit-area, edit-output, edit-screen

TYPE="$1"
SCALE_FACTOR="${2:-}"

# Function to get scale factor of focused monitor
get_focused_monitor_scale() {
    hyprctl monitors -j | jq -r '.[] | select(.focused) | .scale'
}

# Function to get scale factor of primary monitor (eDP-1 or first monitor)
get_primary_monitor_scale() {
    # Try to get eDP-1 scale first, fallback to first monitor
    local edp_scale=$(hyprctl monitors -j | jq -r '.[] | select(.name == "eDP-1") | .scale' 2>/dev/null || echo "null")
    if [ "$edp_scale" != "null" ] && [ -n "$edp_scale" ]; then
        echo "$edp_scale"
    else
        hyprctl monitors -j | jq -r '.[0].scale'
    fi
}

# Auto-detect scale factor if not provided
if [ -z "${SCALE_FACTOR:-}" ]; then
    case "$TYPE" in
    "area" | "edit-area")
        # For area selection, we don't know which monitor, so use focused monitor's scale
        SCALE_FACTOR=$(get_focused_monitor_scale)
        ;;
    "output" | "edit-output")
        # For full output, use primary monitor scale (or could be improved to detect all scales)
        SCALE_FACTOR=$(get_primary_monitor_scale)
        ;;
    "screen" | "edit-screen")
        # For active screen, use focused monitor's scale
        SCALE_FACTOR=$(get_focused_monitor_scale)
        ;;
    esac
fi

# Fallback to 1.0 if detection fails
SCALE_FACTOR="${SCALE_FACTOR:-1.0}"

case "$TYPE" in
"area")
    # Quick area screenshot with scaling
    hyprctl keyword animation "fadeOut,0,0,default"
    grimblast --notify --scale "$SCALE_FACTOR" copysave area
    hyprctl keyword animation "fadeOut,1,4,default"
    ;;
"output")
    # Full output screenshot with scaling
    grimblast --notify --cursor --scale "$SCALE_FACTOR" copysave output
    ;;
"screen")
    # Active screen screenshot with scaling
    grimblast --notify --cursor --scale "$SCALE_FACTOR" copysave screen
    ;;
"edit-area")
    # Screenshot area and edit with satty
    hyprctl keyword animation "fadeOut,0,0,default"
    GRIMBLAST_EDITOR=satty grimblast --scale "$SCALE_FACTOR" edit area
    hyprctl keyword animation "fadeOut,1,4,default"
    ;;
"edit-output")
    # Screenshot full output and edit with satty
    GRIMBLAST_EDITOR=satty grimblast --cursor --scale "$SCALE_FACTOR" edit output
    ;;
"edit-screen")
    # Screenshot active screen and edit with satty
    GRIMBLAST_EDITOR=satty grimblast --cursor --scale "$SCALE_FACTOR" edit screen
    ;;
*)
    echo "Usage: $0 {area|output|screen|edit-area|edit-output|edit-screen} [scale_factor]"
    echo "If scale_factor is not provided, it will be auto-detected from active monitor"
    exit 1
    ;;
esac
