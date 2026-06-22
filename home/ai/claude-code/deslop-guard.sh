#!/usr/bin/env bash
# PreToolUse hook: block `git push` and `gh pr create` until the deslop skill
# has run on this branch in the current session. deslop-mark.sh (PostToolUse on
# Skill) records the per-session, per-branch sentinel this guard checks for.
# A hook can't run the deslop review itself (that needs Claude to read the diff
# and edit) — it only forces /deslop to run first. Set
# ALLOW_PUSH_WITHOUT_DESLOP=1 for a deliberate bypass.

set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
[[ $tool_name == "Bash" ]] || exit 0

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -n $command ]] || exit 0

# `git push` (allowing `git -C <dir> push`, `git -c k=v push`, flags, args)
# or `gh pr create`.
gated=false
if echo "$command" | grep -qE '(^|\s)git\s+(-[Cc]\s+\S+\s+|-[^ ]+\s+)*push(\s|$)'; then
  gated=true
fi
if echo "$command" | grep -qE '(^|\s)gh\s+pr\s+create(\s|$)'; then
  gated=true
fi
[[ $gated == true ]] || exit 0

# Deliberate override.
[[ ${ALLOW_PUSH_WITHOUT_DESLOP:-} == 1 ]] && exit 0

session=$(jq -r '.session_id // empty' <<<"$input")
[[ -n $session ]] || exit 0

# git runs in the intercepted command's cwd, not the hook process's cwd.
cwd=$(jq -r '.cwd // empty' <<<"$input" || true)
cwd=${cwd:-$PWD}

# Resolve the directory the command truly runs in (cd / git -C), mirroring
# git-default-branch-guard, so the branch matches what deslop-mark recorded.
target=$cwd
if [[ $command =~ (^|[[:space:]])git[[:space:]]+-C[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^[:space:]]+) ]]; then
  target=${BASH_REMATCH[2]}
elif [[ $command =~ (^|[;&|][[:space:]]*|[[:space:]])cd[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^[:space:];&|]+) ]]; then
  target=${BASH_REMATCH[2]}
fi
target=${target#[\"\']}
target=${target%[\"\']}
[[ $target == /* ]] || target=$cwd/$target

git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
branch=$(git -C "$target" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
[[ -n $branch ]] || exit 0

safe=${branch//\//%2F}
[[ -f "${TMPDIR:-/tmp}/claude-deslop/$session/$safe" ]] && exit 0

# The per-branch sentinel is only recorded for worktrees of the session cwd's
# repo (deslop-mark). A push from a *different* repo's worktree can never match
# it, so fall back to the session-level marker: if deslop ran at all this
# session and the push targets a different repo than the session cwd, allow it.
# Same-repo pushes keep the strict per-branch requirement above.
git_common() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
if [[ -f "${TMPDIR:-/tmp}/claude-deslop/$session/.ran" && -n $(git_common "$target") && $(git_common "$target") != "$(git_common "$cwd")" ]]; then
  exit 0
fi

jq -n --arg branch "$branch" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Run the deslop skill on this branch (\($branch)) before pushing or opening a PR. Invoke the /deslop skill, commit the cleanup, then retry. Set ALLOW_PUSH_WITHOUT_DESLOP=1 to bypass.")
  }
}'
