#!/usr/bin/env bash
# Tmux/Hyprland navigation with proper edge detection
# Called from tmux bindings when NOT in vim
# Usage: tmux-navigate <direction>

set -euo pipefail

direction="${1:-}"
if [[ -z $direction ]]; then
  exit 1
fi

# Map direction to tmux and Hyprland commands
case "$direction" in
left)
  tmux_dir="-L"
  hypr_dir="l"
  ;;
right)
  tmux_dir="-R"
  hypr_dir="r"
  ;;
up)
  tmux_dir="-U"
  hypr_dir="u"
  ;;
down)
  tmux_dir="-D"
  hypr_dir="d"
  ;;
*)
  exit 1
  ;;
esac

# Check if we're in tmux (should always be true when called from tmux binding)
if [[ -z ${TMUX:-} ]]; then
  hyprctl dispatch movefocus "$hypr_dir" >/dev/null 2>&1
  exit 0
fi

# Check if pane is zoomed
is_zoomed=$(tmux display-message -p '#{window_zoomed_flag}')
if [[ $is_zoomed == "1" ]]; then
  # Zoomed: navigate Hyprland directly
  hyprctl dispatch movefocus "$hypr_dir" >/dev/null 2>&1
  exit 0
fi

# Not zoomed: navigate tmux panes with edge detection
current_pane=$(tmux display-message -p '#{pane_id}')
tmux select-pane "$tmux_dir" 2>/dev/null || true
new_pane=$(tmux display-message -p '#{pane_id}')

if [[ $current_pane == "$new_pane" ]]; then
  # At edge (pane didn't change) → navigate Hyprland
  hyprctl dispatch movefocus "$hypr_dir" >/dev/null 2>&1
fi

# If pane changed, we successfully navigated within tmux, do nothing more
