#!/usr/bin/env bash
# Find the priority window in a tmux session
# Priority: Claude window (processing > waiting > done) > active window
#
# Usage: claude-priority-window SESSION_NAME [--index|--name|--target|--display]
#   --index   Return window index only (default)
#   --name    Return window name only
#   --target  Return session:window target for tmux switch
#   --display Return "window_name (claude_status)" for display

set -euo pipefail

STATE_DIR="/tmp/claude-status/panes"

session="${1:-}"
format="${2:---index}"

if [[ -z $session ]]; then
  echo ""
  exit 0
fi

# Strip tmux target format prefixes/suffixes (e.g., "=session:" -> "session")
session="${session#=}"
session="${session%:}"

# Check if session exists
if ! tmux has-session -t "$session" 2>/dev/null; then
  echo ""
  exit 0
fi

# Find windows with Claude activity
# Returns: window_index window_name state
find_claude_windows() {
  local sess="$1"

  while IFS=$'\t' read -r win_idx win_name pane_id; do
    [[ -n $pane_id ]] || continue

    local pane_file="${pane_id#%}"
    local state_file="$STATE_DIR/$pane_file"

    if [[ -f $state_file ]]; then
      local state
      state=$(grep "^state=" "$state_file" 2>/dev/null | cut -d= -f2)
      if [[ -n $state && $state != "idle" ]]; then
        echo -e "$win_idx\t$win_name\t$state"
      fi
    fi
  done < <(tmux list-panes -s -t "$sess" -F '#{window_index}	#{window_name}	#{pane_id}' 2>/dev/null)
}

# Get active window as fallback
get_active_window() {
  local sess="$1"
  tmux list-windows -t "$sess" -F '#{window_index}	#{window_name}	#{window_active}' 2>/dev/null |
    awk -F'\t' '$3 == "1" {print $1 "\t" $2; exit}'
}

# Find priority window
priority_idx=""
priority_name=""
priority_state=""

# Check for Claude windows with priority: processing > waiting > done
while IFS=$'\t' read -r idx name state; do
  [[ -n $idx ]] || continue

  case "$state" in
  processing)
    # Highest priority - use immediately
    priority_idx="$idx"
    priority_name="$name"
    priority_state="$state"
    break
    ;;
  waiting)
    # Second priority
    if [[ $priority_state != "processing" ]]; then
      priority_idx="$idx"
      priority_name="$name"
      priority_state="$state"
    fi
    ;;
  done)
    # Third priority
    if [[ -z $priority_state || $priority_state == "done" ]]; then
      priority_idx="$idx"
      priority_name="$name"
      priority_state="$state"
    fi
    ;;
  esac
done < <(find_claude_windows "$session")

# Fallback to active window if no Claude window found
if [[ -z $priority_idx ]]; then
  read -r priority_idx priority_name < <(get_active_window "$session")
fi

# Output based on format
case "$format" in
--index)
  echo "$priority_idx"
  ;;
--name)
  echo "$priority_name"
  ;;
--target)
  if [[ -n $priority_idx ]]; then
    echo "${session}:${priority_idx}"
  else
    echo "$session"
  fi
  ;;
--display)
  if [[ -n $priority_state ]]; then
    # Show window name with Claude indicator
    icon=""
    case "$priority_state" in
    processing) icon="󰪠" ;;
    waiting) icon="󰔟" ;;
    done) icon="" ;;
    esac
    echo "${priority_name} ${icon}"
  else
    echo "${priority_name:-}"
  fi
  ;;
esac
