#!/usr/bin/env bash
# Smart DND audio sync - detects active calls before muting

# Apps to manage during DND
DND_MUTE_APPS=(
  "Slack"
  "slack"
  "Discord"
  "discord"
  "teams"
  "Microsoft Teams"
  "Chromium"
  "Google Chrome"
  "firefox"
)

# File to store override status
OVERRIDE_FILE="/tmp/dnd-audio-override"

# Get current DND status from SwayNC
get_dnd_status() {
  swaync-client -D 2>/dev/null | jq -r '.dnd' 2>/dev/null || echo "false"
}

# Check if any app is in an active call
is_in_call() {
  local in_call=false

  # Method 1: Check for active microphone usage by our apps
  for app in "${DND_MUTE_APPS[@]}"; do
    if pactl list source-outputs | grep -B 20 "application.name = \"$app\"" | grep -q "state: RUNNING"; then
      echo "Active mic usage detected for $app"
      in_call=true
      break
    fi
  done

  # Method 2: Check for high-bandwidth audio streams (typical for calls)
  # Call audio typically has consistent high bandwidth, notifications are brief
  if ! $in_call; then
    for app in "${DND_MUTE_APPS[@]}"; do
      # Get sink inputs for the app
      local sink_inputs
      sink_inputs=$(pactl list sink-inputs | grep -B 20 "application.name = \"$app\"" | grep "Sink Input #" | awk '{print $3}' | tr -d '#')

      for sink_id in $sink_inputs; do
        # Check if the stream has been active for more than 10 seconds (likely a call)
        local duration
        duration=$(pactl list sink-inputs | grep -A 50 "Sink Input #$sink_id" | grep -oP '(?<=Duration: )\d+' | head -1)
        if [[ -n $duration && $duration -gt 10000 ]]; then
          echo "Long-running audio stream detected for $app (likely a call)"
          in_call=true
          break 2
        fi
      done
    done
  fi

  # Method 3: Check for screen sharing (often indicates active meeting)
  if ! $in_call && command -v hyprctl &>/dev/null; then
    if hyprctl clients | grep -q "screen-share\|sharing"; then
      echo "Screen sharing detected - likely in a meeting"
      in_call=true
    fi
  fi

  $in_call
}

# Get list of currently playing audio streams for our apps
get_active_streams() {
  for app in "${DND_MUTE_APPS[@]}"; do
    pactl list sink-inputs | grep -B 20 "application.name = \"$app\"" | grep "Sink Input #" | awk '{print $3}' | tr -d '#'
  done
}

# Mute/unmute specific application
toggle_app_audio() {
  local app_name="$1"
  local mute_status="$2" # 1 for mute, 0 for unmute

  pactl list sink-inputs | grep -B 20 "application.name = \"$app_name\"" |
    grep "Sink Input #" | awk '{print $3}' | tr -d '#' |
    while read -r sink_id; do
      pactl set-sink-input-mute "$sink_id" "$mute_status"
    done
}

# Store current mute state to restore after call
save_mute_state() {
  date +%s >"$OVERRIDE_FILE.timestamp"
  get_active_streams >"$OVERRIDE_FILE.streams"
}

# Main sync function with smart detection
sync_dnd_audio() {
  local dnd_status
  dnd_status=$(get_dnd_status)

  # Check for manual override (expires after 4 hours)
  if [[ -f $OVERRIDE_FILE ]]; then
    local override_time
    override_time=$(cat "$OVERRIDE_FILE.timestamp" 2>/dev/null || echo 0)
    local current_time
    current_time=$(date +%s)
    local time_diff=$((current_time - override_time))

    if [[ $time_diff -gt 14400 ]]; then # 4 hours
      echo "Override expired, removing..."
      rm -f "$OVERRIDE_FILE" "$OVERRIDE_FILE.timestamp" "$OVERRIDE_FILE.streams"
    else
      echo "Manual override active (expires in $((14400 - time_diff)) seconds)"
      return
    fi
  fi

  if [[ $dnd_status == "true" ]]; then
    # DND is ON - but check if we're in a call first
    if is_in_call; then
      echo "DND is ON but active call detected - NOT muting"
      notify-send "Smart DND" "Call detected - audio not muted" -t 3000
      save_mute_state
    else
      echo "DND is ON - muting notification apps"
      for app in "${DND_MUTE_APPS[@]}"; do
        toggle_app_audio "$app" 1
      done
    fi
  else
    echo "DND is OFF - unmuting notification apps"
    for app in "${DND_MUTE_APPS[@]}"; do
      toggle_app_audio "$app" 0
    done
  fi
}

# Create manual override (useful during calls)
create_override() {
  touch "$OVERRIDE_FILE"
  date +%s >"$OVERRIDE_FILE.timestamp"
  echo "Manual override created - DND audio sync disabled for 4 hours"
  notify-send "Smart DND" "Audio sync disabled for 4 hours" -t 3000
}

# Remove manual override
remove_override() {
  rm -f "$OVERRIDE_FILE" "$OVERRIDE_FILE.timestamp" "$OVERRIDE_FILE.streams"
  echo "Manual override removed"
  notify-send "Smart DND" "Audio sync re-enabled" -t 3000
  sync_dnd_audio
}

# Monitor mode with smart call detection
monitor_dnd() {
  echo "Starting Smart DND audio sync monitor..."
  echo "Features:"
  echo "  - Detects active calls and won't mute during them"
  echo "  - Monitors microphone usage"
  echo "  - Detects long-running audio streams"
  echo "  - Checks for screen sharing"
  echo ""

  local last_status=""
  local last_call_status=false

  while true; do
    current_status=$(get_dnd_status)
    current_call_status=false

    if [[ $current_status == "true" ]]; then
      is_in_call && current_call_status=true
    fi

    # Sync if DND status changed OR call status changed
    if [[ $current_status != "$last_status" ]] || [[ $current_call_status != "$last_call_status" ]]; then
      sync_dnd_audio
      last_status="$current_status"
      last_call_status="$current_call_status"
    fi

    sleep 2 # Check every 2 seconds
  done
}

# Show current status
show_status() {
  echo "DND Status: $(get_dnd_status)"
  echo "In Call: $(is_in_call && echo "Yes" || echo "No")"
  echo "Override Active: $(test -f "$OVERRIDE_FILE" && echo "Yes" || echo "No")"
  echo ""
  echo "Active audio streams:"
  for app in "${DND_MUTE_APPS[@]}"; do
    local streams
    streams=$(pactl list sink-inputs | grep -B 20 "application.name = \"$app\"" | grep -c "Sink Input #")
    [[ $streams -gt 0 ]] && echo "  $app: $streams stream(s)"
  done
}

# Handle command line arguments
case "${1:-}" in
"monitor")
  monitor_dnd
  ;;
"sync")
  sync_dnd_audio
  ;;
"override")
  create_override
  ;;
"unoverride")
  remove_override
  ;;
"status")
  show_status
  ;;
"test-call")
  is_in_call && echo "Call detected!" || echo "No call detected"
  ;;
*)
  echo "Smart DND Audio Sync - Won't mute during active calls"
  echo ""
  echo "Usage: $0 {monitor|sync|override|unoverride|status|test-call}"
  echo "  monitor    - Continuously monitor and sync DND status"
  echo "  sync       - Sync once and exit"
  echo "  override   - Disable auto-muting for 4 hours"
  echo "  unoverride - Re-enable auto-muting"
  echo "  status     - Show current status"
  echo "  test-call  - Test call detection"
  exit 1
  ;;
esac
