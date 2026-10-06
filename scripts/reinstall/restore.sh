#!/usr/bin/env bash
# Put back what backup.sh captured, on the freshly installed host, as the user.
# Run from a TTY before the first graphical login: the keyring daemon and
# Firefox would otherwise overwrite their restored files on exit.
# Existing paths are skipped, never overwritten, so a rerun is safe.
set -euo pipefail

src=${1:?usage: restore.sh <backup-dir>}
git_src=$src/git

# The manifest keeps the old host's paths. g6 keeps checkouts under ~/git rather
# than ~/Data/git; this pair is the only place that layout change lives. Git
# writes every absolute path it stores (worktree gitfiles, <common>/worktrees/*/gitdir,
# submodule gitfiles and core.worktree) itself, from the mapped location.
old_prefix=$HOME/Data/git
new_prefix=$HOME/git
map_path() {
  if [[ $1 == "$old_prefix" || $1 == "$old_prefix"/* ]]; then
    echo "$new_prefix${1#"$old_prefix"}"
  else
    echo "$1"
  fi
}
# Claude names a project dir after its path with every non-alphanumeric as "-".
dash_encode() { echo "${1//[^[:alnum:]]/-}"; }

echo "== home state"
tar -C "$HOME" -xpf "$src/home-state.tar" --skip-old-files
old_enc=$(dash_encode "$old_prefix")
new_enc=$(dash_encode "$new_prefix")
for d in "$HOME/.claude/projects/$old_enc" "$HOME/.claude/projects/$old_enc"-*; do
  [[ -d $d ]] || continue
  target=$HOME/.claude/projects/$new_enc${d#"$HOME/.claude/projects/$old_enc"}
  if [[ -e $target ]]; then
    echo "skip (exists): $target"
  else
    mv -- "$d" "$target"
  fi
done

declare -A done_paths
rows() { awk -F'\t' -v k="$1" '$1 == k' "$git_src/manifest.tsv"; }

# Clone from the bundle and mirror every ref back. kind=submodule expects the
# superproject to be restored already and moves the git dir inside it.
restore_repo() {
  local kind=$1 name=$2 path=$3 origin_head=$4 head=${5:--} ref super gitdir
  if [[ $kind == submodule ]]; then
    # git clone leaves an empty directory for each submodule path; only a
    # populated path is existing work to protect.
    if [[ -e $path && (! -d $path || -n $(ls -A "$path")) ]]; then
      echo "skip (exists): $path"
      return
    fi
    super=$(git -C "$(dirname "$path")" rev-parse --show-toplevel 2>/dev/null) || {
      echo "FAIL submodule: no superproject for $path"
      return
    }
    # An existing superproject may have its own state for this submodule.
    if [[ -z ${done_paths[$super]:-} ]]; then
      echo "skip (superproject not restored here): $path"
      return
    fi
  elif [[ -e $path ]]; then
    echo "skip (exists): $path"
    return
  fi
  mkdir -p "$(dirname "$path")"
  # A bare repo kept at <path>/.git (worktrees elsewhere) must come back bare,
  # or the clone checks a tree out next to it.
  if [[ $(git config -f "$git_src/config/$name.config" --bool core.bare) == true ]]; then
    git clone -q --bare "$git_src/bundles/$name.bundle" "$path/.git" || {
      echo "FAIL clone: $path"
      return
    }
  else
    git clone -q "$git_src/bundles/$name.bundle" "$path" || {
      echo "FAIL clone: $path"
      return
    }
  fi
  # clone maps the bundle's local branches to origin/*; mirroring with --prune
  # drops those fakes and brings every ref back verbatim. The clone's own
  # origin/HEAD symref goes first, or the fetch writes through it.
  git -C "$path" symbolic-ref --delete refs/remotes/origin/HEAD 2>/dev/null || true
  if ! git -C "$path" fetch -q --prune --update-head-ok "$git_src/bundles/$name.bundle" '+refs/*:refs/*'; then
    echo "FAIL fetch: $path"
    return
  fi
  [[ $origin_head != - ]] && git -C "$path" symbolic-ref refs/remotes/origin/HEAD "$origin_head"
  # A bundle does not carry a detached HEAD (every submodule has one).
  if [[ $(git config -f "$git_src/config/$name.config" --bool core.bare) == true ]]; then
    [[ $head == refs/heads/* ]] && git -C "$path/.git" symbolic-ref HEAD "$head"
  elif [[ $head == refs/heads/* ]]; then
    git -C "$path" checkout -q "${head#refs/heads/}" -- || echo "WARN: HEAD not restored: $path"
  elif [[ $head != - && $head != refs/* ]]; then
    git -C "$path" checkout -q --detach "$head" || echo "WARN: HEAD not restored: $path"
  fi
  cp "$git_src/config/$name.config" "$path/.git/config"
  if [[ $kind == submodule ]]; then
    # The saved config's core.worktree was relative to the old git dir; absorb
    # moves the clone to where the superproject expects it and rewrites that.
    git config -f "$path/.git/config" --unset core.worktree || true
    # Not registered yet (an uncommitted `submodule add`): the standalone clone
    # is still a complete repo, so keep restoring its stashes and files.
    git -C "$super" submodule absorbgitdirs -- "${path#"$super"/}" ||
      echo "WARN absorb failed, left as standalone repo: $path"
  fi
  gitdir=$(git -C "$path" rev-parse --absolute-git-dir)
  # Oldest first, so the newest ends up as stash@{0}.
  git -C "$path" update-ref -d refs/stash
  while read -r ref; do
    if ! git -C "$path" stash store -m "$(git -C "$path" log -1 --format=%s "$ref")" "$ref"; then
      echo "FAIL stash: $path"
      continue
    fi
    git -C "$path" update-ref -d "$ref"
  done < <(git -C "$path" for-each-ref --format='%(refname)' refs/stash-backup | sort -t/ -k3 -rn)
  [[ -f $git_src/crew/$name.tar ]] && tar -C "$gitdir" -xf "$git_src/crew/$name.tar"
  done_paths[$path]=1
  echo "$kind: $path"
}

echo "== repos"
while IFS=$'\t' read -r _ name path origin_head head _; do
  path=$(map_path "$path")
  restore_repo repo "$name" "$path" "$origin_head" "$head"
done < <(rows repo | LC_ALL=C sort -t$'\t' -k3,3)

echo "== worktrees"
while IFS=$'\t' read -r _ _ path main branch; do
  path=$(map_path "$path")
  main=$(map_path "$main")
  if [[ -e $path ]]; then
    echo "skip (exists): $path"
    continue
  fi
  if [[ -z $branch ]]; then
    echo "skip (was detached): $path"
    continue
  fi
  if [[ $branch == refs/* ]]; then
    git -C "$main" worktree add -q --detach "$path" "$branch" || {
      echo "FAIL worktree: $path"
      continue
    }
  else
    git -C "$main" worktree add -q "$path" "$branch" || {
      echo "FAIL worktree: $path"
      continue
    }
  fi
  # Detached HEAD keeps the commit alive from here on; the pin ref was only
  # for the bundle.
  [[ $branch == refs/worktree-backup/* ]] && git -C "$main" update-ref -d "$branch"
  done_paths[$path]=1
  echo "worktree: $path ($branch)"
done < <(rows worktree)

# After worktrees: a linked worktree can be the superproject. Parents sort
# before their children, so nested submodules come back in order.
echo "== submodules"
while IFS=$'\t' read -r _ name path origin_head head _; do
  path=$(map_path "$path")
  restore_repo submodule "$name" "$path" "$origin_head" "$head"
done < <(rows submodule | LC_ALL=C sort -t$'\t' -k3,3)

echo "== uncommitted files"
while IFS=$'\t' read -r _ name path _; do
  path=$(map_path "$path")
  # Only into trees this run created — an existing tree may hold newer work.
  if [[ -z ${done_paths[$path]:-} ]]; then
    echo "skip (not restored here): $path"
    continue
  fi
  # Remove first, extract after: a `git rm --cached` file is listed as deleted
  # but is also in the tar, and must keep its on-disk content.
  if [[ -f $git_src/dirty/$name.deletes ]]; then
    while IFS= read -r -d '' rel; do
      # A staged submodule removal lists a directory the clone left empty.
      rm -f -- "$path/$rel" 2>/dev/null || rmdir -- "$path/$rel" || echo "FAIL delete: $path/$rel"
    done <"$git_src/dirty/$name.deletes"
  fi
  if [[ -f $git_src/dirty/$name.tar ]]; then
    tar -C "$path" -xf "$git_src/dirty/$name.tar"
  fi
  if [[ -f $git_src/dirty/$name.deletes ]]; then
    # update-index, not `git rm --cached`: the latter refuses to drop a
    # submodule while the restored .gitmodules differs from the index.
    git -C "$path" update-index --force-remove -z --stdin <"$git_src/dirty/$name.deletes" ||
      echo "FAIL staged deletes: $path"
  fi
  echo "dirty: $path"
done < <(rows dirty)

echo "== orphaned worktrees"
while IFS=$'\t' read -r _ name path _; do
  path=$(map_path "$path")
  if [[ -e $path ]]; then
    echo "skip (exists): $path"
    continue
  fi
  mkdir -p "$path"
  tar -C "$path" -xf "$git_src/orphans/$name.tar"
  echo "orphan: $path"
done < <(rows orphan)

echo "done. Next: just tpm-enroll (see hosts/tp-g5/BTRFS-MIGRATION.md)"
