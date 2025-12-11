#!/usr/bin/env bash
# List sessions using sesh with deduplication and Claude status indicators
# Simple passthrough to sesh with duplicate removal

set -euo pipefail

STATE_DIR="/tmp/claude-status"
PANES_DIR="$STATE_DIR/panes"

# Spinner frames (Nerd Font circle progress)
SPINNER_FRAMES=("󰪞" "󰪟" "󰪠" "󰪡" "󰪢" "󰪣" "󰪤" "󰪥")

# Get Claude status indicator for a session (inline for performance)
get_claude_indicator() {
  local session_name="$1"
  local count_processing=0 count_waiting=0 count_done=0

  for pane_file in "$PANES_DIR"/*; do
    [[ -f $pane_file ]] || continue
    local pane_session pane_state
    pane_session=$(grep "^session=" "$pane_file" 2>/dev/null | cut -d= -f2)
    [[ $pane_session == "$session_name" ]] || continue
    pane_state=$(grep "^state=" "$pane_file" 2>/dev/null | cut -d= -f2)
    case "$pane_state" in
    processing) ((count_processing++)) || true ;;
    waiting) ((count_waiting++)) || true ;;
    done) ((count_done++)) || true ;;
    esac
  done

  local total=$((count_processing + count_waiting + count_done))
  [[ $total -gt 0 ]] || return

  if [[ $count_waiting -gt 0 ]]; then
    echo "󰔟" # nf-md-timer-sand
  elif [[ $count_processing -gt 0 ]]; then
    local frame_idx=$(($(date +%s) % ${#SPINNER_FRAMES[@]}))
    echo "${SPINNER_FRAMES[$frame_idx]}"
  elif [[ $count_done -gt 0 ]]; then
    echo "" # nf-fa-check
  fi
}

# Helper to strip ANSI color codes for comparison
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# Track seen sessions to avoid duplicates
declare -A seen_sessions

# Get sessions with sesh's built-in icons
sesh list -t -z -c --icons 2>/dev/null | while IFS= read -r line; do
  # Skip empty lines
  [[ -z $line ]] && continue

  # Extract session name (last field) for duplicate checking
  clean_line=$(echo "$line" | strip_ansi)
  session_name=$(echo "$clean_line" | awk '{print $NF}')

  # Skip if we've already seen this session
  if [[ -n ${seen_sessions[$session_name]:-} ]]; then
    continue
  fi
  seen_sessions[$session_name]=1

  # Get Claude indicator for this session
  indicator=$(get_claude_indicator "$session_name")

  # Output line without ANSI codes, with Claude indicator appended
  if [[ -n $indicator ]]; then
    echo "$clean_line $indicator"
  else
    echo "$clean_line"
  fi
done | LC_ALL=C sort || true
