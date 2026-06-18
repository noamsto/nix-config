#!/usr/bin/env bash
# PostToolUse hook (Skill): when the deslop skill is invoked, record a
# per-session, per-branch sentinel so deslop-guard lets the next `git push` /
# `gh pr create` on that branch through. Pairs with deslop-guard.sh.
#
# The sentinel marks "deslop was invoked this session on this branch" — the
# Skill PostToolUse fires when the skill loads, not when the review finishes,
# so this is a forcing function, not proof the cleanup completed.

set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
[[ $tool_name == "Skill" ]] || exit 0

# Plugin-qualified skills arrive as "plugin:deslop"; match the bare name too.
skill=$(jq -r '.tool_input.skill // empty' <<<"$input")
[[ $skill == "deslop" || $skill == *:deslop ]] || exit 0

session=$(jq -r '.session_id // empty' <<<"$input")
[[ -n $session ]] || exit 0

cwd=$(jq -r '.cwd // empty' <<<"$input")
cwd=${cwd:-$PWD}

git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
[[ -n $branch ]] || exit 0

dir="${TMPDIR:-/tmp}/claude-deslop/$session"
mkdir -p "$dir"
# Sanitize the branch (feat/foo -> feat%2Ffoo) so it is a single filename.
safe=${branch//\//%2F}
: >"$dir/$safe"
