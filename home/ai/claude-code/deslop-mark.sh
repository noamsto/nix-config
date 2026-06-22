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

dir="${TMPDIR:-/tmp}/claude-deslop/$session"
mkdir -p "$dir"

# Session-level marker: deslop ran at least once this session. The per-branch
# loop below only sees worktrees of the session cwd's repo, so a push from a
# *different* repo's worktree can never get a per-branch sentinel. deslop-guard
# falls back to this marker for that cross-repo case. A leading-dot name can
# never collide with a sanitized branch (git forbids refs beginning with '.').
: >"$dir/.ran"

# Mark every branch checked out across this repo's worktrees, not just the
# session cwd's branch. The skill runs from the session cwd — typically the main
# checkout on the default branch — while the work being reviewed (and the push
# that follows) happens in a `wt` worktree on a different branch (#16).
# deslop-guard resolves the push command's cd/git -C target branch, so marking
# only the session cwd's branch never matches it. Marking all worktree branches
# keeps the two in agreement; the per-session sentinel dir bounds the blast
# radius, and the marker is a forcing function, not proof the cleanup ran.
#
# `worktree list --porcelain` emits a `branch refs/heads/<name>` line per
# worktree (absent for detached HEADs, which deslop-guard also lets through).
while IFS= read -r line; do
  [[ $line == "branch refs/heads/"* ]] || continue
  branch=${line#branch refs/heads/}
  # Sanitize the branch (feat/foo -> feat%2Ffoo) so it is a single filename.
  safe=${branch//\//%2F}
  : >"$dir/$safe"
done < <(git -C "$cwd" worktree list --porcelain)
