#!/usr/bin/env bash

# Smart browser launcher that focuses existing browser or opens new one in current workspace

BROWSER="brave"
BROWSER_CLASS="Brave-browser"

# Get current workspace
CURRENT_WORKSPACE=$(hyprctl activewindow | grep workspace | awk '{print $2}')

# Check if browser is already running in current workspace
BROWSER_IN_CURRENT=$(hyprctl clients | grep -A10 "class: $BROWSER_CLASS" | grep "workspace: $CURRENT_WORKSPACE")

if [ -n "$BROWSER_IN_CURRENT" ]; then
  # Focus existing browser in current workspace
  hyprctl dispatch focuswindow "class:$BROWSER_CLASS"
else
  # Check if browser is running anywhere else
  if hyprctl clients | grep -q "class: $BROWSER_CLASS"; then
    # Browser exists elsewhere, bring it to current workspace
    hyprctl dispatch movetoworkspace "$CURRENT_WORKSPACE,class:$BROWSER_CLASS"
    hyprctl dispatch focuswindow "class:$BROWSER_CLASS"
  else
    # No browser running, start new one
    $BROWSER "$@" &
  fi
fi
