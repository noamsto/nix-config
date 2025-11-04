#!/usr/bin/env bash
# Sesh session launcher using vicinae dmenu
# Opens a terminal with the selected tmux session

set -euo pipefail

# Helper to strip ANSI codes
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# Get sessions with sesh's built-in icons
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

# Strip ANSI codes and extract session name (sesh format: "icon session-name")
clean_choice=$(strip_ansi <<<"$choice")

# Remove icon (first field) to get session name
session_name=$(echo "$clean_choice" | awk '{for(i=2;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}' | xargs)

# If extraction failed, use the whole thing
if [[ -z $session_name ]]; then
  session_name=$(echo "$clean_choice" | xargs)
fi

# Open terminal and let sesh handle connection
kitty --detach sh -c "sesh connect '$session_name'"
