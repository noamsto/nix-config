#!/bin/bash
set -euo pipefail

# Satty copy wrapper - saves image and copies image data to clipboard
# This allows pasting images directly into apps and claude-code

SCREENSHOT_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Generate filename with timestamp
FILENAME="satty-$(date +%Y-%m-%d_%H-%M-%S).png"
FILEPATH="$SCREENSHOT_DIR/$FILENAME"

# Read image data from stdin and save to file
cat >"$FILEPATH"

# Copy the image data to clipboard (for pasting into apps)
wl-copy --type image/png <"$FILEPATH"
