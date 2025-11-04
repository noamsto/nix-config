#!/usr/bin/env bash
# Enhanced sesh preview with windows, session info, git status, and pane layout
# Usage: sesh-preview <session-name-or-path>

set -euo pipefail

# Session name is passed directly from sesh list (no icons from sesh)
target="$1"

# Color codes for output
BOLD="\033[1m"
DIM="\033[2m"
BLUE="\033[34m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

# Check if it's a tmux session or directory
if tmux has-session -t "$target" 2>/dev/null; then
  # It's an existing tmux session
  session_name="$target"
  session_path=$(tmux display-message -p -t "$session_name" -F "#{pane_current_path}" 2>/dev/null)

  echo -e "${BOLD}${BLUE}Session: $session_name${RESET}"
  echo ""

  # Session info
  echo -e "${BOLD}${CYAN}Session Info:${RESET}"
  created=$(tmux display-message -p -t "$session_name" -F "#{session_created}")
  created_human=$(date -d "@$created" "+%Y-%m-%d %H:%M" 2>/dev/null || date -r "$created" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "Unknown")
  attached=$(tmux display-message -p -t "$session_name" -F "#{session_attached}")
  windows=$(tmux display-message -p -t "$session_name" -F "#{session_windows}")

  echo -e "  ${DIM}Created:${RESET}  $created_human"
  echo -e "  ${DIM}Clients:${RESET}  $attached"
  echo -e "  ${DIM}Windows:${RESET}  $windows"
  echo -e "  ${DIM}Path:${RESET}     $session_path"
  echo ""

  # Window list with tree-style formatting (like tmux choose-tree)
  echo -e "${BOLD}${CYAN}Windows:${RESET}"
  tmux list-windows -t "$session_name" 2>/dev/null | while IFS= read -r line; do
    # Parse window line: "0: window-name* (2 panes) [282x67]"
    win_index=$(echo "$line" | awk -F: '{print $1}')
    win_info=$(echo "$line" | cut -d: -f2-)

    # Check if active (contains *)
    if [[ $win_info == *"*"* ]]; then
      echo -e "  ${GREEN}● $win_index:${RESET}$win_info"
    else
      echo -e "  ${DIM}○ $win_index:${RESET}$win_info"
    fi
  done
  echo ""

  # Visual pane layout using tmux's display-panes format
  echo -e "${BOLD}${CYAN}Layout:${RESET}"
  active_window=$(tmux display-message -p -t "$session_name" -F "#{window_index}")
  layout=$(tmux list-windows -t "$session_name:$active_window" -F "#{window_layout}" 2>/dev/null)
  pane_count=$(tmux list-panes -t "$session_name:$active_window" 2>/dev/null | wc -l)

  if [[ $pane_count -eq 1 ]]; then
    echo -e "  ${DIM}Single pane${RESET}"
  else
    echo -e "  ${DIM}$pane_count panes - Layout: $layout${RESET}"
    # Show pane tree
    tmux list-panes -t "$session_name:$active_window" -F "  ├─ Pane #{pane_index}: #{pane_current_command} [#{pane_width}x#{pane_height}]" 2>/dev/null
  fi
  echo ""

  # Git status if in a repo
  if [[ -d $session_path ]]; then
    if git -C "$session_path" rev-parse --git-dir >/dev/null 2>&1; then
      echo -e "${BOLD}${CYAN}Git Status:${RESET}"
      branch=$(git -C "$session_path" branch --show-current 2>/dev/null || echo "detached")
      echo -e "  ${DIM}Branch:${RESET}   ${GREEN}$branch${RESET}"

      # Check if there are changes
      if git -C "$session_path" diff --quiet 2>/dev/null; then
        echo -e "  ${DIM}Changes:${RESET}  ${GREEN}Clean${RESET}"
      else
        changed=$(git -C "$session_path" diff --name-only 2>/dev/null | wc -l)
        echo -e "  ${DIM}Changes:${RESET}  ${YELLOW}$changed file(s) modified${RESET}"
      fi

      # Show repository icon if exists
      git_root=$(git -C "$session_path" rev-parse --show-toplevel 2>/dev/null)
      if [[ -f "$git_root/.icon" ]]; then
        icon=$(cat "$git_root/.icon")
        echo -e "  ${DIM}Repo:${RESET}     $icon $(basename "$git_root")"
      fi
    fi
  fi

else
  # It's a directory path - show directory info
  if [[ -d $target ]]; then
    echo -e "${BOLD}${BLUE}Directory: $target${RESET}"
    echo ""

    # Directory info
    echo -e "${BOLD}${CYAN}Info:${RESET}"
    size=$(du -sh "$target" 2>/dev/null | awk '{print $1}' || echo "Unknown")
    files=$(find "$target" -maxdepth 1 -type f 2>/dev/null | wc -l || echo "0")
    dirs=$(find "$target" -maxdepth 1 -type d 2>/dev/null | tail -n +2 | wc -l || echo "0")

    echo -e "  ${DIM}Size:${RESET}     $size"
    echo -e "  ${DIM}Files:${RESET}    $files"
    echo -e "  ${DIM}Dirs:${RESET}     $dirs"
    echo ""

    # Git status if in a repo
    if git -C "$target" rev-parse --git-dir >/dev/null 2>&1; then
      echo -e "${BOLD}${CYAN}Git Status:${RESET}"
      branch=$(git -C "$target" branch --show-current 2>/dev/null || echo "detached")
      echo -e "  ${DIM}Branch:${RESET}   ${GREEN}$branch${RESET}"

      if git -C "$target" diff --quiet 2>/dev/null; then
        echo -e "  ${DIM}Changes:${RESET}  ${GREEN}Clean${RESET}"
      else
        changed=$(git -C "$target" diff --name-only 2>/dev/null | wc -l)
        echo -e "  ${DIM}Changes:${RESET}  ${YELLOW}$changed file(s) modified${RESET}"
      fi

      # Show repository icon if exists
      git_root=$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)
      if [[ -f "$git_root/.icon" ]]; then
        icon=$(cat "$git_root/.icon")
        echo -e "  ${DIM}Repo:${RESET}     $icon $(basename "$git_root")"
      fi
      echo ""
    fi

    # Show recent files
    echo -e "${BOLD}${CYAN}Recent Files:${RESET}"
    find "$target" -maxdepth 2 -type f -not -path "*/\.git/*" 2>/dev/null | head -n 5 | while read -r file; do
      echo -e "  ${DIM}$(basename "$file")${RESET}"
    done || echo "  No files found"

  else
    echo -e "${YELLOW}Not found: $target${RESET}"
    echo ""
    echo "This will create a new session when selected."
  fi
fi
