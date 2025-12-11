#!/usr/bin/env bash
# Output Claude status indicator for tmux status bar
# Usage: claude-tmux-indicator [--pane PANE_ID] [--session SESSION_NAME] [--window WINDOW_ID]
#
# Outputs an animated spinner for processing, static icons for other states
# Called by tmux status-format every status-interval (1 second)

set -euo pipefail

STATE_DIR="/tmp/claude-status"
PANES_DIR="$STATE_DIR/panes"
SESSIONS_DIR="$STATE_DIR/sessions"

# Spinner frames (Nerd Font circle progress - nf-md-circle-slice)
SPINNER_FRAMES=("󰪞" "󰪟" "󰪠" "󰪡" "󰪢" "󰪣" "󰪤" "󰪥")
SPINNER_COUNT=${#SPINNER_FRAMES[@]}

# Icons for different states (Nerd Font)
ICON_WAITING="󰔟" # nf-md-timer-sand
ICON_DONE=""    # nf-fa-check

# Colors (tmux style)
COLOR_PROCESSING="#[fg=colour116]" # Teal
COLOR_WAITING="#[fg=colour216]"    # Peach
COLOR_DONE="#[fg=colour151]"       # Green
COLOR_RESET="#[fg=default]"

# Parse arguments
mode="pane" # pane, session, or window
pane_id=""
session_name=""
window_id=""
no_color=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --pane)
    mode="pane"
    pane_id="$2"
    shift 2
    ;;
  --session)
    mode="session"
    session_name="$2"
    shift 2
    ;;
  --window)
    mode="window"
    window_id="$2"
    shift 2
    ;;
  --no-color)
    no_color=true
    shift
    ;;
  *)
    shift
    ;;
  esac
done

# Get current spinner frame based on timestamp
get_spinner_frame() {
  local frame_idx=$(($(date +%s) % SPINNER_COUNT))
  echo "${SPINNER_FRAMES[$frame_idx]}"
}

# Read pane state
read_pane_state() {
  local pane="$1"
  local pane_file="${pane#%}"
  local state_file="$PANES_DIR/$pane_file"

  [[ -f $state_file ]] || return 1

  local state
  state=$(grep "^state=" "$state_file" 2>/dev/null | cut -d= -f2)

  echo "$state"
}

# Read session aggregate state
read_session_state() {
  local sess="$1"
  local state_file="$SESSIONS_DIR/$sess"

  [[ -f $state_file ]] || return 1

  local state count
  state=$(grep "^state=" "$state_file" 2>/dev/null | cut -d= -f2)
  count=$(grep "^count=" "$state_file" 2>/dev/null | cut -d= -f2)

  echo "$state:$count"
}

# Output indicator with optional color
output_indicator() {
  local state="$1"
  local count="${2:-1}"

  local icon color

  case "$state" in
  processing)
    icon=$(get_spinner_frame)
    color="$COLOR_PROCESSING"
    ;;
  waiting)
    icon="$ICON_WAITING"
    color="$COLOR_WAITING"
    ;;
  done)
    icon="$ICON_DONE"
    color="$COLOR_DONE"
    ;;
  *)
    echo ""
    return
    ;;
  esac

  if $no_color; then
    if [[ $count -gt 1 ]]; then
      echo "$icon$count"
    else
      echo "$icon"
    fi
  else
    if [[ $count -gt 1 ]]; then
      echo "${color}${icon}${count}${COLOR_RESET}"
    else
      echo "${color}${icon}${COLOR_RESET}"
    fi
  fi
}

# Main logic based on mode
case "$mode" in
pane)
  if [[ -z $pane_id ]]; then
    echo ""
    exit 0
  fi
  state=$(read_pane_state "$pane_id") || exit 0
  output_indicator "$state"
  ;;

session)
  if [[ -z $session_name ]]; then
    echo ""
    exit 0
  fi
  result=$(read_session_state "$session_name") || exit 0
  state="${result%%:*}"
  count="${result##*:}"
  output_indicator "$state" "$count"
  ;;

window)
  # For window mode, scan all panes in the window
  # This requires tmux commands to list panes
  if [[ -z $window_id ]]; then
    echo ""
    exit 0
  fi

  has_waiting=false
  has_processing=false
  has_done=false

  # Get all panes in window
  while IFS= read -r pane; do
    [[ -n $pane ]] || continue
    state=$(read_pane_state "$pane") || continue

    case "$state" in
    waiting) has_waiting=true ;;
    processing) has_processing=true ;;
    done) has_done=true ;;
    esac
  done < <(tmux list-panes -t "$window_id" -F '#{pane_id}' 2>/dev/null)

  # Priority: waiting > processing > done
  if $has_waiting; then
    output_indicator "waiting"
  elif $has_processing; then
    output_indicator "processing"
  elif $has_done; then
    output_indicator "done"
  fi
  ;;
esac
