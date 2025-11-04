#!/usr/bin/env bash
# Create new tmux session with optional worktree support
# Usage: sesh-new [directory] [session-name]

set -euo pipefail

dir="${1:-.}"
session_name="${2:-}"

# Expand home directory if needed
dir="${dir/#\~/$HOME}"

# If directory doesn't exist, show helpful message
if [[ ! -d $dir ]]; then
  echo "Error: Directory '$dir' does not exist"
  echo ""
  echo "To create a git worktree session:"
  echo "  1. cd to your repository"
  echo "  2. Use Claude Code's git worktrees skill, or"
  echo "  3. Run: git worktree add .worktrees/<branch-name> <branch-name>"
  echo "  4. Then run: sesh-new .worktrees/<branch-name>"
  exit 1
fi

# Determine session name
if [[ -z $session_name ]]; then
  # Auto-generate session name from directory
  session_name=$(basename "$dir")

  # If this is a worktree, use repo-name/branch-name format
  if [[ $dir == */.worktrees/* ]]; then
    branch_name=$(basename "$dir")
    git_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "")
    if [[ -n $git_root ]]; then
      repo_name=$(basename "$git_root")
      session_name="$repo_name/$branch_name"
    fi
  fi
fi

# Create or connect to session
echo "Creating/connecting to session: $session_name"
sesh connect "$session_name" --root "$dir"
