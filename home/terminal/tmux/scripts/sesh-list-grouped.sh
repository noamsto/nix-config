#!/usr/bin/env bash
# List sessions using sesh with deduplication
# Simple passthrough to sesh with duplicate removal

set -euo pipefail

# Helper to strip ANSI color codes for comparison
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

# Track seen sessions to avoid duplicates
declare -A seen_sessions

# Get sessions with sesh's built-in icons
sesh list -t -z -c --icons 2>/dev/null | while IFS= read -r line; do
  # Skip empty lines
  [[ -z $line ]] && continue

  # Extract session name (last field) for duplicate checking
  clean_line=$(echo "$line" | strip_ansi)
  session_name=$(echo "$clean_line" | awk '{print $NF}')

  # Skip if we've already seen this session
  if [[ -n ${seen_sessions[$session_name]:-} ]]; then
    continue
  fi
  seen_sessions[$session_name]=1

  # Output line as-is with sesh's icons
  echo "$line"
done | LC_ALL=C sort
