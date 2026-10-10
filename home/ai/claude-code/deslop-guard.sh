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

# Same-length copy of $1 with command separators inside quotes replaced by `_`,
# so quoted text (`-m 'a; cd x'`, `-m "git push later"`) can't pose as structure.
mask_quoted() {
  local s=$1 out="" q="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [[ -n $q ]]; then
      [[ $c == "$q" ]] && q=""
      [[ $c == [\;\&\|$'\n'] ]] && c=_
    elif [[ $c == [\"\'] ]]; then
      q=$c
    fi
    out+=$c
  done
  printf '%s' "$out"
}

# Resolve the directory the gated command truly runs in, so the branch matches
# what deslop-mark recorded: the push's own `git -C <dir>`, else the nearest `cd
# <dir>` before it. An earlier `git -C`/`cd` aimed at another checkout must not
# decide which repo is checked.
push_re='(^|[[:space:]])git[[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+|-[^[:space:]]+[[:space:]]+)*push([[:space:]]|$)'
gh_re='(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'
dq='"' sq="'"
path_re="(${dq}[^${dq}]+${dq}|${sq}[^${sq}]+${sq}|[^[:space:];&|]+)"
target=$cwd
anchor=""
masked=$(mask_quoted "$command")
if [[ $masked =~ $push_re ]]; then
  anchor=${BASH_REMATCH[0]}
  if [[ $anchor =~ git[[:space:]]+(.*[[:space:]])?-C[[:space:]]+$path_re ]]; then
    target=${BASH_REMATCH[2]}
    anchor=""
  fi
elif [[ $masked =~ $gh_re ]]; then
  anchor=${BASH_REMATCH[0]}
fi
if [[ -n $anchor ]]; then
  before_anchor=${masked%%"$anchor"*}
  cd_re="^[[:space:]]*(([{(!]|if|then|do|else|elif|while|until|command|builtin)[[:space:]]*)*cd[[:space:]]+$path_re"
  while IFS= read -r seg; do
    if [[ $seg =~ $cd_re ]]; then
      dir=${BASH_REMATCH[3]}
      dir=${dir#[\"\']}
      dir=${dir%[\"\']}
      if [[ $dir == /* ]]; then target=$dir; else target=$target/$dir; fi
    fi
  done < <(tr ';&|' '\n' <<<"$before_anchor")
fi
target=${target#[\"\']}
target=${target%[\"\']}
[[ $target == /* ]] || target=$cwd/$target

git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# `gh pr create --repo`/`-R` can target a different repository than `target`'s
# local checkout — the cross-repo git-common-dir fallback further down never
# fires here, since target == cwd for this command. Parse --repo/-R directly:
# if it names a repo other than target's origin, the local branch isn't what's
# being reviewed, so skip the gate (no network call — origin comes from the
# local git config).
normalize_repo() {
  local url=$1
  url=${url%.git}
  url=${url%/}
  url=${url#*://}
  url=${url##*@}
  url=${url/:/\/}
  while [[ $url == */*/* ]]; do
    url=${url#*/}
  done
  printf '%s' "${url,,}"
}

if echo "$command" | grep -qE '(^|\s)gh\s+pr\s+create(\s|$)'; then
  repo_flag=""
  # Tokenize with the shell's own quoting rules (via xargs) rather than
  # regex-scanning the raw string, so `--repo=` text embedded inside an
  # unrelated quoted --title/--body argument can't be mistaken for the flag.
  prev=""
  while IFS= read -r tok; do
    if [[ $prev == "--repo" || $prev == "-R" ]]; then
      repo_flag=$tok
      break
    fi
    case $tok in
    --repo=*) repo_flag=${tok#--repo=} ;;
    -R=*) repo_flag=${tok#-R=} ;;
    esac
    [[ -n $repo_flag ]] && break
    prev=$tok
  done < <(xargs -n1 <<<"$command" 2>/dev/null || true)
  if [[ -n $repo_flag ]]; then
    origin_url=$(git -C "$target" remote get-url origin 2>/dev/null || true)
    if [[ -n $origin_url ]]; then
      [[ $(normalize_repo "$origin_url") != "$(normalize_repo "$repo_flag")" ]] && exit 0
    fi
  fi
fi

# Tag-only pushes carry no branch commits to review, so the deslop gate doesn't
# apply — the deploy flow here is all tag pushes (`git push origin v*-…`). Skip
# the gate when every pushed refspec resolves to a tag (or deletes one) and no
# flag drags commits along. A tag created earlier in the same command counts:
# this hook runs before the command, so the ref doesn't exist yet. Bare
# `git push` (current branch), any branch refspec, --follow-tags/--all/--mirror/
# --branches, a second push, and `gh pr create` fall through to the gate.
# Tag names a segment creates: `git [globals] tag [flags] <name>`, skipping
# list/delete/verify modes.
created_tags_in() {
  local -a t=()
  local i=0 n name listing=false tok
  mapfile -t t < <(xargs -n1 <<<"$1" 2>/dev/null || true)
  n=${#t[@]}
  while ((i < n)) && [[ ${t[i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i + 1)); done
  ((i < n)) && [[ ${t[i]} == git ]] || return 0
  i=$((i + 1))
  while ((i < n)) && [[ ${t[i]} == -* ]]; do
    case ${t[i]} in -C | -c) i=$((i + 2)) ;; *) i=$((i + 1)) ;; esac
  done
  ((i < n)) && [[ ${t[i]} == tag ]] || return 0
  i=$((i + 1))
  name=""
  while ((i < n)); do
    tok=${t[i]}
    case $tok in
    -m | -F | -u | --message | --file | --local-user | --trailer | --cleanup | --color) i=$((i + 1)) ;;
    -d | --delete | -l | --list | -v | --verify | -n* | --contains* | --no-contains* | --points-at* | --merged* | --no-merged* | --sort* | --format*) listing=true ;;
    -*) : ;;
    *)
      name=$tok
      break
      ;;
    esac
    i=$((i + 1))
  done
  [[ $listing == false && -n $name ]] && printf '%s\n' "$name"
  return 0
}

is_push=false
refspecs=() push_remote=""
if [[ $command =~ $push_re ]]; then
  is_push=true
  match=${BASH_REMATCH[0]}
  before=${command%%"$match"*}
  after=${command#*"$match"} # args after the `push` word
  # Drop redirections (`2>&1`, `&>f`, `> f`, `<f`) so they aren't read as refspecs.
  after=$(sed -E 's/(^|[[:space:]])(&>>?|[0-9]*[<>]+\|?&?)[[:space:]]*[^[:space:];&|]*/ /g' <<<"$after")
  # A redirect glued to a word (`v1>/dev/null`) is cut off the word.
  after=$(sed -E 's/([^[:space:]])[<>][^[:space:];&|]*/\1/g' <<<"$after")
  args=${after%%[;&|$'\n']*} # ignore anything past a shell separator
  rest=${after#"$args"}

  created_tags=()
  while IFS= read -r seg; do
    while IFS= read -r name; do
      [[ -n $name ]] && created_tags+=("$name")
    done < <(created_tags_in "$seg")
  done < <(tr ';&|' '\n' <<<"$before")

  is_tag() {
    local x
    # A name that is also a local branch may belong to a `git tag` that never
    # ran (or ran elsewhere), so only a pre-existing tag counts then.
    git -C "$target" rev-parse --verify --quiet "refs/tags/$1" >/dev/null 2>&1 && return 0
    for x in "${created_tags[@]}"; do
      [[ $x == "$1" ]] &&
        ! git -C "$target" rev-parse --verify --quiet "refs/heads/$1" >/dev/null 2>&1 && return 0
    done
    return 1
  }

  read -ra ptoks <<<"$args"
  carries_commits=false saw_remote=false saw_refspec=false tag_only=true
  for tok in "${ptoks[@]}"; do
    case $tok in
    --follow-tags | --all | --mirror | --branches) carries_commits=true ;;
    --tags) saw_refspec=true ;; # all tags, no branch
    -*) : ;;                    # other flags (-f, --force-with-lease, …)
    *)
      if [[ $saw_remote == false ]]; then
        saw_remote=true # first positional is the remote
        push_remote=$tok
      else
        saw_refspec=true
        refspecs+=("$tok")
        ref=${tok#+}                 # strip force '+'
        src=${ref%%:*} dst=${ref#*:} # split a src:dst refspec
        if [[ $src == *[~^*]* ]]; then
          tag_only=false # peeled/globbed source may resolve to a branch tip
        elif [[ $ref == *:* && $dst != refs/tags/* ]]; then
          tag_only=false # destination must be a tag (also covers deletions)
        elif [[ -z $src ]]; then
          :
        elif [[ $src != refs/tags/* ]] && ! is_tag "$src"; then
          tag_only=false # branch or unknown ref
        fi
      fi
      ;;
    esac
  done
  if [[ $carries_commits == false && $saw_refspec == true && $tag_only == true &&
    ! $rest =~ $push_re ]] &&
    ! echo "$command" | grep -qE '(^|\s)gh\s+pr\s+create(\s|$)'; then
    exit 0
  fi
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

# A branch whose diff against its deslop base touches only non-source files has
# nothing for the skill to review, so the gate doesn't apply. The base mirrors
# the skill's own resolution (@{push}, @{upstream}, else merge-base main HEAD);
# it's captured under `if !` so a failing rev-parse can't trip `set -e` into a
# non-blocking hook error — which would fail open.
deslop_base() {
  git -C "$target" rev-parse --verify --quiet '@{push}' ||
    git -C "$target" rev-parse --verify --quiet '@{upstream}' ||
    git -C "$target" merge-base main HEAD
}

is_nonsource_path() {
  case $1 in
  *.json | *.lock | *.lockb | *.lock.toml | *.md | \
    *.yaml | *.yml | *.png | *.jpg | *.jpeg | *.gif | *.svg | *.webp | *.ico | \
    docs/*) return 0 ;;
  esac
  return 1
}

if ! base=$(deslop_base 2>/dev/null); then
  : # unresolvable base → today's deny
else
  # Nothing ahead of upstream (e.g. a branch merely behind it) leaves nothing to
  # review. Only for a push of the current branch to its own upstream: `gh pr
  # create` and pushes to another destination still need the gate.
  if [[ $is_push == true ]] && ! echo "$command" | grep -qE '(^|\s)gh\s+pr\s+create(\s|$)' &&
    { git -C "$target" rev-parse --verify --quiet '@{push}' ||
      git -C "$target" rev-parse --verify --quiet '@{upstream}'; } >/dev/null 2>&1 &&
    [[ $(git -C "$target" rev-list --count "$base"..HEAD 2>/dev/null) == 0 ]]; then
    to_upstream=true
    upstream_remote=$(git -C "$target" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
    upstream_remote=${upstream_remote%%/*}
    [[ -z $push_remote || $push_remote == "$upstream_remote" ]] || to_upstream=false
    for r in "${refspecs[@]}"; do
      [[ $r == "$branch" || $r == HEAD ]] || to_upstream=false
    done
    [[ $carries_commits == false && ! $rest =~ $push_re ]] || to_upstream=false
    [[ $to_upstream == true ]] && exit 0
  fi
  # Diff only the commits being pushed, not upstream's side of a diverged history.
  base=$(git -C "$target" merge-base "$base" HEAD 2>/dev/null || printf '%s' "$base")
  nonsource_only=true
  changed=0
  paths_left=0
  # `--name-status -z` emits a status token then one path (two for R/C), so a
  # source path removed by a rename is still judged.
  while IFS= read -r -d '' tok; do
    if ((paths_left > 0)); then
      paths_left=$((paths_left - 1))
      changed=$((changed + 1))
      if ! is_nonsource_path "$tok"; then
        nonsource_only=false
      fi
    elif [[ $tok =~ ^[A-Z][0-9]*$ ]]; then
      case $tok in
      R* | C*) paths_left=2 ;;
      *) paths_left=1 ;;
      esac
    fi
  done < <(git -C "$target" diff -z --name-status "$base"..HEAD 2>/dev/null)
  if ((changed > 0)) && [[ $nonsource_only == true ]]; then
    exit 0
  fi
fi

jq -n --arg branch "$branch" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Run the deslop skill on this branch (\($branch)) before pushing or opening a PR. Invoke the /deslop skill, commit the cleanup, then retry. Set ALLOW_PUSH_WITHOUT_DESLOP=1 to bypass.")
  }
}'
