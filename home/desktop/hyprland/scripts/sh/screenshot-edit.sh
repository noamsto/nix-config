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

# Open in swappy for editing (requires swappy package)
if command -v swappy >/dev/null 2>&1; then
    swappy -f "$latest_file"
else
    # Fallback to image viewer
    xdg-open "$latest_file"
fi
