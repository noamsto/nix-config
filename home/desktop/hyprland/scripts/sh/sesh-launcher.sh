#!/usr/bin/env bash
# Sesh session launcher using vicinae dmenu
# Opens a terminal with the selected tmux session

set -euo pipefail

# Get sessions with grouping and icons
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

# Extract session name (last field after icons/formatting)
# Session name is typically the last word in the line
session_name=$(echo "$choice" | awk '{print $NF}')

# Open terminal with tmux session
# Using kitty as the terminal (adjust if using different terminal)
kitty --detach sh -c "tmux attach -t '$session_name' 2>/dev/null || sesh connect '$session_name'"
