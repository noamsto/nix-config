#!/usr/bin/env bash
# PreToolUse hook: block `git commit` when HEAD is the repo's default branch.
# New work belongs on its own branch/worktree (see CLAUDE.md "Worktree
# Isolation") — committing straight to main is what produces stray-main commits
# when multiple sessions share one checkout. Set ALLOW_COMMIT_ON_DEFAULT=1 for a
# deliberate default-branch commit.

set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
[[ $tool_name == "Bash" ]] || exit 0

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -n $command ]] || exit 0

# Only handle git commit (not `git commit-tree`, `git committed`, etc.)
echo "$command" | grep -qE '(^|\s)git\s+commit(\s|$)' || exit 0

# Explicit, deliberate override.
[[ ${ALLOW_COMMIT_ON_DEFAULT:-} == 1 ]] && exit 0

# git runs in the intercepted command's cwd, not the hook process's cwd.
cwd=$(jq -r '.cwd // empty' <<<"$input" || true)
cwd=${cwd:-$PWD}

git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Detached HEAD isn't a branch commit — leave it alone.
current=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
[[ -n $current ]] || exit 0

# Prefer the remote's advertised default; fall back to main/master.
default=$(git -C "$cwd" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
if [[ -z $default ]]; then
  if git -C "$cwd" show-ref --verify --quiet refs/heads/main; then
    default=main
  elif git -C "$cwd" show-ref --verify --quiet refs/heads/master; then
    default=master
  fi
fi

[[ -n $default && $current == "$default" ]] || exit 0

jq -n --arg branch "$current" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Refusing to commit directly to the default branch (\($branch)). New work belongs on its own branch/worktree — run `wt switch -c <branch-name>` first, then commit. Set ALLOW_COMMIT_ON_DEFAULT=1 for a deliberate default-branch commit.")
  }
}'
