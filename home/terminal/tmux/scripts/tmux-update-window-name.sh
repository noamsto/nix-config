#!/usr/bin/env bash
# Update tmux pane title with branch + process name
# Called by tmux hooks to display branch info in prefix+W and status bar
# Usage: tmux-update-window-name <session_name> <window_index> <pane_current_path> <pane_current_command>

set -uo pipefail

session="$1"
window_index="$2"
pane_path="$3"
process="${4:-}"

# Get branch name (same logic as tmux-window-branch-display)
branch=$(tmux show-window-options -t "$session:$window_index" -v @branch 2>/dev/null || true)

if [[ -z $branch ]]; then
  branch=$(tmux show-options -t "$session" -v @branch 2>/dev/null || true)
fi

if [[ -z $branch ]] && [[ -n $pane_path ]] && [[ -d $pane_path ]]; then
  branch=$(git -C "$pane_path" branch --show-current 2>/dev/null || true)
fi

# Format pane title: branch (process) or just branch if no process
if [[ -n $branch ]]; then
  if [[ -n $process ]]; then
    pane_title="$branch ($process)"
  else
    pane_title="$branch"
  fi

  # Set the pane title (prefix+W will show this via tree-mode-format)
  tmux select-pane -t "$session:$window_index" -T "$pane_title" 2>/dev/null || true
fi

# Always exit successfully (hooks should never fail)
exit 0
