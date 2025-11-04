#!/usr/bin/env bash
# Set or view repository icon for session grouping
# Usage: sesh-icon [emoji]

set -euo pipefail

# Find git root
git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

if [[ -z $git_root ]]; then
  echo "Error: Not in a git repository"
  exit 1
fi

repo_name=$(basename "$git_root")

if [[ -n ${1:-} ]]; then
  # Set icon
  icon="$1"
  echo "$icon" >"$git_root/.icon"
  echo "✓ Set icon for '$repo_name': $icon"
  echo ""

  # Check if .icon is in .gitignore
  if [[ -f "$git_root/.gitignore" ]]; then
    if ! grep -q "^\.icon$" "$git_root/.gitignore" 2>/dev/null; then
      echo "Tip: Consider adding .icon to .gitignore if it's a personal preference:"
      echo "  echo '.icon' >> .gitignore"
    fi
  fi
else
  # Show current icon
  if [[ -f "$git_root/.icon" ]]; then
    current_icon=$(cat "$git_root/.icon" | head -n1)
    echo "Current icon for '$repo_name': $current_icon"
  else
    echo "No icon set for '$repo_name'"
    echo ""
    echo "Set an icon with: sesh-icon <emoji>"
    echo "Example: sesh-icon ❄️"
  fi
fi
