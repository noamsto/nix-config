#!/usr/bin/env bash
# PreToolUse hook: block destructive psql commands (DROP, TRUNCATE, DELETE, REVOKE)
# All other psql usage (SELECT, INSERT, CREATE, UPDATE, ALTER, etc.) is auto-approved.
# Non-psql commands are ignored (exit 0, no decision).

set -euo pipefail

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ $tool_name == "Bash" ]] || exit 0

command=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -n $command ]] || exit 0

# Only handle commands involving psql
echo "$command" | grep -qE '(^|\s|;|\|)psql(\s|$)' || exit 0

# Normalize to uppercase for keyword matching
upper=$(echo "$command" | tr '[:lower:]' '[:upper:]')

# Destructive operations -> fall through to permission prompt
if echo "$upper" | grep -qP '\b(DROP|TRUNCATE|DELETE|REVOKE)\b'; then
  exit 0
fi

# Everything else (SELECT, INSERT, CREATE, UPDATE, ALTER, \d, -l, etc.) -> allow
echo '{"decision":"allow"}'
