#!/usr/bin/env bash
# Put back what backup.sh captured, on the freshly installed host, as the user.
# Run from a TTY before the first graphical login: the keyring daemon and
# Firefox would otherwise overwrite their restored files on exit.
# Existing paths are skipped, never overwritten, so a rerun is safe.
set -euo pipefail

src=${1:?usage: restore.sh <backup-dir>}
git_src=$src/git

echo "== home state"
tar -C "$HOME" -xpf "$src/home-state.tar" --skip-old-files

declare -A done_paths
rows() { awk -F'\t' -v k="$1" '$1 == k' "$git_src/manifest.tsv"; }

echo "== repos"
while IFS=$'\t' read -r _ name path origin_head _; do
  if [[ -e $path ]]; then
    echo "skip (exists): $path"
    continue
  fi
  mkdir -p "$(dirname "$path")"
  # A bare repo kept at <path>/.git (worktrees elsewhere) must come back bare,
  # or the clone checks a tree out next to it.
  if [[ $(git config -f "$git_src/config/$name.config" --bool core.bare) == true ]]; then
    git clone -q --bare "$git_src/bundles/$name.bundle" "$path/.git" || {
      echo "FAIL clone: $path"
      continue
    }
  else
    git clone -q "$git_src/bundles/$name.bundle" "$path" || {
      echo "FAIL clone: $path"
      continue
    }
  fi
  # clone maps the bundle's local branches to origin/*; mirroring with --prune
  # drops those fakes and brings every ref back verbatim. The clone's own
  # origin/HEAD symref goes first, or the fetch writes through it.
  git -C "$path" symbolic-ref --delete refs/remotes/origin/HEAD 2>/dev/null || true
  if ! git -C "$path" fetch -q --prune --update-head-ok "$git_src/bundles/$name.bundle" '+refs/*:refs/*'; then
    echo "FAIL fetch: $path"
    continue
  fi
  [[ $origin_head != - ]] && git -C "$path" symbolic-ref refs/remotes/origin/HEAD "$origin_head"
  cp "$git_src/config/$name.config" "$path/.git/config"
  # Oldest first, so the newest ends up as stash@{0}.
  git -C "$path" update-ref -d refs/stash
  while read -r ref; do
    if ! git -C "$path" stash store -m "$(git -C "$path" log -1 --format=%s "$ref")" "$ref"; then
      echo "FAIL stash: $path"
      continue
    fi
    git -C "$path" update-ref -d "$ref"
  done < <(git -C "$path" for-each-ref --format='%(refname)' refs/stash-backup | sort -t/ -k3 -rn)
  [[ -f $git_src/crew/$name.tar ]] && tar -C "$path/.git" -xf "$git_src/crew/$name.tar"
  done_paths[$path]=1
  echo "repo: $path"
done < <(rows repo)

echo "== worktrees"
while IFS=$'\t' read -r _ _ path main branch; do
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
  done_paths[$path]=1
  echo "worktree: $path ($branch)"
done < <(rows worktree)

echo "== uncommitted files"
while IFS=$'\t' read -r _ name path _; do
  # Only into trees this run created — an existing tree may hold newer work.
  if [[ -z ${done_paths[$path]:-} ]]; then
    echo "skip (not restored here): $path"
    continue
  fi
  if [[ -f $git_src/dirty/$name.tar ]]; then
    tar -C "$path" -xf "$git_src/dirty/$name.tar"
  fi
  if [[ -f $git_src/dirty/$name.deletes ]]; then
    while IFS= read -r rel || [[ -n ${rel:-} ]]; do
      [[ -z $rel ]] && continue
      rm -f -- "$path/$rel"
    done <"$git_src/dirty/$name.deletes"
  fi
  echo "dirty: $path"
done < <(rows dirty)

echo "== orphaned worktrees"
while IFS=$'\t' read -r _ name path _; do
  if [[ -e $path ]]; then
    echo "skip (exists): $path"
    continue
  fi
  mkdir -p "$path"
  tar -C "$path" -xf "$git_src/orphans/$name.tar"
  echo "orphan: $path"
done < <(rows orphan)

echo "done. Next: just tpm-enroll (see hosts/thinkpad-p14s-g5/BTRFS-MIGRATION.md)"
