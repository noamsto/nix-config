#!/usr/bin/env bash
# Toggle tmux session sidebar
# Creates or destroys a sidebar pane on the right showing session list

set -euo pipefail

SIDEBAR_WIDTH=40
SIDEBAR_TITLE="[sidebar]"

# Find existing sidebar pane by title
find_sidebar_pane() {
  local pane_id
  pane_id=$(tmux list-panes -F '#{pane_id}:#{pane_title}' 2>/dev/null |
    grep -F ":$SIDEBAR_TITLE" | head -n1 | cut -d: -f1)

  if [[ -n $pane_id ]]; then
    echo "$pane_id"
    return 0
  fi
  return 1
}

# Find sidebar pane across all windows in current session
find_sidebar_global() {
  local session
  session=$(tmux display-message -p '#{session_name}')

  local pane_target
  pane_target=$(tmux list-panes -s -t "$session" -F '#{window_id}:#{pane_id}:#{pane_title}' 2>/dev/null |
    grep -F ":$SIDEBAR_TITLE" | head -n1 | cut -d: -f1-2)

  if [[ -n $pane_target ]]; then
    echo "${pane_target/:/\.}"
    return 0
  fi
  return 1
}

# Close sidebar
close_sidebar() {
  local pane="$1"
  tmux kill-pane -t "$pane" 2>/dev/null || true
}

# Open sidebar
open_sidebar() {
  # Create a new pane on the right running the TUI
  # Use -P to get the new pane ID, then set its title
  local new_pane
  new_pane=$(tmux split-window -h -l "$SIDEBAR_WIDTH" -d -P -F '#{pane_id}' \
    "tmux-sidebar-tui")

  # Set the pane title for detection
  tmux select-pane -t "$new_pane" -T "$SIDEBAR_TITLE"
}

main() {
  # First check current window
  if sidebar_pane=$(find_sidebar_pane); then
    close_sidebar "$sidebar_pane"
    exit 0
  fi

  # Then check other windows in session (close remote sidebar)
  if sidebar_pane=$(find_sidebar_global); then
    close_sidebar "$sidebar_pane"
  fi

  # Open new sidebar in current window
  open_sidebar
}

main
