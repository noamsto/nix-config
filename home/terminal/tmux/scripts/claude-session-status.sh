#!/usr/bin/env bash
# Get Claude status summary for a session (used by sesh picker)
# Usage: claude-session-status <session-name> [--format short|long|icon|icon-color]
#
# Output formats:
#   short: "⠙2" (icon + count)
#   long:  "2 processing, 1 waiting"
#   icon:  Just the icon (no color)
#   icon-color: Icon with tmux color codes

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

# Detect current theme from state file
detect_theme() {
  local theme_file="${XDG_STATE_HOME:-$HOME/.local/state}/theme-state.json"
  if [[ -f $theme_file ]]; then
    grep -o '"theme"[[:space:]]*:[[:space:]]*"[^"]*"' "$theme_file" 2>/dev/null | cut -d'"' -f4
  else
    echo "dark"
  fi
}

# Count states for this session
count_processing=0
count_waiting=0
count_compacting=0
count_done=0
count_idle=0

for pane_file in "$PANES_DIR"/*; do
  [[ -f $pane_file ]] || continue

  pane_session=$(grep "^session=" "$pane_file" 2>/dev/null | cut -d= -f2)
  [[ $pane_session == "$session_name" ]] || continue

  pane_state=$(grep "^state=" "$pane_file" 2>/dev/null | cut -d= -f2)

  case "$pane_state" in
  processing) ((count_processing++)) || true ;;
  waiting) ((count_waiting++)) || true ;;
  compacting) ((count_compacting++)) || true ;;
  done) ((count_done++)) || true ;;
  idle) ((count_idle++)) || true ;;
  esac
done

total=$((count_processing + count_waiting + count_compacting + count_done + count_idle))
[[ $total -gt 0 ]] || exit 0

# Output based on format
case "$format_value" in
short)
  # Priority icon + total count (using Nerd Font icons)
  if [[ $count_waiting -gt 0 ]]; then
    echo "󰔟$total" # nf-md-timer-sand
  elif [[ $count_compacting -gt 0 ]]; then
    echo "$total" # nf-md-archive (compacting)
  elif [[ $count_processing -gt 0 ]]; then
    echo "$(get_spinner_frame)$total"
  elif [[ $count_done -gt 0 ]]; then
    echo "$total" # nf-fa-check
  elif [[ $count_idle -gt 0 ]]; then
    echo "󰚩$total" # nf-md-robot (idle)
  fi
  ;;

long)
  # Detailed breakdown
  parts=()
  [[ $count_processing -eq 0 ]] || parts+=("$count_processing processing")
  [[ $count_waiting -eq 0 ]] || parts+=("$count_waiting waiting")
  [[ $count_compacting -eq 0 ]] || parts+=("$count_compacting compacting")
  [[ $count_done -eq 0 ]] || parts+=("$count_done done")
  [[ $count_idle -eq 0 ]] || parts+=("$count_idle idle")

  IFS=", "
  echo "${parts[*]}"
  ;;

icon)
  # Priority icon with count if multiple (for inline use, Nerd Font)
  # Shows: icon (if 1 claude) or icon + count (if multiple)
  count_suffix=""
  [[ $total -gt 1 ]] && count_suffix=" $total"

  if [[ $count_waiting -gt 0 ]]; then
    echo "󰔟$count_suffix" # nf-md-timer-sand
  elif [[ $count_compacting -gt 0 ]]; then
    echo "$count_suffix" # nf-md-archive (compacting)
  elif [[ $count_processing -gt 0 ]]; then
    echo "$(get_spinner_frame)$count_suffix"
  elif [[ $count_done -gt 0 ]]; then
    echo "$count_suffix" # nf-fa-check (U+F00C)
  elif [[ $count_idle -gt 0 ]]; then
    echo "󰚩$count_suffix" # nf-md-robot (idle)
  fi
  ;;

icon-color)
  # Priority icon with tmux colors and count if multiple
  # Theme-aware: uses Catppuccin hex colors for proper contrast in both themes
  current_theme=$(detect_theme)

  if [[ $current_theme == "light" ]]; then
    # Catppuccin Latte
    C_WAITING="#[fg=#fe640b]" # Peach
    C_COMPACT="#[fg=#04a5e5]" # Sky
    C_PROCESS="#[fg=#8839ef]" # Mauve
    C_DONE="#[fg=#40a02b]"    # Green
    C_IDLE="#[fg=#6c6f85]"    # Overlay0
  else
    # Catppuccin Mocha
    C_WAITING="#[fg=#fab387]" # Peach
    C_COMPACT="#[fg=#89dceb]" # Sky
    C_PROCESS="#[fg=#cba6f7]" # Mauve
    C_DONE="#[fg=#a6e3a1]"    # Green
    C_IDLE="#[fg=#6c7086]"    # Overlay0
  fi
  C_RESET="#[fg=default]"

  count_suffix=""
  [[ $total -gt 1 ]] && count_suffix=" $total"

  if [[ $count_waiting -gt 0 ]]; then
    echo "${C_WAITING}󰔟$count_suffix${C_RESET}"
  elif [[ $count_compacting -gt 0 ]]; then
    echo "${C_COMPACT}$count_suffix${C_RESET}"
  elif [[ $count_processing -gt 0 ]]; then
    echo "${C_PROCESS}$(get_spinner_frame)$count_suffix${C_RESET}"
  elif [[ $count_done -gt 0 ]]; then
    echo "${C_DONE}$count_suffix${C_RESET}"
  elif [[ $count_idle -gt 0 ]]; then
    echo "${C_IDLE}󰚩$count_suffix${C_RESET}"
  fi
  ;;

gum)
  # Gum-styled output for sesh picker
  if [[ $count_waiting -gt 0 ]]; then
    gum style --foreground 216 "󰔟 $count_waiting waiting" 2>/dev/null || echo "󰔟 $count_waiting waiting"
  elif [[ $count_compacting -gt 0 ]]; then
    gum style --foreground 117 " $count_compacting compacting" 2>/dev/null || echo "󰛆 $count_compacting compacting"
  elif [[ $count_processing -gt 0 ]]; then
    gum style --foreground 183 "$(get_spinner_frame) $count_processing working" 2>/dev/null || echo "$(get_spinner_frame) $count_processing working"
  elif [[ $count_done -gt 0 ]]; then
    gum style --foreground 151 " $count_done done" 2>/dev/null || echo " $count_done done"
  elif [[ $count_idle -gt 0 ]]; then
    gum style --foreground 245 "󰚩 $count_idle idle" 2>/dev/null || echo "󰚩 $count_idle idle"
  fi
  ;;
esac
