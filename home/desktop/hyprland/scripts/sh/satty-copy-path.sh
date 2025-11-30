#!/bin/bash
set -euo pipefail

# Satty copy wrapper - saves image and copies path instead of image data
# This allows pasting file paths into terminals (like claude-code)

SCREENSHOT_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Generate filename with timestamp
FILENAME="satty-$(date +%Y-%m-%d_%H-%M-%S).png"
FILEPATH="$SCREENSHOT_DIR/$FILENAME"

# Read image data from stdin and save to file
cat >"$FILEPATH"

# Copy ONLY the file path to clipboard as text
# This allows pasting the path directly into terminals/editors
echo -n "$FILEPATH" | wl-copy
