#!/usr/bin/env bash
# List sessions with repository grouping and icons
# Reads .icon files from project roots and prepends to session names
# Output format: [repo-icon] [session-name] [type]

set -euo pipefail

# Helper to strip ANSI color codes
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# Track seen sessions to avoid duplicates
declare -A seen_sessions

# Cache git roots to avoid repeated lookups
declare -A git_root_cache

# Helper to get git root with caching
get_git_root() {
  local path="$1"
  if [[ -n ${git_root_cache[$path]:-} ]]; then
    echo "${git_root_cache[$path]}"
    return
  fi
  local root
  root=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null || echo "")
  git_root_cache[$path]="$root"
  echo "$root"
}

# Get all sessions without icons first for clean parsing
# Priority: tmux sessions > zoxide directories > config
# This ensures active sessions are shown, not just directories
sesh list -t -z -c 2>/dev/null | while IFS= read -r line; do
  # Skip empty lines
  [[ -z $line ]] && continue

  # Strip any ANSI codes
  clean_line=$(echo "$line" | strip_ansi)

  # Parse sesh output: session name is the last field (handles icons if present)
  # Example: "icon session-name" or just "session-name"
  session_name=$(echo "$clean_line" | awk '{print $NF}')

  # Skip if we've already seen this session name
  if [[ -n ${seen_sessions[$session_name]:-} ]]; then
    continue
  fi
  seen_sessions[$session_name]=1

  # Determine if it's a tmux session or directory
  repo_icon=""
  session_type="dir"

  if tmux has-session -t "$session_name" 2>/dev/null; then
    # It's a tmux session - get its working directory
    session_type="tmux"
    session_path=$(tmux display-message -p -t "$session_name" -F "#{pane_current_path}" 2>/dev/null || echo "")
    if [[ -n $session_path ]] && [[ -d $session_path ]]; then
      git_root=$(get_git_root "$session_path")
      if [[ -n $git_root ]] && [[ -f "$git_root/.icon" ]]; then
        repo_icon=$(cat "$git_root/.icon" | head -n1 | tr -d '\n')
      fi
    fi
  else
    # It's a directory path
    session_type="zoxide"
    if [[ -d $session_name ]]; then
      git_root=$(get_git_root "$session_name")
      if [[ -n $git_root ]] && [[ -f "$git_root/.icon" ]]; then
        repo_icon=$(cat "$git_root/.icon" | head -n1 | tr -d '\n')
      fi
    fi
  fi

  # Output format: [repo-icon] [session-name] ([type])
  if [[ -n $repo_icon ]]; then
    echo "$repo_icon  $session_name ($session_type)"
  else
    echo "$session_name ($session_type)"
  fi
done | LC_ALL=C sort # Sort alphabetically (groups same repos together due to icon)
