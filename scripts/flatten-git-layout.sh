#!/usr/bin/env bash
# Migrate git worktrees from the old trees to the flat ~/git/.worktrees layout.
#
#   flatten-git-layout.sh            dry run: print the plan, change nothing
#   flatten-git-layout.sh --apply    perform the plan
#
# Per worktree under OLD_ROOTS:
#   remove  clean, nothing unpushed, and merged into origin's default branch or
#           its PR is MERGED/CLOSED. Uses `git worktree remove` without --force,
#           which still deletes git-ignored files (.env, .direnv, result links).
#   move    everything else, via `git worktree move`, then the matching
#           ~/.claude/projects dir (and its subdir siblings) is renamed too.
#   keep    locked, in use as any process's cwd, or the target already exists.
# ~/projects/* and ~/Projects are not worktrees: reported with a suggested target.
set -euo pipefail

OLD_ROOTS=("$HOME/Data/git/.worktrees" "$HOME/nix-config-worktrees")
NEW_ROOT="$HOME/git/.worktrees"
REPORT_ONLY=("$HOME/projects" "$HOME/Projects")
CLAUDE_PROJECTS="$HOME/.claude/projects"

apply=0
case "${1:-}" in
"") ;;
--apply) apply=1 ;;
-h | --help)
  sed -n '2,15p' "$0"
  exit 0
  ;;
*)
  echo "usage: $0 [--apply]" >&2
  exit 2
  ;;
esac

# Claude Code keys session dirs by cwd with every non-alphanumeric char as '-'.
encode() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
tilde() { printf '%s' "${1/#$HOME/\~}"; }

# True when any process has $1 (or a subdirectory) as its cwd. One readlink over
# all of /proc: a per-process bash loop takes minutes with many processes.
in_use() {
  local real
  real=$(realpath "$1")
  # readlink exits non-zero on other users' processes; keep awk's verdict only.
  { readlink /proc/[0-9]*/cwd 2>/dev/null || true; } |
    awk -v r="$real" '$0 == r || index($0, r "/") == 1 { found = 1 } END { exit !found }'
}

# Echo "<old dir>|<new dir>" session dir pairs for old path $1 moving to $2: the
# worktree itself plus sessions started in its subdirectories. Encoding is lossy,
# so subdirectory sessions are matched by encoding real subdirs, never by prefix
# (a prefix would also catch a sibling worktree such as feat-foo-bar).
session_pairs() { # $3: where the tree exists now (default $1)
  local old_enc new_enc sub d
  old_enc=$(encode "$1")
  new_enc=$(encode "$2")
  [[ -d $CLAUDE_PROJECTS ]] || return 0
  {
    printf '%s\n' "$old_enc"
    while IFS= read -r sub; do
      encode "$1/$sub"
      echo
    done < <(cd "${3:-$1}" && find . -mindepth 1 -maxdepth 4 -type d -not -path './.git' -not -path './.git/*' 2>/dev/null | sed 's|^\./||')
  } | sort -u | while IFS= read -r d; do
    [[ -n $d && -d $CLAUDE_PROJECTS/$d ]] || continue
    printf '%s|%s\n' "$CLAUDE_PROJECTS/$d" "$CLAUDE_PROJECTS/$new_enc${d#"$old_enc"}"
  done
}

declare -a W_PATH W_MAIN W_BRANCH W_DIRTY W_UNPUSHED W_MERGED W_ACTION W_TARGET W_CLAUDE

discover() {
  local root f dir top common main branch dirty unpushed merged action target default sha prs states
  local prs_state claude pair collision status
  for root in "${OLD_ROOTS[@]}"; do
    [[ -d $root ]] || continue
    while IFS= read -r f; do
      dir=${f%/.git}
      top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || continue
      [[ $top == "$(realpath "$dir")" ]] || continue
      common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
      [[ $common == */.git ]] || continue
      main=${common%/.git}
      [[ -d $main ]] || main=

      branch=$(git -C "$dir" symbolic-ref -q --short HEAD 2>/dev/null || true)
      if status=$(git -C "$dir" status --porcelain 2>/dev/null); then
        dirty=no
        [[ -z $status ]] || dirty=yes
      else
        dirty=unknown
      fi
      sha=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)

      default=
      if [[ -n $main ]]; then
        default=$(git -C "$main" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
        if [[ -z $default ]] && git -C "$main" rev-parse -q --verify refs/remotes/origin/main >/dev/null 2>&1; then
          default=origin/main
        fi
      fi

      # PR state is best effort: gh may be absent, offline, or origin not GitHub.
      prs_state=
      if [[ -n $branch && -n $main ]] && command -v gh >/dev/null 2>&1; then
        prs=$(cd "$main" && gh pr list --head "$branch" --state all --json state,headRefOid \
          --jq '.[] | "\(.state) \(.headRefOid)"' 2>/dev/null || true)
        states=$(printf '%s\n' "$prs" | awk '{print $1}')
        if grep -qx OPEN <<<"$states"; then
          prs_state=open
        elif grep -Eqx 'MERGED|CLOSED' <<<"$states"; then
          prs_state=closed
        fi
      fi

      unpushed=$(git -C "$dir" rev-list HEAD --not --remotes --count 2>/dev/null || echo 1)
      # A merged/closed PR whose head is this commit means the commits were pushed.
      if [[ $unpushed != 0 && $prs_state == closed && -n $sha ]] && grep -Eq "^(MERGED|CLOSED) $sha\$" <<<"$prs"; then
        unpushed=0
      fi

      merged=no
      if [[ -n $default && -n $sha ]] && git -C "$dir" merge-base --is-ancestor HEAD "$default" 2>/dev/null; then
        merged=yes
      elif [[ $prs_state == closed ]]; then
        merged=pr-closed
      fi
      # A branch sitting exactly on the default tip with no PR is likely brand new, not merged work.
      if [[ $merged == yes && $prs_state != closed && $sha == "$(git -C "$dir" rev-parse "$default" 2>/dev/null)" ]]; then
        merged=no
      fi

      if [[ -n $main ]]; then
        if [[ -n $branch ]]; then
          target="$NEW_ROOT/${branch//\//-}"
        else
          target="$NEW_ROOT/$(basename "$dir")"
        fi
        if [[ $dir == "$HOME/Data/git/.worktrees/"* ]]; then
          target="$NEW_ROOT/${dir#"$HOME/Data/git/.worktrees/"}"
        else
          # Same shape worktrunk uses: <basename of main's parent>/<main name>/<branch>
          target="$NEW_ROOT/$(basename "$(dirname "$main")")/$(basename "$main")/${target#"$NEW_ROOT/"}"
        fi
      else
        target=
      fi

      if [[ -z $main ]]; then
        action="keep (no main checkout)"
      elif in_use "$dir"; then
        action="keep (in use)"
      elif [[ -e $(git -C "$dir" rev-parse --path-format=absolute --git-dir)/locked ]]; then
        action="keep (locked)"
      elif [[ $dirty == unknown ]]; then
        action="keep (git status failed)"
      elif [[ $dirty == no && $unpushed == 0 && $merged != no ]]; then
        action=remove
      elif [[ -e $target ]]; then
        action="keep (target exists)"
      else
        action="move -> $(tilde "$target")"
      fi

      claude=-
      if [[ $action == move* ]]; then
        collision=0
        while IFS='|' read -r pair target_dir; do
          [[ -n $pair ]] || continue
          [[ -e $target_dir ]] && collision=1
          claude=rename
        done < <(session_pairs "$dir" "$target")
        ((collision)) && claude=collision
      fi

      W_PATH+=("$dir")
      W_MAIN+=("$main")
      W_BRANCH+=("${branch:-(detached)}")
      W_DIRTY+=("$dirty")
      W_UNPUSHED+=("$unpushed")
      W_MERGED+=("$merged")
      W_ACTION+=("$action")
      W_TARGET+=("$target")
      W_CLAUDE+=("$claude")
    done < <(find "$root" -mindepth 2 -maxdepth 4 -name .git -type f 2>/dev/null | sort)
  done
}

print_table() {
  local i
  {
    printf 'PATH\tREPO\tBRANCH\tDIRTY\tUNPUSHED\tMERGED\tCLAUDE\tACTION\n'
    for i in "${!W_PATH[@]}"; do
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(tilde "${W_PATH[i]}")" "$(tilde "${W_MAIN[i]:-?}")" "${W_BRANCH[i]}" \
        "${W_DIRTY[i]}" "${W_UNPUSHED[i]}" "${W_MERGED[i]}" "${W_CLAUDE[i]}" "${W_ACTION[i]}"
    done
  } | column -t -s $'\t'
}

rename_sessions() {
  local pair old new
  while IFS='|' read -r old new; do
    [[ -n $old ]] || continue
    if [[ -e $new ]]; then
      echo "  claude: collision, skipped $(tilde "$old") -> $(tilde "$new")"
    elif mv -T "$old" "$new"; then
      echo "  claude: renamed $(tilde "$old") -> $(tilde "$new")"
    else
      echo "  claude: rename failed for $(tilde "$old")"
    fi
  done < <(session_pairs "$1" "$2" "$2")
}

apply_plan() {
  local i dir main branch action target
  local -A repos=()
  for i in "${!W_PATH[@]}"; do
    dir=${W_PATH[i]}
    main=${W_MAIN[i]}
    branch=${W_BRANCH[i]}
    action=${W_ACTION[i]}
    target=${W_TARGET[i]}
    case $action in
    remove | move*)
      if in_use "$dir"; then
        echo "keep (in use, started since the plan): $(tilde "$dir")"
        continue
      fi
      ;;
    esac
    case $action in
    remove)
      if git -C "$main" worktree remove "$dir"; then
        echo "removed $(tilde "$dir")"
        repos[$main]=1
        if [[ $branch != "(detached)" && ${W_MERGED[i]} == yes ]]; then
          git -C "$main" branch -d "$branch" 2>&1 | sed 's/^/  /' || true
        fi
      else
        echo "remove failed: $(tilde "$dir")"
      fi
      ;;
    move*)
      mkdir -p "$(dirname "$target")"
      if git -C "$main" worktree move "$dir" "$target"; then
        echo "moved $(tilde "$dir") -> $(tilde "$target")"
        repos[$main]=1
        rename_sessions "$dir" "$target"
      else
        echo "move failed: $(tilde "$dir")"
      fi
      ;;
    *) echo "$action: $(tilde "$dir")" ;;
    esac
  done

  for main in "${!repos[@]}"; do
    git -C "$main" worktree prune
  done

  local root d
  for root in "${OLD_ROOTS[@]}"; do
    [[ -d $root ]] || continue
    while IFS= read -r d; do
      rmdir "$d" && echo "removed empty dir $(tilde "$d")"
    done < <(find "$root" -mindepth 1 -depth -type d -empty 2>/dev/null)
    if [[ -z $(ls -A "$root") ]]; then
      echo "old root is now empty (left in place): $(tilde "$root")"
    fi
  done
}

report_only() {
  local root e name url slug
  for root in "${REPORT_ONLY[@]}"; do
    [[ -d $root ]] || continue
    echo
    echo "== not worktrees, report only: $(tilde "$root")"
    shopt -s nullglob
    local entries=("$root"/*)
    shopt -u nullglob
    if ((${#entries[@]} == 0)); then
      echo "  (empty) remove manually if unused"
      continue
    fi
    for e in "${entries[@]}"; do
      name=$(basename "$e")
      url=$(git -C "$e" remote get-url origin 2>/dev/null || true)
      slug=$(sed -E 's#^.*[:/]([^/:]+/[^/]+)$#\1#; s#\.git$##' <<<"$url")
      [[ -n $url ]] || slug="noamsto/$name"
      echo "  $(tilde "$e") -> suggest $(tilde "$HOME/git/$slug")"
    done
  done
}

discover
if ((${#W_PATH[@]} == 0)); then
  echo "no worktrees found under: ${OLD_ROOTS[*]}"
else
  print_table
fi
report_only

if ((apply)); then
  echo
  echo "== apply"
  apply_plan
else
  echo
  echo "dry run: nothing changed. Re-run with --apply to perform the plan."
fi
