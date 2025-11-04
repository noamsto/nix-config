#!/usr/bin/env bash
# Sesh session launcher using vicinae dmenu
# Opens a terminal with the selected tmux session

set -euo pipefail

# Get sessions with sesh's built-in icons (ANSI codes already stripped)
sessions=$(sesh-list-grouped 2>/dev/null)

if [[ -z $sessions ]]; then
  # No sessions available, show helpful message
  echo "No sessions available" | vicinae dmenu -p "Connect to Session" \
    --navigation-title "Tmux Sessions"
  exit 0
fi

# Show vicinae menu
choice=$(echo "$sessions" | vicinae dmenu -p "Connect to Session" \
  --navigation-title "Tmux Sessions" \
  --section-title "Available Sessions ({count})" || echo "")

# Exit if no choice made (user cancelled)
if [[ -z $choice ]]; then
  exit 0
fi

# Extract session name (sesh format: "icon session-name")
# sesh-list-grouped already stripped ANSI codes
# Remove icon (first field) to get session name
session_name=$(echo "$choice" | awk '{for(i=2;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}' | xargs)

# If extraction failed (no icon present), use whole string
if [[ -z $session_name ]]; then
  session_name=$(echo "$choice" | xargs)
fi

# Open terminal and let sesh handle connection
kitty --detach sh -c "sesh connect '$session_name'"
