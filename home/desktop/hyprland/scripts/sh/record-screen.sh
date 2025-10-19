#!/bin/bash
set -euo pipefail

# Unified screen recording script for both GIF and MP4
# Usage: record-screen.sh [gif|mp4]

target_process="wl-screenrec"
record_dir="$HOME/Pictures/Records"
record_type_file="$HOME/.cache/current_record_type"
mkdir -p "$record_dir"

# Determine recording type from argument or default to mp4
record_type=${1:-mp4}

# Validate recording type
if [[ $record_type != "gif" && $record_type != "mp4" ]]; then
  echo "Usage: $0 [gif|mp4]"
  echo "Default: mp4"
  exit 1
fi

# Set format-specific variables
if [[ $record_type == "gif" ]]; then
  keybind="Alt+Shift+R"
  encode_resolution="" # No downscaling for GIF - will downscale during conversion
  qp="20"              # Slightly lower quality for GIF since it gets converted anyway
  notification_id="recording-gif"
  icon="󰹑"
  inhibitor_name="gif-recording"
else
  keybind="Super+Shift+R"
  encode_resolution="" # Record at native resolution for MP4
  qp="18"              # High quality for direct MP4 use
  notification_id="recording-mp4"
  icon="󰐌"
  inhibitor_name="mp4-recording"
fi

if pgrep -x "$target_process" >/dev/null; then
  # Process is running - try to stop it
  if [ -f "$record_type_file" ] && [ "$(cat "$record_type_file")" = "$record_type" ]; then
    # Stop recording
    pkill -INT -x "$target_process"
    rm -f "$record_type_file"

    # Remove notification inhibitor
    swaync-client --inhibitor-remove "$inhibitor_name" >/dev/null 2>&1

    # Show processing notification
    notify-send -i "$icon" \
      -h string:x-canonical-private-synchronous:$notification_id \
      "Recording Stopped" \
      "Processing ${record_type^^}..." \
      -t 0

    # Wait for the process to fully stop with timeout
    timeout=10
    count=0
    while pgrep -x "$target_process" >/dev/null && [ $count -lt $timeout ]; do
      sleep 0.5
      count=$((count + 1))
    done

    # Force kill if still running after timeout
    if pgrep -x "$target_process" >/dev/null; then
      pkill -KILL -x "$target_process"
      sleep 2
    fi

    if [[ $record_type == "gif" ]]; then
      # GIF conversion process
      # Find the most recent MP4 file
      latest_mp4=$(find "$record_dir" -name "*.mp4" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

      if [ -n "$latest_mp4" ] && [ -f "$latest_mp4" ]; then
        gif_file="${latest_mp4%.mp4}.gif"
        filename=$(basename "$gif_file")

        # Update notification for conversion step
        notify-send -i "$icon" \
          -h string:x-canonical-private-synchronous:$notification_id \
          "Processing GIF" \
          "Converting to optimized GIF..." \
          -t 0

        # Convert to GIF with optimization (capture errors)
        if ffmpeg -i "$latest_mp4" \
          -vf "fps=15,scale=1024:-1:flags=lanczos,palettegen" \
          -y "/tmp/palette.png" \
          -v quiet 2>/dev/null; then

          if ffmpeg -i "$latest_mp4" -i "/tmp/palette.png" \
            -filter_complex "fps=15,scale=1024:-1:flags=lanczos[x];[x][1:v]paletteuse" \
            -y "$gif_file" \
            -v quiet 2>/dev/null; then

            conversion_success=true
          else
            conversion_success=false
          fi
        else
          conversion_success=false
        fi

        if [ "$conversion_success" = true ] && [ -f "$gif_file" ]; then
          # Clean up
          rm -f "$latest_mp4" "/tmp/palette.png"

          # Copy to clipboard and show completion
          wl-copy -t text/uri-list "file://$gif_file"
          notify-send -i "$icon" \
            -h string:x-canonical-private-synchronous:$notification_id \
            "GIF Complete" \
            "GIF created and copied to clipboard: $filename" \
            -t 3000
        else
          # Clean up failed conversion
          rm -f "/tmp/palette.png"
          notify-send -i dialog-error \
            -h string:x-canonical-private-synchronous:$notification_id \
            "GIF Conversion Failed" \
            "Could not convert MP4 to GIF" \
            -t 3000
        fi
      else
        # Error notification
        notify-send -i dialog-error \
          -h string:x-canonical-private-synchronous:$notification_id \
          "Recording Error" \
          "Failed to process GIF" \
          -t 3000
      fi
    else
      # MP4 completion process
      # Wait for MP4 file to be properly finalized
      sleep 1

      # Find the most recent MP4 and validate it
      latest_mp4=$(find "$record_dir" -name "*.mp4" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

      if [ -n "$latest_mp4" ] && [ -f "$latest_mp4" ] && [ -s "$latest_mp4" ]; then
        # Validate MP4 file integrity
        if ffprobe "$latest_mp4" >/dev/null 2>&1; then
          filename=$(basename "$latest_mp4")
          filesize=$(du -h "$latest_mp4" | cut -f1)

          # Copy to clipboard and show completion
          wl-copy -t text/uri-list "file://$latest_mp4"
          notify-send -i "$icon" \
            -h string:x-canonical-private-synchronous:$notification_id \
            "Recording Complete" \
            "MP4 saved ($filesize) and copied to clipboard: $filename" \
            -t 3000
        else
          # Corrupted file notification
          notify-send -i dialog-error \
            -h string:x-canonical-private-synchronous:$notification_id \
            "Recording Corrupted" \
            "MP4 file is damaged or incomplete" \
            -t 3000
        fi
      else
        # Error notification
        notify-send -i dialog-error \
          -h string:x-canonical-private-synchronous:$notification_id \
          "Recording Error" \
          "Failed to save MP4" \
          -t 3000
      fi
    fi
  else
    # Not the expected recording type
    notify-send -i dialog-error "Recording Error" "Different recording type active" -t 2000
  fi
else
  # No process running - start new recording
  # Get active window geometry as default
  active_geometry=$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null)

  # Get monitor geometries
  active_monitor_geometry=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | "\(.x),\(.y) \(.width)x\(.height)"')
  all_monitors_geometry=$(hyprctl monitors -j 2>/dev/null | jq -r 'map({x: .x, y: .y, w: .width, h: .height}) | (map(.x) | min) as $min_x | (map(.y) | min) as $min_y | (map(.x + .w) | max) as $max_x | (map(.y + .h) | max) as $max_y | "\($min_x),\($min_y) \($max_x - $min_x)x\($max_y - $min_y)"')

  # Show selection menu
  if [ -n "$active_geometry" ] && [ "$active_geometry" != "null,null 0x0" ]; then
    selection=$(printf "Active Window\nSelect Area\nActive Monitor\nAll Monitors" | walker --dmenu -p "Record ${record_type^^}")

    # Wait for walker to fully close before proceeding
    sleep 0.5

    case "$selection" in
    "Active Window")
      geometry="$active_geometry"
      ;;
    "Select Area")
      geometry=$(slurp 2>/dev/null)
      ;;
    "Active Monitor")
      geometry="$active_monitor_geometry"
      ;;
    "All Monitors")
      geometry="$all_monitors_geometry"
      ;;
    *)
      exit 0
      ;;
    esac
  else
    # No active window, show all options except Active Window
    selection=$(printf "Select Area\nActive Monitor\nAll Monitors" | walker --dmenu -p "Record ${record_type^^}")

    # Wait for walker to fully close before proceeding
    sleep 0.5

    case "$selection" in
    "Select Area")
      geometry=$(slurp 2>/dev/null)
      ;;
    "Active Monitor")
      geometry="$active_monitor_geometry"
      ;;
    "All Monitors")
      geometry="$all_monitors_geometry"
      ;;
    *)
      exit 0
      ;;
    esac
  fi

  if [ -n "$geometry" ]; then
    timestamp=$(date +"%Y-%m-%d--%H:%M:%S")
    record_name="record-$timestamp"

    # Mark recording type
    echo "$record_type" >"$record_type_file"

    # Add notification inhibitor for screen recording
    swaync-client --inhibitor-add "$inhibitor_name" >/dev/null 2>&1

    # Start recording
    if [ -n "$encode_resolution" ]; then
      wl-screenrec -g "$geometry" \
        -f "$record_dir/$record_name.mp4" \
        --encode-resolution "$encode_resolution" \
        --codec avc \
        --ffmpeg-encoder-options rc_mode=1,qp="$qp" &
    else
      wl-screenrec -g "$geometry" \
        -f "$record_dir/$record_name.mp4" \
        --codec avc \
        --ffmpeg-encoder-options rc_mode=1,qp="$qp" &
    fi

    # Now safe to show notification (won't appear in recording)
    notify-send -i "$icon" \
      -h string:x-canonical-private-synchronous:$notification_id \
      "🔴 Recording ${record_type^^}" \
      "Press $keybind to stop recording" \
      -t 0
  fi
fi
