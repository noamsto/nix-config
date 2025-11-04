#!/usr/bin/env bash
# Hook called after worktree creation to auto-create tmux session
# Usage: worktree-session-hook.sh <worktree-path> <branch-name>

set -euo pipefail

worktree_path="$1"
branch_name="$2"

# Get repository name for session naming
repo_root=$(git -C "$worktree_path" rev-parse --show-toplevel)
repo_name=$(basename "$repo_root")

# Session name format: repo-name/branch-name
session_name="$repo_name/$branch_name"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Creating tmux session for worktree"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Worktree: $worktree_path"
echo "  Branch:   $branch_name"
echo "  Session:  $session_name"
echo ""

# Create session in background (don't switch if inside tmux)
if [[ -n ${TMUX:-} ]]; then
  # Inside tmux - create detached session
  if tmux new-session -d -s "$session_name" -c "$worktree_path" 2>/dev/null; then
    echo "✓ Session created successfully"
    echo ""
    echo "Switch to it with:"
    echo "  • Press Prefix+S and select '$session_name'"
    echo "  • Or run: tmux switch-client -t $session_name"
  else
    echo "⚠ Session '$session_name' already exists"
    echo ""
    echo "Switch to it with: tmux switch-client -t $session_name"
  fi
else
  # Outside tmux - create and attach
  echo "Opening new terminal with session..."
  kitty --detach sh -c "sesh connect '$session_name' --root '$worktree_path'"
  echo "✓ Terminal opened with session: $session_name"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
