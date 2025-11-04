#!/usr/bin/env bash
# List sessions with repository grouping and icons
# Reads .icon files from project roots and prepends to session names

set -euo pipefail

# Get all sessions (tmux + zoxide + config) with icons
sesh list -t -z -c --icons 2>/dev/null | while IFS= read -r line; do
  # Skip empty lines
  [[ -z $line ]] && continue

  # Try to extract a directory path from the line
  # Sesh output format varies, but typically: [icon] [name] [path]
  # For tmux sessions, the name is the session name
  # For zoxide, the name is the directory path

  # Extract last field as potential path
  last_field=$(echo "$line" | awk '{print $NF}')

  # Try to find git root and check for .icon file
  icon=""
  if [[ -d $last_field ]]; then
    # It's a directory (zoxide entry)
    git_root=$(git -C "$last_field" rev-parse --show-toplevel 2>/dev/null || echo "")
  elif tmux has-session -t "$last_field" 2>/dev/null; then
    # It's a tmux session - get its working directory
    session_path=$(tmux display-message -p -t "$last_field" -F "#{pane_current_path}" 2>/dev/null || echo "")
    git_root=$(git -C "$session_path" rev-parse --show-toplevel 2>/dev/null || echo "")
  else
    git_root=""
  fi

  # If we found a git root, check for .icon file
  if [[ -n $git_root ]] && [[ -f "$git_root/.icon" ]]; then
    icon=$(cat "$git_root/.icon" | head -n1 | tr -d '\n')
  fi

  # Output with icon prepended if found
  if [[ -n $icon ]]; then
    echo "$icon $line"
  else
    echo "$line"
  fi
done
