#!/usr/bin/env bash
# Display "branch | dir" for tmux status bar (top right)
# Branch is bold, dir is regular weight
# Shows "./" when at git/worktree root
# Args: $1 = @branch value (may be empty), $2 = pane_current_path

branch="$1"
pane_path="$2"

# Get branch (from @branch or git)
if [[ -z $branch ]] && [[ -n $pane_path ]] && [[ -d $pane_path ]]; then
  branch=$(git -C "$pane_path" branch --show-current 2>/dev/null)
fi

# Check if at git root
git_root=""
if [[ -n $pane_path ]] && [[ -d $pane_path ]]; then
  git_root=$(git -C "$pane_path" rev-parse --show-toplevel 2>/dev/null)
fi

# Determine dir display
if [[ -n $git_root ]] && [[ $pane_path == "$git_root" ]]; then
  # At git/worktree root
  dir="./"
else
  # Show basename
  dir=$(basename "$pane_path" 2>/dev/null)
fi

# Output with bold branch (#[bold]) and regular dir (#[nobold])
if [[ -n $branch ]]; then
  echo "#[bold]$branch#[nobold] | $dir"
else
  echo "$dir"
fi
