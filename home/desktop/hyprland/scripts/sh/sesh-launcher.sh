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

# Extract session name from format: [icon] session-name (type)
# Remove everything after and including the opening parenthesis
session_name=$(echo "$choice" | sed 's/ *(.*$//' | awk '{print $NF}')

# Determine if it's a tmux session or directory
if [[ $choice == *"(tmux)"* ]]; then
  # It's an existing tmux session - attach to it
  kitty --detach sh -c "tmux attach -t '$session_name'"
else
  # It's a directory - create new session
  kitty --detach sh -c "sesh connect '$session_name'"
fi
