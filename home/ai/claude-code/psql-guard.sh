#!/usr/bin/env bash
# PreToolUse hook: ask before destructive psql commands (DROP, TRUNCATE, DELETE, REVOKE).
# `ask` prompts a human when one is attached, and Claude Code auto-denies it
# when nothing can answer (auto mode, unattended -p runs). All other psql
# usage (SELECT, INSERT, CREATE, UPDATE, ALTER, etc.) is auto-approved.
# Non-psql commands are ignored (exit 0, no decision).

set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
[[ $tool_name == "Bash" ]] || exit 0

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -n $command ]] || exit 0

# Only handle commands involving psql
echo "$command" | grep -qE '(^|\s|;|\|)psql(\s|$)' || exit 0

# Normalize to uppercase for keyword matching
upper=$(echo "$command" | tr '[:lower:]' '[:upper:]')

# Destructive operations -> ask for confirmation
if echo "$upper" | grep -qP '\b(DROP|TRUNCATE|DELETE|REVOKE)\b'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: "Destructive psql command (DROP/TRUNCATE/DELETE/REVOKE) requires confirmation."
    }
  }'
  exit 0
fi

# Everything else (SELECT, INSERT, CREATE, UPDATE, ALTER, \d, -l, etc.) -> allow
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "Non-destructive psql command."
  }
}'
