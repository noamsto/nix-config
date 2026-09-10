#!/usr/bin/env bash
# PreToolUse hook: keep hand-rolled tmux repros off the user's live server.
# Inside a pane $TMUX is set, so a bare `tmux new-session` builds on the live
# server: a detached one-window shell nobody attaches and nothing reaps, which
# resurfaces days later as a mystery session. `kill-server` is the same mistake
# with the whole server as the blast radius.
# Fires only on those verbs, only where tmux itself is the command being run and
# carries no socket selection. Reading the live server (list-sessions,
# capture-pane, …), any `-L`/`-S`/`TMUX_TMPDIR=` invocation, and a tmux command
# that is merely an argument (`rg 'tmux new-session'`) all pass through.

set -euo pipefail

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ $tool_name == "Bash" ]] || exit 0

command=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -n $command ]] || exit 0

# A private server dir anywhere in the command is the intended isolation, and
# LIVE_TMUX=1 is the deliberate opt-in for acting on the real server.
if echo "$command" | grep -qE 'TMUX_TMPDIR=|LIVE_TMUX=1'; then
  exit 0
fi

# Heredoc bodies are content, not commands — a bats fixture full of
# `tmux new-session` lines is the common case, so abstain rather than block it.
if [[ $command == *'<<'* ]]; then
  exit 0
fi

# Per-segment, because a command may isolate one tmux call and not the next.
# Splitting on the operator characters also splits `2>&1`, which only ever
# shortens a segment — the verb and the socket flag stay on the same side.
verb=""
while IFS= read -r segment; do
  read -ra words <<<"$segment"
  # Walk off the leading env assignments and wrappers (env/sudo/timeout and
  # their flags) so the command word is what's actually being executed.
  # `env -u NAME` also puts a bare variable name in front of the command.
  saw_env=""
  while [[ ${#words[@]} -gt 0 ]]; do
    case "${words[0]}" in
    env) saw_env=1 ;;
    *=* | -* | [0-9]* | exec | command | sudo | doas | nice | stdbuf | timeout) ;;
    *)
      [[ -n $saw_env && ${words[0]} =~ ^[A-Z_][A-Z0-9_]*$ ]] || break
      ;;
    esac
    words=("${words[@]:1}")
  done
  [[ ${#words[@]} -gt 0 ]] || continue
  # A leading path is still tmux, so ./result/bin/tmux is covered; "$T
  # new-session" is not, since $T carries its socket in the assignment.
  [[ $(basename "${words[0]}") == tmux ]] || continue

  socket=""
  found=""
  for word in "${words[@]:1}"; do
    case "$word" in
    -L* | -S*) socket=1 ;;
    new-session | new | kill-server) [[ -n $found ]] || found=$word ;;
    esac
  done
  if [[ -z $socket && -n $found ]]; then
    verb=$found
    break
  fi
done <<<"$(echo "$command" | tr ';&|\n' '\n')"

[[ -n $verb ]] || exit 0

reason="\`tmux $verb\` with no socket selection acts on the LIVE tmux server — a leaked scratch session nothing reaps, or (kill-server) the user's whole server. Re-issue on a private server: TMUX_TMPDIR=/tmp/lzt-\$\$ tmux -L probe $verb …, then kill-server it when the repro is done. To act on the real server on purpose, prefix the command with LIVE_TMUX=1."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
