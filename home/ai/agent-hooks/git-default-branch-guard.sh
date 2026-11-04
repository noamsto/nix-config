#!/usr/bin/env bash
# PreToolUse hook: block `git commit` when HEAD is the repo's default branch.
# New work belongs on its own branch/worktree (see CLAUDE.md "Worktree
# Isolation") — committing straight to main is what produces stray-main commits
# when multiple sessions share one checkout. For a deliberate default-branch
# commit, launch the agent with ALLOW_COMMIT_ON_DEFAULT=1 in its environment.

set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
[[ $tool_name == "Bash" ]] || exit 0

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -n $command ]] || exit 0

# Only handle git commit (not `git commit-tree`, `git committed`, etc.)
echo "$command" | grep -qE '(^|\s)git\s+commit(\s|$)' || exit 0

# Explicit, deliberate override — from the hook's own env, never the command
# string: an override the agent can type for itself is no override.
[[ ${ALLOW_COMMIT_ON_DEFAULT:-} == 1 ]] && exit 0

# git runs in the intercepted command's cwd, not the hook process's cwd.
cwd=$(jq -r '.cwd // empty' <<<"$input" || true)
cwd=${cwd:-$PWD}

# The Bash tool resets its cwd to the project root before each call, so a
# worktree commit arrives as `cd <worktree> && git commit …` (or
# `git -C <worktree> commit …`) while the reported cwd is still the
# default-branch checkout. Checking that cwd then flags a commit that actually
# lands in the worktree — the source of the false positives. Resolve the
# directory the commit truly runs in before reading its branch.
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

# Detached HEAD isn't a branch commit — leave it alone.
current=$(git -C "$target" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
[[ -n $current ]] || exit 0

# Prefer the remote's advertised default; fall back to main/master.
default=$(git -C "$target" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
if [[ -z $default ]]; then
  if git -C "$target" show-ref --verify --quiet refs/heads/main; then
    default=main
  elif git -C "$target" show-ref --verify --quiet refs/heads/master; then
    default=master
  fi
fi

[[ -n $default && $current == "$default" ]] || exit 0

jq -n --arg branch "$current" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Refusing to commit directly to the default branch (\($branch)). New work belongs on its own branch/worktree — run `wt switch -c <branch-name>` first, then commit. To allow default-branch commits for a whole session, launch the agent with ALLOW_COMMIT_ON_DEFAULT=1 in its environment — prefixing this command with it will not work.")
  }
}'
