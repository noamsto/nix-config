#!/bin/bash
set -euo pipefail

screenshot_dir="$HOME/Pictures/Screenshots"

if [ ! -d "$screenshot_dir" ]; then
  notify-send -i dialog-error "Screenshot" "Screenshots directory not found" -t 2000
  exit 1
fi

# Get the most recent screenshot
latest_file=$(find "$screenshot_dir" -name "*.png" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

if [ -z "$latest_file" ]; then
  notify-send -i dialog-error "Screenshot" "No screenshots found to edit" -t 2000
  exit 1
fi

# Open in satty for editing (requires satty package)
if command -v satty >/dev/null 2>&1; then
  satty -f "$latest_file"
elif command -v gwenview >/dev/null 2>&1; then
  # Fallback to gwenview image viewer
  gwenview "$latest_file"
else
  # Ultimate fallback to system default
  xdg-open "$latest_file"
fi
