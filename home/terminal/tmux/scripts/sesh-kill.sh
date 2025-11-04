#!/usr/bin/env bash
# Delete session with confirmation
# Usage: sesh-kill [session-name]

set -euo pipefail

session="${1:-}"

if [[ -z $session ]]; then
  # Show picker if no session specified
  session=$(sesh list -t --icons | fzf --prompt="Kill session: " --height=50% --border --ansi || echo "")

  if [[ -z $session ]]; then
    echo "No session selected"
    exit 0
  fi

  # Extract session name (remove icons and formatting)
  session=$(echo "$session" | awk '{print $NF}')
fi

# Confirm deletion
echo "Kill session '$session'? (y/N)"
read -r response

if [[ $response =~ ^[Yy]$ ]]; then
  if tmux kill-session -t "$session" 2>/dev/null; then
    echo "✓ Killed session: $session"
  else
    echo "✗ Failed to kill session '$session' (may not exist)"
    exit 1
  fi
else
  echo "Cancelled"
  exit 0
fi
