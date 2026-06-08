#!/usr/bin/env bash
# PreToolUse hook: warn before `git commit` when unstaged tracked changes coexist
# with staged changes. pre-commit stashes the unstaged hunks, which makes the
# commit look like it retried. Advisory only (exit 0) — never blocks the commit.

set -euo pipefail

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ $tool_name == "Bash" ]] || exit 0

command=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -n $command ]] || exit 0

# git runs in the intercepted command's cwd, not the hook process's cwd.
cwd=$(jq -r '.cwd // empty' 2>/dev/null <<<"$input" || true)
cwd=${cwd:-$PWD}

# Only handle git commit (not `git commit-tree`, `git committed`, etc.)
echo "$command" | grep -qE '(^|\s)git\s+commit(\s|$)' || exit 0

# `-a`/`--all` stages tracked changes itself, so no surprise stash happens.
# Matches a short-flag cluster containing `a` (-a, -am, -av) or --all anywhere
# in the command. Advisory-only, so a stray `-a` inside a commit message that
# wrongly suppresses the hint is acceptable.
echo "$command" | grep -qE '(\s-[a-zA-Z]*a[a-zA-Z]*(\s|$)|\s--all(\s|=|$))' && exit 0

git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Surprise stash only happens when staged AND unstaged tracked changes coexist.
git -C "$cwd" diff --cached --quiet 2>/dev/null && exit 0
git -C "$cwd" diff --quiet 2>/dev/null && exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: "Unstaged tracked changes present alongside staged changes — pre-commit will stash them, so the commit may look like it retried. Run `git add -u` first, or use `git commit -a`, if you meant to include them."
  }
}'
