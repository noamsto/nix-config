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

# Copy the file path to clipboard (instead of image data)
echo -n "$FILEPATH" | wl-copy

# Also copy the image data for apps that expect it (like browsers, image editors)
# This puts both the path (as text/plain) and image data (as image/png) in clipboard
wl-copy <"$FILEPATH" --type image/png &
