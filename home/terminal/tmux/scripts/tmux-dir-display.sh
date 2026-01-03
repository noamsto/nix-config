#!/usr/bin/env bash
# Display directory for tmux status bar
# Shows "/" if basedir equals branch, otherwise shows basedir
# Args: $1 = @branch value, $2 = pane_current_path

branch="$1"
pane_path="$2"

# Get branch (from @branch or git)
if [[ -z $branch ]] && [[ -n $pane_path ]] && [[ -d $pane_path ]]; then
  branch=$(git -C "$pane_path" branch --show-current 2>/dev/null)
fi

# Get basedir
basedir=$(basename "$pane_path" 2>/dev/null)

# Compare and output
if [[ $basedir == "$branch" ]]; then
  echo "/"
else
  echo "$basedir"
fi
