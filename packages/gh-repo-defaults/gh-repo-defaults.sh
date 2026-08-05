#!/usr/bin/env bash
# House GitHub repo settings: squash-only merges, auto-delete branch on merge,
# auto-merge enabled. Idempotent — safe to re-run over the whole account.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  gh-repo-defaults <owner/repo>...       apply to the named repos
  gh-repo-defaults --all                 apply to every owned, non-fork, non-archived repo
  gh-repo-defaults --check [--all|<owner/repo>...]
                                         report drift only, exit 1 if any

Applies: squash-only merges (merge-commit and rebase disabled), delete branch
on merge, allow auto-merge.

Auto-merge is a public-repo-only feature on the GitHub free plan. The API
accepts the write and silently keeps it off, so private repos on free are
reported as "auto-merge unavailable" rather than counted as applied.
EOF
}

owned_repos() {
  gh api "user/repos?affiliation=owner&per_page=100" --paginate \
    --jq '.[] | select(.archived == false and .fork == false) | .full_name' | sort
}

state_of() {
  gh api "repos/$1" \
    --jq '[.private, .allow_squash_merge, .allow_merge_commit, .allow_rebase_merge, .delete_branch_on_merge, .allow_auto_merge] | map(tostring) | @tsv'
}

apply_to() {
  gh api -X PATCH "repos/$1" \
    -F allow_squash_merge=true \
    -F allow_merge_commit=false \
    -F allow_rebase_merge=false \
    -F delete_branch_on_merge=true \
    -F allow_auto_merge=true >/dev/null
}

# Auto-merge the plan cannot grant is not drift — nothing would fix it.
drift_of() {
  local private=$1 squash=$2 merge=$3 rebase=$4 delete=$5 auto=$6
  local -a drift=()

  [[ $squash == true ]] || drift+=("squash-merge off")
  [[ $merge == false ]] || drift+=("merge-commit on")
  [[ $rebase == false ]] || drift+=("rebase-merge on")
  [[ $delete == true ]] || drift+=("delete-branch-on-merge off")
  if [[ $auto != true ]] && ! automerge_blocked "$private"; then
    drift+=("auto-merge off")
  fi

  local item out=""
  for item in ${drift[@]+"${drift[@]}"}; do
    out+="${out:+, }$item"
  done
  printf '%s' "$out"
}

automerge_blocked() {
  [[ $1 == true && $PLAN == free ]]
}

main() {
  local check=0 all=0
  local -a repos=()

  while (($# > 0)); do
    case $1 in
    --check) check=1 ;;
    --all) all=1 ;;
    -h | --help)
      usage
      return 0
      ;;
    -*)
      printf 'gh-repo-defaults: unknown flag %s\n\n' "$1" >&2
      usage >&2
      return 2
      ;;
    *) repos+=("$1") ;;
    esac
    shift
  done

  if ((all)); then
    mapfile -t repos < <(owned_repos)
  fi
  if ((${#repos[@]} == 0)); then
    usage >&2
    return 2
  fi

  PLAN=$(gh api user --jq '.plan.name')
  readonly PLAN

  local repo state drift failed=0 changed=0 blocked=0
  local -a fields
  for repo in "${repos[@]}"; do
    if ! state=$(state_of "$repo"); then
      printf 'FAIL  %s (cannot read settings)\n' "$repo"
      failed=1
      continue
    fi

    IFS=$'\t' read -r -a fields <<<"$state"
    drift=$(drift_of "${fields[@]}")
    if [[ -z $drift ]]; then
      printf 'ok    %s\n' "$repo"
    elif ((check)); then
      printf 'drift %s: %s\n' "$repo" "$drift"
      failed=1
    elif apply_to "$repo"; then
      printf 'set   %s (was: %s)\n' "$repo" "$drift"
      changed=$((changed + 1))
    else
      printf 'FAIL  %s (settings write rejected)\n' "$repo"
      failed=1
    fi

    if automerge_blocked "${fields[0]}"; then
      blocked=$((blocked + 1))
    fi
  done

  ((check)) || printf '\n%d repo(s) updated, %d checked\n' "$changed" "${#repos[@]}"
  if ((blocked)); then
    printf '%d private repo(s) cannot have auto-merge: needs GitHub Pro, plan is %s\n' \
      "$blocked" "$PLAN" >&2
  fi

  return "$failed"
}

main "$@"
