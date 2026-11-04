#!/bin/bash
set -euo pipefail

# Post-processor for Noctalia screen recordings
# Watches Videos directory and offers GIF conversion via vicinae dmenu
# Usage: recording-post-processor.sh

WATCH_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}"
TEMP_MARKER="$HOME/.cache/recording-processing"

# Ensure watch directory exists
mkdir -p "$WATCH_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Process a newly created recording
process_recording() {
  local file="$1"
  local filename
  filename=$(basename "$file")

  log "Processing new recording: $filename"

  # Wait a moment for file to be fully written
  sleep 1

  # Verify it's a valid video file
  if ! ffprobe "$file" >/dev/null 2>&1; then
    log "Invalid video file, skipping: $filename"
    return
  fi

  # Check if already processing (prevent duplicate dialogs)
  if [ -f "$TEMP_MARKER" ]; then
    log "Already processing a recording, skipping"
    return
  fi

  touch "$TEMP_MARKER"

  # Launch vicinae via a helper script in Hyprland's session context
  # (vicinae won't show a window when launched directly from a systemd service)
  local choice_file="$HOME/.cache/recording-choice"
  rm -f "$choice_file"

  # Write a helper script that vicinae runs in the graphical session
  local helper="/tmp/recording-dmenu-helper.sh"
  cat >"$helper" <<HELPER
#!/bin/bash
choice=\$(printf "Keep as MP4\nConvert to GIF" | vicinae dmenu -p "Recording saved: $filename")
echo "\$choice" > "$choice_file"
HELPER
  chmod +x "$helper"

  # Launch via hyprctl so it runs in the compositor session
  hyprctl dispatch "hl.dsp.exec_cmd(\"$helper\")"

  # Wait for the user to make a choice (timeout after 60s)
  local waited=0
  while [ ! -f "$choice_file" ] && [ "$waited" -lt 60 ]; do
    sleep 1
    waited=$((waited + 1))
  done

  if [ -f "$choice_file" ]; then
    choice=$(cat "$choice_file")
    rm -f "$choice_file"
  else
    choice=""
    log "Timed out waiting for user choice"
  fi

  case "$choice" in
  "Keep as MP4")
    log "User chose to keep MP4"
    # Copy MP4 to clipboard
    wl-copy -t text/uri-list "file://$file"
    notify-send -i "󰐌" "Recording Saved" "MP4 copied to clipboard: $filename" -t 3000
    ;;
  "Convert to GIF")
    log "User chose to convert to GIF"
    convert_to_gif "$file"
    ;;
  *)
    log "User cancelled"
    ;;
  esac

  rm -f "$TEMP_MARKER" "$helper"
}

# Convert MP4 to optimized GIF
convert_to_gif() {
  local mp4_file="$1"
  local gif_file="${mp4_file%.mp4}.gif"
  local filename
  filename=$(basename "$gif_file")

  log "Converting to GIF: $filename"

  # Show processing notification
  notify-send -i "󰹑" \
    -h string:x-canonical-private-synchronous:recording-gif \
    "Converting to GIF" \
    "Processing $filename..." \
    -t 0

  # Convert to GIF with optimization using two-pass palette generation
  if ffmpeg -i "$mp4_file" \
    -vf "fps=24,palettegen" \
    -y "/tmp/palette.png" \
    -v quiet 2>/dev/null; then

    if ffmpeg -i "$mp4_file" -i "/tmp/palette.png" \
      -filter_complex "fps=24[x];[x][1:v]paletteuse" \
      -y "$gif_file" \
      -v quiet 2>/dev/null; then

      conversion_success=true
      log "Conversion successful"
    else
      conversion_success=false
      log "Conversion failed (second pass)"
    fi
  else
    conversion_success=false
    log "Conversion failed (palette generation)"
  fi

  if [ "$conversion_success" = true ] && [ -f "$gif_file" ]; then
    # Clean up
    rm -f "$mp4_file" "/tmp/palette.png"

    # Copy to clipboard and show completion
    wl-copy -t text/uri-list "file://$gif_file"
    notify-send -i "󰹑" \
      -h string:x-canonical-private-synchronous:recording-gif \
      "GIF Complete" \
      "GIF created and copied to clipboard: $filename" \
      -t 3000
  else
    # Clean up failed conversion
    rm -f "/tmp/palette.png"
    notify-send -i dialog-error \
      -h string:x-canonical-private-synchronous:recording-gif \
      "GIF Conversion Failed" \
      "Could not convert MP4 to GIF" \
      -t 3000
  fi
}

# Watch directory for new recordings
watch_recordings() {
  log "Starting recording post-processor"
  log "Watching directory: $WATCH_DIR"

  # Use inotifywait to watch for new files
  inotifywait -m -e close_write --format '%w%f' "$WATCH_DIR" | while read -r file; do
    # Only process video files (mp4, webm, mkv)
    case "$file" in
    *.mp4 | *.webm | *.mkv)
      process_recording "$file"
      ;;
    esac
  done
}

# Main entry point
main() {
  # Clean up any stale marker
  rm -f "$TEMP_MARKER"

  # Check if inotify-tools is available
  if ! command -v inotifywait >/dev/null 2>&1; then
    log "Error: inotify-tools not found. Please install it."
    exit 1
  fi

  # Start watching
  watch_recordings
}

main "$@"
