#!/usr/bin/env bash
# Extract session name from sesh output with icon
# Usage: sesh-extract-name "󰒜 session-name"

set -euo pipefail

input="$1"

# Strip ANSI codes
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}
clean=$(strip_ansi <<<"$input")

# Remove first field (icon) if present
# Check if starts with non-alphanumeric (icon)
if [[ ! ${clean:0:1} =~ ^[a-zA-Z0-9/._-]$ ]]; then
  # Has icon - remove it
  echo "$clean" | awk '{for(i=2;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":""); print ""}' | xargs
else
  # No icon - use as-is
  echo "$clean" | xargs
fi
