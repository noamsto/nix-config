#!/usr/bin/env bash
# Get Claude status summary for a session (used by sesh picker)
# Usage: claude-session-status <session-name> [--format short|long|icon]
#
# Output formats:
#   short: "⠙2" (icon + count)
#   long:  "2 processing, 1 waiting"
#   icon:  Just the icon with color

set -euo pipefail

STATE_DIR="/tmp/claude-status"
PANES_DIR="$STATE_DIR/panes"

session_name="${1:-}"
format="${2:---format}"
format_value="${3:-short}"

# Handle --format arg
if [[ $format == "--format" ]]; then
  format_value="${format_value:-short}"
elif [[ $format =~ ^-- ]]; then
  format_value="${format#--}"
else
  format_value="$format"
fi

[[ -n $session_name ]] || exit 0

# Spinner frames (Nerd Font circle progress)
SPINNER_FRAMES=("󰪞" "󰪟" "󰪠" "󰪡" "󰪢" "󰪣" "󰪤" "󰪥")
get_spinner_frame() {
  local frame_idx=$(($(date +%s) % ${#SPINNER_FRAMES[@]}))
  echo "${SPINNER_FRAMES[$frame_idx]}"
}

# Count states for this session
count_processing=0
count_waiting=0
count_done=0

for pane_file in "$PANES_DIR"/*; do
  [[ -f $pane_file ]] || continue

  pane_session=$(grep "^session=" "$pane_file" 2>/dev/null | cut -d= -f2)
  [[ $pane_session == "$session_name" ]] || continue

  pane_state=$(grep "^state=" "$pane_file" 2>/dev/null | cut -d= -f2)
  timestamp=$(grep "^timestamp=" "$pane_file" 2>/dev/null | cut -d= -f2)

  now=$(date +%s)
  age=$((now - timestamp))

  # Skip stale states based on type
  case "$pane_state" in
  processing)
    [[ $age -le 30 ]] || continue
    ;;
  done)
    [[ $age -le 60 ]] || continue
    ;;
  waiting)
    [[ $age -le 300 ]] || continue
    ;;
  esac

  case "$pane_state" in
  processing) ((count_processing++)) || true ;;
  waiting) ((count_waiting++)) || true ;;
  done) ((count_done++)) || true ;;
  esac
done

total=$((count_processing + count_waiting + count_done))
[[ $total -gt 0 ]] || exit 0

# Output based on format
case "$format_value" in
short)
  # Priority icon + total count
  if [[ $count_waiting -gt 0 ]]; then
    echo "⏳$total"
  elif [[ $count_processing -gt 0 ]]; then
    echo "$(get_spinner_frame)$total"
  elif [[ $count_done -gt 0 ]]; then
    echo "✓$total"
  fi
  ;;

long)
  # Detailed breakdown
  parts=()
  [[ $count_processing -eq 0 ]] || parts+=("$count_processing processing")
  [[ $count_waiting -eq 0 ]] || parts+=("$count_waiting waiting")
  [[ $count_done -eq 0 ]] || parts+=("$count_done done")

  IFS=", "
  echo "${parts[*]}"
  ;;

icon)
  # Just the icon (for inline use)
  if [[ $count_waiting -gt 0 ]]; then
    echo "⏳"
  elif [[ $count_processing -gt 0 ]]; then
    get_spinner_frame
  elif [[ $count_done -gt 0 ]]; then
    echo "✓"
  fi
  ;;

gum)
  # Gum-styled output for sesh picker
  if [[ $count_waiting -gt 0 ]]; then
    gum style --foreground 216 "⏳ $count_waiting waiting" 2>/dev/null || echo "⏳ $count_waiting waiting"
  elif [[ $count_processing -gt 0 ]]; then
    gum style --foreground 183 "$(get_spinner_frame) $count_processing working" 2>/dev/null || echo "$(get_spinner_frame) $count_processing working"
  elif [[ $count_done -gt 0 ]]; then
    gum style --foreground 151 "✓ $count_done done" 2>/dev/null || echo "✓ $count_done done"
  fi
  ;;
esac
