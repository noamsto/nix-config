#!/usr/bin/env bash
# Scratch-repo test for flatten-git-layout.sh under a throwaway $HOME.
set -euo pipefail

script=$(realpath "$(dirname "$0")/flatten-git-layout.sh")
tmp=$(mktemp -d)
sleeper=
# shellcheck disable=SC2329
cleanup() {
  [[ -z $sleeper ]] || kill "$sleeper" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

export HOME=$tmp/home
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
mkdir -p "$HOME/git/noamsto" "$HOME/Data/git/.worktrees/noamsto/repo" "$HOME/.claude/projects"

origin=$tmp/origin.git
main=$HOME/git/noamsto/repo
git init -q --bare -b main "$origin"
git clone -q "$origin" "$main" 2>/dev/null
git -C "$main" commit -q --allow-empty -m init
git -C "$main" push -q origin main
git -C "$main" remote set-head origin main

old=$HOME/Data/git/.worktrees/noamsto/repo
new=$HOME/git/.worktrees/noamsto/repo

# merged: branch == main tip, pushed
git -C "$main" worktree add -q -b merged "$old/merged"
git -C "$old/merged" commit -q --allow-empty -m feature
git -C "$old/merged" push -q origin merged:main
git -C "$main" pull -q origin main
git -C "$main" commit -q --allow-empty -m after
git -C "$main" push -q origin main
# fresh: new branch on the default tip, never committed; must not count as merged
git -C "$main" worktree add -q -b fresh "$old/fresh" main
# unmerged: own commit, pushed
git -C "$main" worktree add -q -b unmerged "$old/unmerged" origin/main
git -C "$old/unmerged" commit -q --allow-empty -m work
git -C "$old/unmerged" push -q origin unmerged
# dirty merged: at main tip but with an untracked file
git -C "$main" worktree add -q -b dirty "$old/dirty" origin/main
touch "$old/dirty/scratch"
# inuse: some process has it as cwd
git -C "$main" worktree add -q -b inuse "$old/inuse"
(cd "$old/inuse" && exec sleep 300) &
sleeper=$!
# detached: probes must not abort the table
git -C "$main" worktree add -q --detach "$old/detached"
git -C "$old/detached" commit -q --allow-empty -m wip

# claude session dirs: collision for unmerged, rename for dirty, plus a subdir session
enc() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
p=$HOME/.claude/projects
mkdir -p "$p/$(enc "$old/unmerged")" "$p/$(enc "$new/unmerged")" "$p/$(enc "$old/dirty")" "$p/$(enc "$old/dirty")-sub"
touch "$p/$(enc "$old/dirty")/s.jsonl"
mkdir -p "$old/dirty/sub"
mkdir -p "$p/$(enc "$old/dirty/sub")" "$p/$(enc "$old/dirty")-two"

fail=0
check() {
  if eval "$2"; then echo "ok   $1"; else
    echo "FAIL $1"
    fail=1
  fi
}

sleep 0.2
echo "--- dry run"
out=$("$script")
echo "$out"
check "dry run changed nothing" "[[ -d $old/merged && ! -e $new ]]"
check "table has remove for merged" "grep -E '/merged .*remove' <<<\"\$out\" >/dev/null"
check "table has keep (in use)" "grep -F 'keep (in use)' <<<\"\$out\" >/dev/null"
check "detached listed" "grep -F '(detached)' <<<\"\$out\" >/dev/null"

echo "--- apply"
"$script" --apply

check "merged removed" "[[ ! -e $old/merged ]]"
check "merged branch deleted" "! git -C $main rev-parse -q --verify refs/heads/merged >/dev/null"
check "fresh branch moved, not removed" "[[ -d $new/fresh && ! -e $old/fresh ]]"
check "unmerged moved" "[[ -d $new/unmerged && ! -e $old/unmerged ]]"
check "unmerged branch kept" "git -C $main rev-parse -q --verify refs/heads/unmerged >/dev/null"
check "worktree list from main" "git -C $main worktree list --porcelain | grep -Fx 'worktree $new/unmerged' >/dev/null"
check "status valid at new path" "git -C $new/unmerged status --porcelain >/dev/null"
check "worktree list from new path" "git -C $new/unmerged worktree list | grep -F $main >/dev/null"
check "dirty moved, not removed" "[[ -f $new/dirty/scratch && ! -e $old/dirty ]]"
check "in-use kept in place" "[[ -d $old/inuse ]]"
check "detached moved" "[[ -d $new/detached ]]"
check "session dir renamed" "[[ -f $p/$(enc "$new/dirty")/s.jsonl && ! -e $p/$(enc "$old/dirty") ]]"
check "subdir session renamed" "[[ -d $p/$(enc "$new/dirty/sub") ]]"
check "sibling-prefix session untouched" "[[ -d $p/$(enc "$old/dirty")-two ]]"
check "collision left untouched" "[[ -d $p/$(enc "$old/unmerged") && -d $p/$(enc "$new/unmerged") ]]"

exit "$fail"
