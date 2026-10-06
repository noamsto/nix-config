#!/usr/bin/env bash
# Capture the state a wipe-and-reinstall cannot rebuild from the flake.
# Restore with restore.sh (user state, git) and `just reinstall-host` (boot state).
#
#   root-state.tar   etc/secureboot + host ssh key — staged by nixos-anywhere
#   home-state.tar   ~/.ssh, keyrings, claude, shell history, cloud creds, firefox
#   git/manifest.tsv one row per backed-up item: kind, name, path, extra
#   git/bundles/     every ref of every repo (branches, tags, refs/stash)
#   git/config/      each repo's .git/config, so remotes and upstreams come back
#   git/crew/        .git/crew dispatcher artifacts (not refs, so not in bundles)
#   git/dirty/       staged, modified, and untracked files; staged deletions as *.deletes
#   git/orphans/     worktrees whose gitdir was pruned; whole tree minus deps
set -uo pipefail

dest=${1:?usage: backup.sh <dest-dir>}
mkdir -p "$dest"/git/{bundles,config,crew,dirty,orphans}
# The repo holding restore.sh is itself in the backup, so it travels alongside.
cp "$(dirname "$0")/restore.sh" "$dest/"
manifest=$dest/git/manifest.tsv
: >"$manifest"
declare -A used_names=()
dirty_list=$(mktemp)
trap 'rm -f "$dirty_list"' EXIT

roots=(
  "$HOME/Data/git" "$HOME/nix-config" "$HOME/Documents" "$HOME/code"
  "$HOME/tmux-config" "$HOME/.config/lzvim" "$HOME/Downloads" "$HOME/data"
)
home_state=(
  .ssh .local/share/keyrings .claude/projects .local/share/fish/fish_history
  .local/share/zoxide .aws .kube .mozilla
)
deps=(--exclude=node_modules --exclude=.venv --exclude=dist --exclude=.next
  --exclude=target --exclude=.terraform --exclude=.turbo --exclude=result)

name_of() {
  local p=${1#"$HOME"/}
  echo "${p//\//_}"
}
row() { printf '%s\t%s\t%s\t%s\n' "$@" >>"$manifest"; }

# Backup refs live only inside the bundle; drop them from the working repo.
drop_refs() {
  local repo=$1
  shift
  if ! git -C "$repo" for-each-ref --format='delete %(refname)' "$@" |
    git -C "$repo" update-ref --stdin; then
    echo "FATAL: failed to drop $* in $repo" >&2
    exit 1
  fi
}

# Stash pins + bundle. cfg is the repo config file (not always $wt/.git/config).
bundle_repo() {
  local wt=$1 name=$2 cfg=$3 sha i=0
  # A bundle carries refs/stash but not its reflog, i.e. only the newest
  # stash. Pin every entry as a ref so all of them travel; restore.sh
  # rebuilds the stash list from these and deletes them.
  drop_refs "$wt" refs/stash-backup
  while read -r sha; do
    git -C "$wt" update-ref "refs/stash-backup/$((i++))" "$sha"
  done < <(git -C "$wt" reflog show --format=%H refs/stash 2>/dev/null)
  if git -C "$wt" bundle create "$dest/git/bundles/$name.bundle" --all 2>/dev/null; then
    drop_refs "$wt" refs/stash-backup refs/worktree-backup
    cp "$cfg" "$dest/git/config/$name.config"
    row repo "$name" "$wt" "$(git -C "$wt" symbolic-ref -q refs/remotes/origin/HEAD || echo -)"
  elif git -C "$wt" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "FATAL: bundle failed: $wt" >&2
    exit 1
  else
    echo "WARN: no commits, nothing to bundle: $wt"
  fi
}

echo "== root state (sudo)"
if ! sudo tar -C / -cf "$dest/root-state.tar" \
  etc/secureboot etc/ssh/ssh_host_ed25519_key etc/ssh/ssh_host_ed25519_key.pub; then
  echo "FATAL: root-state archive failed" >&2
  exit 1
fi

# Only /nix/store symlinks are left out: they point at the old system's store
# and would make Home Manager's first activation refuse to overwrite them.
# Every other symlink is archived as a symlink.
echo "== home state"
if ! (
  cd "$HOME"
  find "${home_state[@]}" ! \( -type l -lname '/nix/store/*' \) -print0
) | tar -C "$HOME" --null --no-recursion -T - -cf "$dest/home-state.tar"; then
  echo "FATAL: home-state archive failed" >&2
  exit 1
fi

echo "== git"
while IFS= read -r -d '' gitpath; do
  wt=$(dirname "$gitpath")
  name=$(name_of "$wt")
  if [[ -n ${used_names[$name]:-} ]]; then
    echo "FATAL: name collision '$name' for $wt and ${used_names[$name]}" >&2
    exit 1
  fi
  used_names[$name]=$wt

  if ! git -C "$wt" rev-parse --git-dir >/dev/null 2>&1; then
    tar -C "$wt" "${deps[@]}" --exclude=.git -cf "$dest/git/orphans/$name.tar" . 2>/dev/null
    row orphan "$name" "$wt" -
    continue
  fi

  if [[ -d $gitpath ]]; then
    bundle_repo "$wt" "$name" "$gitpath/config"
    [[ -d $gitpath/crew ]] && tar -C "$gitpath" -cf "$dest/git/crew/$name.tar" crew
  else
    gitdir=$(git -C "$wt" rev-parse --absolute-git-dir)
    commondir=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)
    if [[ $gitdir == "$commondir" ]]; then
      # Submodule or .git gitfile: one repo, not a linked worktree.
      cfg=$(git -C "$wt" rev-parse --path-format=absolute --git-path config)
      bundle_repo "$wt" "$name" "$cfg"
    else
      main=$(dirname "$commondir")
      bundle=$dest/git/bundles/$(name_of "$main").bundle
      branch=$(git -C "$wt" branch --show-current)
      if [[ -z $branch ]]; then
        branch=refs/worktree-backup/$name
        # --all replaces the bundle from the repo. bundle_repo already deleted
        # refs/stash-backup, and each recreate deletes both pin namespaces, so
        # reload whichever of them the previous bundle still holds.
        if [[ -f $bundle ]]; then
          heads=$(git -C "$main" bundle list-heads "$bundle") || {
            echo "FATAL: cannot read $bundle" >&2
            exit 1
          }
          if [[ $heads == *refs/stash-backup/* ]]; then
            if ! git -C "$main" fetch -q "$bundle" '+refs/stash-backup/*:refs/stash-backup/*'; then
              echo "FATAL: failed to reload stash pins from $bundle" >&2
              exit 1
            fi
          fi
          if [[ $heads == *refs/worktree-backup/* ]]; then
            if ! git -C "$main" fetch -q "$bundle" '+refs/worktree-backup/*:refs/worktree-backup/*'; then
              echo "FATAL: failed to reload worktree pins from $bundle" >&2
              exit 1
            fi
          fi
        fi
        git -C "$wt" update-ref "$branch" HEAD
        if [[ -f $bundle ]]; then
          if ! git -C "$main" bundle create "$bundle" --all; then
            echo "FATAL: bundle recreate failed for $main" >&2
            exit 1
          fi
          drop_refs "$main" refs/stash-backup refs/worktree-backup
        fi
      fi
      row worktree "$name" "$wt" "$main	$branch"
    fi
  fi

  : >"$dirty_list"
  git -C "$wt" diff --cached -z --name-only --diff-filter=ACMRT >"$dirty_list"
  git -C "$wt" ls-files -z -m -o --exclude-standard >>"$dirty_list"
  have_dirty=0
  if [[ -s $dirty_list ]]; then
    tar -C "$wt" --null --ignore-failed-read -T "$dirty_list" -cf "$dest/git/dirty/$name.tar"
    have_dirty=1
  fi
  git -C "$wt" diff --cached --name-only --diff-filter=D >"$dest/git/dirty/$name.deletes"
  if [[ -s $dest/git/dirty/$name.deletes ]]; then
    have_dirty=1
  else
    rm -f "$dest/git/dirty/$name.deletes"
  fi
  if [[ $have_dirty == 1 ]]; then
    row dirty "$name" "$wt" -
  fi
done < <(find "${roots[@]}" \( -name node_modules -o -name .terraform -o -name _deps -o -name .venv \) -prune \
  -o -name .git -prune -print0 2>/dev/null)

echo "done -> $dest"
du -sh "$dest"/*.tar "$dest"/git/*/
