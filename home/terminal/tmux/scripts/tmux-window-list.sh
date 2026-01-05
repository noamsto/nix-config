#!/usr/bin/env bash
# Unified window list with adaptive compression based on total width
# Args: $1 = session_name, $2 = client_width

session="${1}"
client_width="${2:-120}"

# Query all windows in the session
windows_data=$(tmux list-windows -t "$session" -F "#{window_index}:#{window_active}:#{window_zoomed_flag}:#{pane_current_path}")

# Read into arrays
declare -a indices active zoomed branches claude_indicators
while IFS=: read -r idx is_active is_zoomed pane_path; do
  indices+=("$idx")
  active+=("$is_active")
  zoomed+=("$is_zoomed")

  # Get branch name (try window-level, then session-level, then git)
  branch=$(tmux show-window-options -t "$session:$idx" -v @branch 2>/dev/null)
  [[ -z $branch ]] && branch=$(tmux show-options -t "$session" -v @branch 2>/dev/null)
  [[ -z $branch && -n $pane_path && -d $pane_path ]] && branch=$(git -C "$pane_path" branch --show-current 2>/dev/null)
  [[ -z $branch ]] && branch="no-branch"
  branches+=("$branch")

  # Get Claude indicator
  indicator=$(claude-tmux-indicator --window "$session:$idx" 2>/dev/null)
  claude_indicators+=("$indicator")
done <<<"$windows_data"

window_count="${#indices[@]}"
[[ $window_count -eq 0 ]] && exit 0

# Calculate total width needed for each compression level
# Format per window: "N: branch indicator"
# With separators: " │ " between windows (3 chars)
# Zoom icon when present: " 󰁌" (2 chars)

calculate_width() {
  local level=$1
  local total=0

  for i in "${!indices[@]}"; do
    local idx="${indices[$i]}"
    local branch="${branches[$i]}"
    local has_zoom="${zoomed[$i]}"
    local indicator="${claude_indicators[$i]}"

    # Base: "N: " (varies with index digits)
    local width=$((${#idx} + 2))

    # Branch name (varies by compression level)
    case $level in
    0 | 1) width=$((width + ${#branch})) ;;                      # Full
    2) width=$((width + (${#branch} < 12 ? ${#branch} : 13))) ;; # 12 chars + ellipsis
    3) width=$((width + (${#branch} < 6 ? ${#branch} : 7))) ;;   # 6 chars + ellipsis
    4) ;;                                                        # Numbers only - no branch
    esac

    # Zoom icon
    [[ $has_zoom == "1" ]] && width=$((width + 2))

    # Claude indicator (usually " 🧠" or empty)
    width=$((width + ${#indicator}))

    # Separator (except for level 1+ or last window)
    [[ $level -eq 0 && $i -lt $((window_count - 1)) ]] && width=$((width + 3))

    # Spacing between windows (always present except numbers-only)
    [[ $level -lt 4 && $i -lt $((window_count - 1)) ]] && width=$((width + 2))

    total=$((total + width))
  done

  echo $total
}

# Find appropriate compression level
# Overhead: " ╰─ " prefix (4 chars) + margins (10 chars) = ~14 chars
available_width=$((client_width - 14))

compression_level=0
for level in 0 1 2 3 4; do
  needed=$(calculate_width $level)
  if [[ $needed -le $available_width ]]; then
    compression_level=$level
    break
  fi
done

# Build output string
output=""
for i in "${!indices[@]}"; do
  idx="${indices[$i]}"
  branch="${branches[$i]}"
  is_active="${active[$i]}"
  has_zoom="${zoomed[$i]}"
  indicator="${claude_indicators[$i]}"

  # Separator (level 0 only, not before first window)
  if [[ $compression_level -eq 0 && $i -gt 0 ]]; then
    output+="#[fg=#{@thm_subtext_0},nobold] │ "
  elif [[ $compression_level -lt 4 && $i -gt 0 ]]; then
    output+="  "
  fi

  # Window index with color based on active state
  if [[ $is_active == "1" ]]; then
    output+="#[fg=#{@thm_green},bold]$idx: #[fg=#{@thm_text},nobold]"
  else
    output+="#[fg=#{@thm_subtext_0},nobold]$idx: #[fg=#{@thm_text},nobold]"
  fi

  # Branch name (compressed based on level)
  case $compression_level in
  0 | 1) output+="$branch" ;;
  2) output+="${branch:0:12}$([ ${#branch} -gt 12 ] && echo '…')" ;;
  3) output+="${branch:0:6}$([ ${#branch} -gt 6 ] && echo '…')" ;;
  4) ;; # Numbers only - skip branch
  esac

  # Zoom icon
  [[ $has_zoom == "1" ]] && output+=" 󰁌"

  # Claude indicator
  [[ -n $indicator ]] && output+=" $indicator"
done

echo "$output"
