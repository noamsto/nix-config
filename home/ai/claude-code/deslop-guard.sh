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

# Deliberate override. Honor it both as a hook-process env var and as an inline
# prefix in the intercepted command — env vars set inline (`ALLOW_…=1 git push`)
# reach only the git subprocess, never this hook, so the documented bypass is
# otherwise unusable from an agent (#25).
[[ ${ALLOW_PUSH_WITHOUT_DESLOP:-} == 1 ]] && exit 0
[[ $command =~ (^|[[:space:]])ALLOW_PUSH_WITHOUT_DESLOP=1([[:space:]]|$) ]] && exit 0

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

# Tag-only pushes carry no branch commits to review, so the deslop gate doesn't
# apply — the deploy flow here is all tag pushes (`git push origin v*-…`). Skip
# the gate when every pushed refspec resolves to a tag (or deletes one) and no
# flag drags commits along. Bare `git push` (current branch), any branch
# refspec, and --follow-tags/--all/--mirror/--branches fall through to the gate.
if echo "$command" | grep -qE '(^|\s)git\s+(-[Cc]\s+\S+\s+|-[^ ]+\s+)*push(\s|$)'; then
  after=${command#*push} # args after the `push` word
  after=${after%%[;&|]*} # ignore anything past a shell separator
  read -ra ptoks <<<"$after"
  carries_commits=false saw_remote=false saw_refspec=false tag_only=true
  for tok in "${ptoks[@]}"; do
    case $tok in
    --follow-tags | --all | --mirror | --branches) carries_commits=true ;;
    --tags) saw_refspec=true ;; # all tags, no branch
    -*) : ;;                    # other flags (-f, --force-with-lease, …)
    *)
      if [[ $saw_remote == false ]]; then
        saw_remote=true # first positional is the remote
      else
        saw_refspec=true
        ref=${tok#+}                 # strip force '+'
        src=${ref%%:*} dst=${ref#*:} # split a src:dst refspec
        if [[ -z $src ]]; then
          [[ $dst == refs/tags/* ]] || tag_only=false # deletion — safe only for a tag
        elif [[ $src != refs/tags/* ]] &&
          ! git -C "$target" rev-parse --verify --quiet "refs/tags/$src" >/dev/null 2>&1; then
          tag_only=false # branch or unknown ref
        fi
      fi
      ;;
    esac
  done
  [[ $carries_commits == false && $saw_refspec == true && $tag_only == true ]] && exit 0
fi

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
