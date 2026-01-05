#!/usr/bin/env bash
# Fullscreen toggle wrapper with hyperbars state refresh
#
# WORKAROUND for hyperbars showing on tiled windows after exiting fullscreen
# Related to closed Hyprland issue #3970 (bar zones not respected after fullscreen toggle)
# https://github.com/hyprwm/Hyprland/issues/3970
#
# Root cause: Window rules don't automatically re-evaluate when exiting fullscreen.
# The window returns to tiling state, but hyperbars decoration state doesn't refresh.
#
# This wrapper forces hyperbars to re-check the window's tiling state after toggling
# fullscreen, ensuring the "hyprbars:no_bar 1, match:float false" rule is applied.

# Get fullscreen mode: 1 = with gaps (focus mode), 0 = true fullscreen
MODE="${1:-1}"

# Toggle fullscreen
hyprctl dispatch fullscreen "$MODE"

# Small delay to let Hyprland update window state
sleep 0.05

# Get active window info
ACTIVE_WINDOW=$(hyprctl activewindow -j)
if [ -z "$ACTIVE_WINDOW" ] || [ "$ACTIVE_WINDOW" = "Invalid" ]; then
  exit 0
fi

# Check if window is floating
IS_FLOATING=$(echo "$ACTIVE_WINDOW" | jq -r '.floating')

# If window is tiled (not floating), explicitly disable hyperbars
# This ensures the window rule is re-applied after exiting fullscreen
if [ "$IS_FLOATING" = "false" ]; then
  WINDOW_ADDR=$(echo "$ACTIVE_WINDOW" | jq -r '.address')
  # Use hyprctl setprop to dynamically update the hyperbars state
  hyprctl setprop address:"$WINDOW_ADDR" plugin:hyprbars:no_bar 1
fi
