#!/usr/bin/env bash

# Browser URL opener that focuses the browser workspace
# Used as the default browser handler for xdg-open

BROWSER="firefox"
BROWSER_CLASS="firefox"

# Get the workspace where the browser is currently located
BROWSER_CURRENT_WORKSPACE=$(hyprctl clients -j | jq -r ".[] | select(.class == \"$BROWSER_CLASS\") | .workspace.id" | head -1)

# If browser is running, switch to its workspace
if [ -n "$BROWSER_CURRENT_WORKSPACE" ]; then
  # Switch to the browser's workspace
  hyprctl dispatch workspace "$BROWSER_CURRENT_WORKSPACE"
  # Focus the browser window
  hyprctl dispatch focuswindow "class:$BROWSER_CLASS"
fi

# Open the URL in the browser (will open in existing instance or start new one)
$BROWSER "$@" &
