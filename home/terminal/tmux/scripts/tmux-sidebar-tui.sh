#!/usr/bin/env bash
# Tmux session sidebar TUI
# Displays sessions with window counts and Claude status
# Handles navigation and session switching

set -euo pipefail

# State
selected_idx=0
sessions=()
first_render=true

# Terminal control sequences - initialized in init_terminal()
CLEAR="" HOME="" CLEAR_LINE="" BOLD="" RESET="" DIM=""
HIDE_CURSOR="" SHOW_CURSOR="" FG_GREEN="" FG_SUBTEXT="" FG_OVERLAY=""

init_terminal() {
  CLEAR=$(tput clear)
  HOME=$(tput cup 0 0)
  CLEAR_LINE=$(tput el)
  BOLD=$(tput bold)
  RESET=$(tput sgr0)
  DIM=$(tput dim 2>/dev/null || echo "")
  HIDE_CURSOR=$(tput civis)
  SHOW_CURSOR=$(tput cnorm)

  # Catppuccin-compatible colors (256 color palette)
  FG_GREEN=$(tput setaf 151)
  FG_SUBTEXT=$(tput setaf 249)
  FG_OVERLAY=$(tput setaf 243)
}

cleanup() {
  printf '%s' "$SHOW_CURSOR"
  stty echo 2>/dev/null || true
}
trap cleanup EXIT

# Disable terminal echo to prevent key display
stty -echo 2>/dev/null || true

# Get current session name
get_current_session() {
  tmux display-message -p '#{session_name}' 2>/dev/null || echo ""
}

# Get Claude status icon for a session (reuses existing script)
get_claude_icon() {
  local session="$1"
  claude-session-status "$session" --format icon 2>/dev/null || echo ""
}

# Fetch all sessions
fetch_sessions() {
  sessions=()
  while IFS=: read -r name windows attached; do
    sessions+=("$name:$windows:$attached")
  done < <(tmux list-sessions -F '#{session_name}:#{session_windows}:#{?session_attached,1,0}' 2>/dev/null | sort)
}

# Render the sidebar
render() {
  local current_session
  current_session=$(get_current_session)
  local width
  width=$(tput cols 2>/dev/null || echo 20)

  # Only clear screen on first render, then just move cursor home
  if [[ $first_render == true ]]; then
    printf '%s' "$CLEAR"
    first_render=false
  fi
  printf '%s' "$HOME"

  # Header
  printf '%s Sessions %s%s\n' "$BOLD" "$RESET" "$CLEAR_LINE"
  printf '%s' "$FG_OVERLAY"
  for ((i = 0; i < width; i++)); do printf '─'; done
  printf '%s\n' "$RESET"

  # Session list
  local idx=0
  for session_data in "${sessions[@]}"; do
    IFS=: read -r name windows attached <<<"$session_data"

    local prefix="  "
    local style=""
    local suffix=""

    # Current session marker
    if [[ $name == "$current_session" ]]; then
      prefix="${FG_GREEN}▸${RESET} "
    fi

    # Selected item highlighting
    if [[ $idx -eq $selected_idx ]]; then
      style="$BOLD"
    fi

    # Claude status icon
    local claude_icon
    claude_icon=$(get_claude_icon "$name")
    if [[ -n $claude_icon ]]; then
      suffix=" $claude_icon"
    fi

    # Format: name [windows] icon
    local windows_display="${FG_SUBTEXT}[$windows]${RESET}"

    printf '%s%s%s %s%s%s%s\n' "$prefix" "$style" "$name" "$windows_display" "$suffix" "$RESET" "$CLEAR_LINE"

    idx=$((idx + 1))
  done

  # Footer with hints
  printf '\n%s j/k:nav  enter:switch  q:close%s\n' "$DIM" "$RESET"
}

# Switch to selected session
switch_session() {
  if [[ ${#sessions[@]} -eq 0 ]]; then
    return
  fi

  local session_data="${sessions[$selected_idx]}"
  local name="${session_data%%:*}"
  local current
  current=$(get_current_session)

  # Don't switch if already on this session
  [[ $name == "$current" ]] && return

  # Switch to target session, then reopen sidebar there
  tmux switch-client -t "$name" 2>/dev/null || true

  # Small delay to let the switch complete, then open sidebar in new session
  sleep 0.1
  tmux run-shell "tmux-sidebar" 2>/dev/null || true
}

# Main loop
main() {
  # Initialize terminal sequences now that we're in the proper terminal
  init_terminal

  printf '%s' "$HIDE_CURSOR"

  # Initial render
  fetch_sessions

  # Find index of current session
  local current_session
  current_session=$(get_current_session)
  local idx=0
  for session_data in "${sessions[@]}"; do
    local name="${session_data%%:*}"
    if [[ $name == "$current_session" ]]; then
      selected_idx=$idx
      break
    fi
    idx=$((idx + 1))
  done

  render

  while true; do
    # Read with short timeout for responsive input
    if read -rsn1 -t 0.2 key; then
      case "$key" in
      j | $'\x1b')
        # Handle arrow keys (escape sequences)
        if [[ $key == $'\x1b' ]]; then
          read -rsn2 -t 0.1 seq || true
          case "$seq" in
          '[A') key='k' ;; # Up arrow
          '[B') key='j' ;; # Down arrow
          *)
            # Escape key alone - close sidebar
            exit 0
            ;;
          esac
        fi

        if [[ $key == 'j' ]]; then
          if [[ $selected_idx -lt $((${#sessions[@]} - 1)) ]]; then
            selected_idx=$((selected_idx + 1))
          fi
        fi
        ;;
      k)
        if [[ $selected_idx -gt 0 ]]; then
          selected_idx=$((selected_idx - 1))
        fi
        ;;
      '' | $'\n') # Enter key
        switch_session
        exit 0
        ;;
      q)
        exit 0
        ;;
      esac
    fi

    # Refresh data and render
    fetch_sessions

    # Clamp selection if sessions changed
    if [[ $selected_idx -ge ${#sessions[@]} ]]; then
      selected_idx=$((${#sessions[@]} - 1))
      [[ $selected_idx -lt 0 ]] && selected_idx=0
    fi

    render
  done
}

main
