#!/usr/bin/env bash
# PreToolUse hook: block `pgrep -f` / `pkill -f` without a bracket class.
# Run via `bash -c '<loop>'`, the pattern sits in that shell's own command line,
# so -f matches the waiting shell itself and the loop never ends. Only
# command-position uses are checked, so prose on the same line passes; a quoted
# line that starts with pgrep/pkill fails closed. `sh -c '<cmd>'` opens a new
# command position because the inner shell's argv holds the pattern too.

set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
[[ $tool_name == "Bash" ]] || exit 0

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -n $command ]] || exit 0

# A backslash-newline continuation is a space to the shell; join it so a
# flag on the next line stays in the same command.
continuation=$'\\\n'
command=${command//"$continuation"/ }

nl=$'\n'
prefix='(do|then|else|elif|while|until|if|!|\{|time|sudo|command|exec|env|nohup|timeout[[:space:]]+[0-9.]+[smhd]?|watch([[:space:]]+-[[:alnum:]-]+([[:space:]]+[0-9.]+)?)*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)'
shell_c='(ba|z|da|k)?sh[[:space:]]+-[[:alpha:]]*c[[:alpha:]]*[[:space:]]+["'"'"']'
re="(^|[;&|(\`${nl}]|\\$\\(|${shell_c})[[:space:]]*(${prefix}[[:space:]]+)*(/[^[:space:]]*/)?(pgrep|pkill)([[:space:]]|\$)"

set -f
rest=$command
while [[ $rest =~ $re ]]; do
  match=${BASH_REMATCH[0]}
  rest=${rest#*"$match"}
  segment=${rest%%[;&|)"$nl"]*}
  [[ $segment =~ \[[^]]+\] ]] && continue
  for token in $segment; do
    if [[ $token == --full || $token =~ ^-[[:alpha:]]*f[[:alpha:]]*$ ]]; then
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: "pgrep/pkill -f matches its own shell; use the bracket trick ('"'"'[b]ats'"'"') or wait on a captured pid (cmd & p=$!; wait $p)"
        }
      }'
      exit 0
    fi
  done
done
