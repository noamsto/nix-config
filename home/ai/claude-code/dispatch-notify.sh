#!/usr/bin/env bash
# SessionEnd backstop: if a worker session ends without having signalled, ping the dispatcher.
# Reads the hook JSON on stdin (.cwd is delivered for SessionEnd).
set -euo pipefail

event="$(cat)"
cwd="$(jq -r '.cwd // empty' <<<"$event")"
[[ -f "$cwd/WORKER_TASK.md" ]] || exit 0

pane="$(grep -m1 '^dispatcher_pane:' "$cwd/WORKER_TASK.md" | cut -d' ' -f2)"
[[ -n "$pane" ]] || exit 0
branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
tmux display-message -t "$pane" -d 4000 "worker exited: $branch — check state" 2>/dev/null || true
