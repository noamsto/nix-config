#!/usr/bin/env bash
# Update Amp status for tmux integration
# Called periodically to detect Amp state from pane content
# Usage: amp-status-update [--pane PANE_ID] [--session SESSION_NAME]
#
# States: processing, waiting, done, idle
# Detection: Parses tmux pane content to detect Amp state

set -euo pipefail

STATE_DIR="/tmp/amp-status"
PANES_DIR="$STATE_DIR/panes"
SESSIONS_DIR="$STATE_DIR/sessions"

mkdir -p "$PANES_DIR" "$SESSIONS_DIR"

# Sanitize session name for use as filename
sanitize_filename() {
  echo "${1//\//_}"
}

# Function to update session aggregate state
update_session_aggregate() {
  local sess="$1"
  local sess_file
  sess_file=$(sanitize_filename "$sess")
  local has_waiting=false
  local has_processing=false
  local has_done=false
  local count=0

  for pf in "$PANES_DIR"/*; do
    [[ -f $pf ]] || continue

    local pane_session pane_state
    pane_session=$(grep "^session=" "$pf" 2>/dev/null | cut -d= -f2)
    pane_state=$(grep "^state=" "$pf" 2>/dev/null | cut -d= -f2)

    [[ $pane_session == "$sess" ]] || continue

    ((count++)) || true

    case "$pane_state" in
    waiting) has_waiting=true ;;
    processing) has_processing=true ;;
    done) has_done=true ;;
    esac
  done

  local agg_state="idle"
  if $has_waiting; then
    agg_state="waiting"
  elif $has_processing; then
    agg_state="processing"
  elif $has_done; then
    agg_state="done"
  fi

  if [[ $count -gt 0 ]]; then
    cat >"$SESSIONS_DIR/$sess_file" <<EOF
state=$agg_state
count=$count
timestamp=$(date +%s)
EOF
  else
    rm -f "$SESSIONS_DIR/$sess_file"
  fi
}

# Cleanup stale panes
cleanup_stale_panes() {
  [[ -d $PANES_DIR ]] || return 0
  command -v tmux &>/dev/null || return 0

  local active_panes
  active_panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null | sed 's/^%//' || true)

  for pf in "$PANES_DIR"/*; do
    [[ -f $pf ]] || continue
    local pane_file
    pane_file=$(basename "$pf")

    if ! echo "$active_panes" | grep -q "^${pane_file}$"; then
      local pane_session
      pane_session=$(grep "^session=" "$pf" 2>/dev/null | cut -d= -f2)
      rm -f "$pf"
      if [[ -n $pane_session ]]; then
        update_session_aggregate "$pane_session"
      fi
    fi
  done
}

# Detect Amp state from pane content
detect_amp_state() {
  local pane_id="$1"

  # Check if amp/bun is running in this pane
  local pane_tty
  pane_tty=$(tmux display-message -p -t "$pane_id" '#{pane_tty}' 2>/dev/null || true)
  [[ -n $pane_tty ]] || return 1

  local procs
  procs=$(ps -o comm= -t "$pane_tty" 2>/dev/null || true)

  if ! echo "$procs" | grep -qE '^(amp|bun)$'; then
    echo "idle"
    return 0
  fi

  # Capture last 50 lines of pane content
  local content
  content=$(tmux capture-pane -p -t "$pane_id" -S -50 2>/dev/null || true)

  # Detect state from content patterns
  # Processing: spinner, "Thinking", tool calls in progress
  if echo "$content" | grep -qE '(⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏|Thinking|Running|Executing|Reading|Writing|Searching)'; then
    echo "processing"
  # Waiting: prompt visible, awaiting input
  elif echo "$content" | grep -qE '(^>|› |┃ $|Enter a prompt|Type a message)'; then
    echo "waiting"
  # Done: completed message
  elif echo "$content" | grep -qE '(Done|Completed|Finished|✓|✔)'; then
    echo "done"
  else
    echo "processing"
  fi
}

# Parse arguments
pane_id="${TMUX_PANE:-}"
session_name=""
action="update"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --pane)
    pane_id="$2"
    shift 2
    ;;
  --session)
    session_name="$2"
    shift 2
    ;;
  --cleanup)
    action="cleanup"
    shift
    ;;
  *)
    shift
    ;;
  esac
done

# Handle cleanup
if [[ $action == "cleanup" ]]; then
  cleanup_stale_panes
  exit 0
fi

# Need pane_id
if [[ -z $pane_id ]]; then
  exit 0
fi

# Get session name
if [[ -z $session_name ]] && command -v tmux &>/dev/null; then
  session_name=$(tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null || true)
fi

# Detect state
state=$(detect_amp_state "$pane_id")

# Clean pane_id for filename
pane_file="${pane_id#%}"

if [[ $state == "idle" ]]; then
  rm -f "$PANES_DIR/$pane_file"
else
  cat >"$PANES_DIR/$pane_file" <<EOF
state=$state
timestamp=$(date +%s)
session=$session_name
EOF
fi

# Update session aggregate
if [[ -n $session_name ]]; then
  update_session_aggregate "$session_name"
fi
