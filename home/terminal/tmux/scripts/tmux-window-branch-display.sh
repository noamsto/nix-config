#!/usr/bin/env bash
# Display branch name for a specific tmux window with dynamic trimming
# Args: $1 = session_name, $2 = window_index, $3 = pane_current_path, $4 = window_width, $5 = window_count

session="$1"
window_index="$2"
pane_path="$3"
window_width="${4:-80}" # Default to 80 if not provided
window_count="${5:-1}"  # Default to 1 if not provided

# Try window-level @branch variable first
branch=$(tmux show-window-options -t "$session:$window_index" -v @branch 2>/dev/null)

# Fall back to session-level @branch
if [[ -z $branch ]]; then
  branch=$(tmux show-options -t "$session" -v @branch 2>/dev/null)
fi

# Fall back to git query
if [[ -z $branch ]] && [[ -n $pane_path ]] && [[ -d $pane_path ]]; then
  branch=$(git -C "$pane_path" branch --show-current 2>/dev/null)
fi

# Strip Linear issue prefix (e.g., "pl-123-" or "PL-123-" or "ABC-456-")
# Keep only the description part for better readability
if [[ $branch =~ ^[A-Za-z]+-[0-9]+-(.+)$ ]]; then
  branch="${BASH_REMATCH[1]}"
fi

# Replace common main branches with single letter
case "$branch" in
main | master) branch="M" ;;
esac

# Calculate dynamic max length based on client width
# Formula: (client_width - padding) / window_count - overhead_per_window
# Overhead per window: "N: " (3) + " │ " (3) + zoom icon (2) + claude indicator (2) = ~10 chars
# Note: client_width is passed as window_width parameter (renamed for clarity in tmux config)
# Bottom status line has only windows, no session/app on that line
available_space=$((window_width - 20)) # Conservative padding for status bar edges
space_per_window=$((available_space / window_count))
max_branch_length=$((space_per_window - 10)) # Reduced overhead estimate

# Set minimum to 15 chars - allows more windows before overflow
# Stripped Linear prefixes make short names more meaningful
if [[ $max_branch_length -lt 15 ]]; then
  max_branch_length=15
fi

# Trim if needed
if [[ ${#branch} -gt $max_branch_length ]]; then
  echo "${branch:0:max_branch_length}…"
else
  echo "$branch"
fi
