#!/usr/bin/env bash
# Capture the state a wipe-and-reinstall cannot rebuild from the flake.
# Restore with restore.sh (user state, git) and `just reinstall-host` (boot state).
#
#   root-state.tar   etc/secureboot + host ssh key — staged by nixos-anywhere
#   home-state.tar   ~/.ssh, keyrings, claude, shell history, cloud creds, firefox
#   git/manifest.tsv one row per backed-up item: kind, name, path, extra...
#                    (worktree rows carry the detached-HEAD pin ref for that path)
#   git/bundles/     every ref of every repo (branches, tags, refs/stash)
#   git/config/      each repo's .git/config, so remotes and upstreams come back
#   git/crew/        .git/crew dispatcher artifacts (not refs, so not in bundles)
#   git/dirty/       staged, modified, and untracked files; staged deletions as
#                    NUL-separated *.deletes
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
dirty_all=$(mktemp)
trap 'rm -f "$dirty_list" "$dirty_all"' EXIT

roots=(
  "$HOME/Data/git" "$HOME/nix-config" "$HOME/Documents" "$HOME/code"
  "$HOME/tmux-config" "$HOME/Downloads" "$HOME/data"
)
home_state=(
  .ssh .local/share/keyrings .claude/projects .local/share/fish/fish_history
  .local/share/zoxide .aws .kube .mozilla .gnupg
)
deps=(--exclude=node_modules --exclude=.venv --exclude=dist --exclude=.next
  --exclude=target --exclude=.terraform --exclude=.turbo --exclude=result)

name_of() {
  local p=${1#"$HOME"/}
  echo "${p//\//_}"
}
row() (
  IFS=$'\t'
  printf '%s\n' "$*" >>"$manifest"
)
# A ref component must be check-ref-format valid whatever the path holds
# (spaces, leading dot, .lock suffix), so derive it from a hash of the path.
pin_ref() {
  local h
  h=$(printf '%s' "$1" | sha256sum)
  echo "refs/worktree-backup/${h:0:32}"
}

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
  local wt=$1 name=$2 cfg=$3 kind=$4 sha i=0
  # A bundle carries refs/stash but not its reflog, i.e. only the newest
  # stash. Pin every entry as a ref so all of them travel; restore.sh
  # rebuilds the stash list from these and deletes them.
  drop_refs "$wt" refs/stash-backup
  while read -r sha; do
    if ! git -C "$wt" update-ref "refs/stash-backup/$((i++))" "$sha"; then
      echo "FATAL: failed to pin stash $sha in $wt" >&2
      exit 1
    fi
  done < <(git -C "$wt" reflog show --format=%H refs/stash 2>/dev/null)
  if git -C "$wt" bundle create "$dest/git/bundles/$name.bundle" --all 2>/dev/null; then
    drop_refs "$wt" refs/stash-backup refs/worktree-backup
    cp "$cfg" "$dest/git/config/$name.config"
    # HEAD is not under refs/*, so a bundle round-trip loses a detached HEAD
    # (the usual state of a submodule); record it to check it out again.
    row "$kind" "$name" "$wt" "$(git -C "$wt" symbolic-ref -q refs/remotes/origin/HEAD || echo -)" \
      "$(git -C "$wt" symbolic-ref -q HEAD || git -C "$wt" rev-parse HEAD)"
  elif git -C "$wt" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "FATAL: bundle failed: $wt" >&2
    exit 1
  else
    # An unborn HEAD has no refs to bundle, but staged and untracked files
    # still travel as a dirty row; restore re-inits the repo to receive them.
    echo "WARN: no commits, restoring as an empty repo: $wt"
    cp "$cfg" "$dest/git/config/$name.config"
    row unborn "$name" "$wt" - "$(git -C "$wt" symbolic-ref -q HEAD || echo refs/heads/main)"
  fi
}

# Manifest rows are unescaped TSV: refuse paths that would corrupt one before
# anything is written.
mapfile -d '' gitpaths < <(find "${roots[@]}" \( -name node_modules -o -name .terraform -o -name _deps -o -name .venv \) -prune \
  -o -name .git -prune -print0 2>/dev/null)
for gitpath in "${gitpaths[@]}"; do
  if [[ $gitpath == *[$'\t\n']* ]]; then
    printf 'FATAL: tab or newline in path, cannot be recorded: %q\n' "$gitpath" >&2
    exit 1
  fi
done

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
for gitpath in "${gitpaths[@]}"; do
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

  if ! superproject=$(git -C "$wt" rev-parse --show-superproject-working-tree); then
    echo "FATAL: cannot tell whether $wt is a submodule" >&2
    exit 1
  fi
  kind=repo
  [[ -n $superproject ]] && kind=submodule
  if [[ -d $gitpath ]]; then
    bundle_repo "$wt" "$name" "$gitpath/config" "$kind"
    [[ -d $gitpath/crew ]] && tar -C "$gitpath" -cf "$dest/git/crew/$name.tar" crew
  else
    gitdir=$(git -C "$wt" rev-parse --absolute-git-dir)
    commondir=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir)
    if [[ $gitdir == "$commondir" ]]; then
      # Submodule or .git gitfile: one repo, not a linked worktree.
      cfg=$(git -C "$wt" rev-parse --path-format=absolute --git-path config)
      bundle_repo "$wt" "$name" "$cfg" "$kind"
    else
      # A submodule's common dir is <super>/.git/modules/..., whose work tree
      # is named by core.worktree; plain and bare layouts fall back to dirname.
      main=$(git -C "$commondir" rev-parse --show-toplevel 2>/dev/null) || main=$(dirname "$commondir")
      if [[ $main == *[$'\t\n']* ]]; then
        printf 'FATAL: tab or newline in path, cannot be recorded: %q\n' "$main" >&2
        exit 1
      fi
      bundle=$dest/git/bundles/$(name_of "$main").bundle
      branch=$(git -C "$wt" branch --show-current)
      if [[ -z $branch ]]; then
        branch=$(pin_ref "$wt")
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
        if ! git -C "$wt" update-ref "$branch" HEAD; then
          echo "FATAL: failed to pin detached HEAD of $wt as $branch" >&2
          exit 1
        fi
        if [[ -f $bundle ]]; then
          if ! git -C "$main" bundle create "$bundle" --all; then
            echo "FATAL: bundle recreate failed for $main" >&2
            exit 1
          fi
          drop_refs "$main" refs/stash-backup refs/worktree-backup
        fi
      fi
      row worktree "$name" "$wt" "$main" "$branch"
    fi
  fi

  # A bare repo has no tree or index to be dirty.
  [[ $(git -C "$wt" rev-parse --is-bare-repository) == true ]] && continue

  # Submodule gitlinks are separate repo rows; archiving one here would drag
  # its whole tree (and .git file) into this repo's tar.
  gitlinks=()
  while IFS= read -r -d '' ent; do
    [[ $ent == 160000\ * ]] && gitlinks+=("${ent#*$'\t'}")
  done < <(git -C "$wt" ls-files -z -s)
  : >"$dirty_list"
  if ! {
    git -C "$wt" diff --cached -z --no-renames --name-only --diff-filter=ACMRT &&
      git -C "$wt" ls-files -z -m -o --exclude-standard
  } >"$dirty_all"; then
    echo "FATAL: cannot list dirty files in $wt" >&2
    exit 1
  fi
  while IFS= read -r -d '' f; do
    skip=0
    for g in "${gitlinks[@]}"; do [[ $f == "$g" ]] && skip=1; done
    # An untracked directory holding its own .git is a separate repo row.
    [[ $f == */ && -e $wt/${f}.git ]] && skip=1
    ((skip)) || printf '%s\0' "$f" >>"$dirty_list"
  done <"$dirty_all"
  if ! git -C "$wt" diff --cached -z --no-renames --name-only --diff-filter=D >"$dirty_all"; then
    echo "FATAL: cannot list staged deletions in $wt" >&2
    exit 1
  fi
  # A `git rm --cached` file stays on disk, even when .gitignore hides it from
  # ls-files -o, and the restore removes it before extracting: archive it.
  while IFS= read -r -d '' f; do
    [[ -L $wt/$f || (-e $wt/$f && ! -d $wt/$f) ]] && printf '%s\0' "$f" >>"$dirty_list"
  done <"$dirty_all"
  have_dirty=0
  # The tar holds worktree content only; the staged blobs travel as a patch.
  excludes=()
  for g in "${gitlinks[@]}"; do excludes+=(":(exclude,literal)$g"); done
  if ! git -C "$wt" diff --cached --binary --no-renames --no-ext-diff --no-textconv --no-color \
    --src-prefix=a/ --dst-prefix=b/ --diff-filter=ACMRT -- . "${excludes[@]}" >"$dest/git/dirty/$name.staged.patch"; then
    echo "FATAL: cannot capture staged changes in $wt" >&2
    exit 1
  fi
  if [[ -s $dest/git/dirty/$name.staged.patch ]]; then
    have_dirty=1
  else
    rm -f "$dest/git/dirty/$name.staged.patch"
  fi
  if [[ -s $dirty_list ]]; then
    tar -C "$wt" --null --ignore-failed-read -T "$dirty_list" -cf "$dest/git/dirty/$name.tar"
    have_dirty=1
  fi
  cp "$dirty_all" "$dest/git/dirty/$name.deletes"
  if [[ -s $dest/git/dirty/$name.deletes ]]; then
    have_dirty=1
  else
    rm -f "$dest/git/dirty/$name.deletes"
  fi
  if [[ $have_dirty == 1 ]]; then
    row dirty "$name" "$wt" -
  fi
done

echo "done -> $dest"
du -sh "$dest"/*.tar "$dest"/git/*/
