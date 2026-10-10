#!/usr/bin/env bash
# Round-trip test for backup.sh/restore.sh over scratch repos in a fake $HOME.
# Never touches the real $HOME: sudo is shimmed, every path lives under a temp dir.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
real_git=$(command -v git)

export HOME=$T/home
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always

mkdir -p "$HOME"/{.ssh,.local/share/keyrings,.claude/projects,.local/share/fish,.local/share/zoxide,.aws,.kube,.mozilla,.gnupg/private-keys-v1.d} \
  "$HOME/Data/git" "$T/up" "$T/shims"
touch "$HOME/.local/share/fish/fish_history"
chmod 700 "$HOME/.gnupg" "$HOME/.gnupg/private-keys-v1.d"
echo secret-key >"$HOME/.gnupg/private-keys-v1.d/k.key"
chmod 600 "$HOME/.gnupg/private-keys-v1.d/k.key"

# backup.sh's only privileged step is the root-state tar; stand in an empty one.
cat >"$T/shims/sudo" <<'EOF'
#!/usr/bin/env bash
[[ $1 == tar ]] || exit 1
shift
while [[ $1 != -cf ]]; do shift; done
exec tar -cf "$2" -T /dev/null
EOF
chmod +x "$T/shims/sudo"
export PATH=$T/shims:$PATH

g() { git -C "$1" "${@:2}"; }
commit() { # repo file content
  echo "$3" >"$1/$2"
  g "$1" add -- "$2"
  g "$1" commit -q -m "$2"
}
new_repo() {
  git init -q -b main "$1"
  commit "$1" README one
}

# --- #507: superproject with a submodule holding unpushed work -----------------
new_repo "$T/up/sub.git.src"
git clone -q --bare "$T/up/sub.git.src" "$T/up/sub.git"
new_repo "$T/up/proj.src"
g "$T/up/proj.src" submodule add -q "$T/up/sub.git" services/sub
g "$T/up/proj.src" commit -q -m sub
git clone -q --bare "$T/up/proj.src" "$T/up/proj.git"
proj=$HOME/Data/git/owner/proj
git clone -q --recurse-submodules "$T/up/proj.git" "$proj"
g "$proj" remote set-head origin main
sub=$proj/services/sub
commit "$sub" unpushed.txt local-only
echo wip >"$sub/README"
echo scratch >"$sub/untracked.txt"
g "$sub" stash push -q -m sub-stash
echo wip2 >"$sub/README"
echo dirty >"$proj/untracked.txt"
echo more >>"$proj/README"
# a linked worktree of the superproject with its own initialised submodule
g "$proj" worktree add -q "$HOME/Data/git/.worktrees/owner/proj/wtbranch" -b wtbranch
g "$HOME/Data/git/.worktrees/owner/proj/wtbranch" submodule update -q --init
echo wtdirty >"$HOME/Data/git/.worktrees/owner/proj/wtbranch/services/sub/untracked.txt"

# --- #515: a linked worktree of the submodule itself ---------------------------
subwt=$HOME/Data/git/.worktrees/subwt
g "$sub" worktree add -q "$subwt" -b subwtbranch
echo subwt-dirty >"$subwt/untracked.txt"

# --- #508: staged deletes, git rm --cached, non-ASCII paths --------------------
del=$HOME/Data/git/del
new_repo "$del"
for f in a.txt keep.txt é-staged.txt é-kept.txt plain.txt mm.txt; do commit "$del" "$f" "$f"; done
commit "$del" local.cfg v1
echo local.cfg >"$del/.gitignore"
g "$del" add .gitignore
g "$del" commit -q -m ignore
echo v2-local >"$del/local.cfg"
g "$del" rm -q a.txt
g "$del" rm -q --cached local.cfg
g "$del" rm -q --cached keep.txt
g "$del" rm -q é-staged.txt
g "$del" rm -q --cached é-kept.txt
echo changed >"$del/plain.txt"

# --- #514: partly staged file, and a staged new file ---------------------------
echo staged-v >"$del/mm.txt"
g "$del" add mm.txt
echo worktree-v >"$del/mm.txt"
echo new >"$del/new-staged.txt"
g "$del" add new-staged.txt

# --- #513: repo with no commits ------------------------------------------------
unborn=$HOME/Data/git/unborn
git init -q -b main "$unborn"
echo s >"$unborn/staged.txt"
g "$unborn" add staged.txt
echo u >"$unborn/untracked.txt"

# submodules the first block does not cover: a .git directory (existing clone
# added in place) and a staged removal
new_repo "$T/up/lib.src"
git clone -q "$T/up/lib.src" "$proj/lib"
g "$proj" submodule add -q "$T/up/lib.src" lib
g "$proj" commit -q -m lib
commit "$proj/lib" lib-local x
new_repo "$T/up/gone.src"
g "$proj" submodule add -q "$T/up/gone.src" gone
g "$proj" commit -q -m gone
g "$proj" rm -q gone
# restore cannot recover which hunks were staged; keep .gitmodules unstaged
g "$proj" reset -q .gitmodules

# bare repo kept at <path>/.git
git clone -q --bare "$T/up/lib.src" "$HOME/Data/git/bare/.git"

# --- #509: detached worktrees with awkward names -------------------------------
wtmain=$HOME/Data/git/wtmain
new_repo "$wtmain"
mkdir "$HOME/Data/git/wts"
for n in "with space" .dotted x.lock; do
  commit "$wtmain" "$(tr -d ' ' <<<"$n").f" "$n"
  g "$wtmain" worktree add -q --detach "$HOME/Data/git/wts/$n" HEAD
  echo "$n" >"$HOME/Data/git/wts/$n/untracked"
done

# --- shallow clone: its bundle lacks the history below the shallow boundary ----
new_repo "$T/up/deep.src"
commit "$T/up/deep.src" second two
shallow=$HOME/Data/git/shallow
git clone -q --depth 1 "file://$T/up/deep.src" "$shallow"
commit "$shallow" local.txt local-only

# --- LFS: a bundle is not an LFS store, so checkout must not smudge from it ----
export GIT_CONFIG_COUNT=4 \
  GIT_CONFIG_KEY_1=filter.lfs.process GIT_CONFIG_VALUE_1="git-lfs filter-process" \
  GIT_CONFIG_KEY_2=filter.lfs.required GIT_CONFIG_VALUE_2=true \
  GIT_CONFIG_KEY_3=filter.lfs.clean GIT_CONFIG_VALUE_3="git-lfs clean -- %f"
new_repo "$T/up/lfs.src"
g "$T/up/lfs.src" lfs track '*.bin' >/dev/null
head -c 4096 /dev/urandom >"$T/up/lfs.src/blob.bin"
g "$T/up/lfs.src" add .gitattributes blob.bin
g "$T/up/lfs.src" commit -q -m lfs
lfs=$HOME/Data/git/lfs
git clone -q "$T/up/lfs.src" "$lfs"

repos=("$proj" "$sub" "$proj/lib" "$HOME/Data/git/bare/.git" "$HOME/Data/git/.worktrees/owner/proj/wtbranch" "$HOME/Data/git/.worktrees/owner/proj/wtbranch/services/sub"
  "$subwt" "$del" "$unborn" "$wtmain" "$HOME/Data/git/wts/with space" "$HOME/Data/git/wts/.dotted" "$HOME/Data/git/wts/x.lock"
  "$shallow" "$lfs")

snapshot() {
  local r
  for r in "${repos[@]}"; do
    echo "### ${r#"$HOME"/}"
    [[ $(g "$r" rev-parse --is-bare-repository) == true ]] || g "$r" ls-files -s
    g "$r" for-each-ref --format='%(refname) %(objectname) %(symref)'
    g "$r" symbolic-ref -q HEAD || g "$r" rev-parse HEAD
    g "$r" symbolic-ref -q refs/remotes/origin/HEAD || true
    g "$r" stash list --format='%gd %H %gs' 2>/dev/null || true
    { g "$r" status --porcelain=v1 -z 2>/dev/null || true; } | tr '\0' '\n'
    # lib starts with a .git directory and comes back absorbed, so its git dir
    # location is expected to differ.
    if [[ $r != "$proj/lib" ]]; then
      g "$r" worktree list --porcelain | grep -v '^$' || true
    fi
    [[ $(g "$r" rev-parse --is-bare-repository) == true ]] ||
      (cd "$r" && find . -type f ! -name .git ! -path './.git/*' ! -path './services/sub/*' ! -path './lib/*' -print0 |
        LC_ALL=C sort -z | xargs -0 sha256sum)
  done
}

# Claude project dirs: dash-encoded old prefix gets renamed, an existing target
# is never overwritten.
enc() { echo "${1//[^[:alnum:]]/-}"; }
old_enc=$(enc "$HOME/Data/git")
new_enc=$(enc "$HOME/git")
proj_dir=$HOME/.claude/projects
mkdir -p "$proj_dir/$old_enc-owner-proj" "$proj_dir/$old_enc--worktrees-owner-proj-wtbranch" \
  "$proj_dir/$old_enc-collide" "$proj_dir/$new_enc-collide" "$proj_dir/-unrelated" \
  "$proj_dir/${old_enc}hub-lookalike"
echo old >"$proj_dir/$old_enc-collide/s.jsonl"
echo new >"$proj_dir/$new_enc-collide/s.jsonl"
echo s >"$proj_dir/$old_enc-owner-proj/s.jsonl"

dest=$T/dest
bash "$here/backup.sh" "$dest" >"$T/backup.log"
tail -n 3 "$T/backup.log" | head -n 1

snapshot >"$T/before"
mv "$HOME/Data/git" "$T/orig-git"
mv "$HOME/.claude" "$T/orig-claude"
rm -rf "$HOME/.gnupg"
mkdir -p "$HOME/.claude/projects"
bash "$here/restore.sh" "$dest" >"$T/restore.log"
grep -E 'FAIL|WARN' "$T/restore.log" && exit 1
# g6 layout: ~/Data/git/<rest> comes back as ~/git/<rest>
repos=("${repos[@]/#"$HOME/Data/git"/"$HOME/git"}")
proj=$HOME/git/owner/proj
sub=$proj/services/sub
snapshot | sed -e "s#$HOME/git#$HOME/Data/git#g" -e 's|^\(### \)git/|\1Data/git/|' >"$T/after"

echo "== refs, symrefs, stashes, status: before vs after restore"
if diff -u "$T/before" "$T/after"; then
  echo "identical ($(wc -l <"$T/before") lines compared)"
else
  echo "MISMATCH" >&2
  exit 1
fi

echo "== .gnupg restored 0700 with identical content"
[[ $(stat -c %a "$HOME/.gnupg") == 700 && $(stat -c %a "$HOME/.gnupg/private-keys-v1.d") == 700 ]] || {
  echo ".gnupg dir mode not 0700" >&2
  exit 1
}
[[ $(<"$HOME/.gnupg/private-keys-v1.d/k.key") == secret-key ]] || {
  echo ".gnupg key content differs" >&2
  exit 1
}

echo "== g6 layout: nothing under the old prefix, worktrees valid, .claude renamed"
[[ ! -e $HOME/Data/git ]] || {
  echo "old prefix recreated" >&2
  exit 1
}
g "$proj" worktree list
if g "$proj" worktree list --porcelain | grep -q '^prunable'; then
  echo "prunable worktree after restore" >&2
  exit 1
fi
for d in "$new_enc-owner-proj" "$new_enc--worktrees-owner-proj-wtbranch" "-unrelated" \
  "${old_enc}hub-lookalike" "$old_enc-collide"; do
  [[ -d $proj_dir/$d ]] || {
    echo "missing $proj_dir/$d" >&2
    exit 1
  }
done
[[ ! -e $proj_dir/$old_enc-owner-proj ]] || {
  echo "old project dir not renamed" >&2
  exit 1
}
[[ $(<"$proj_dir/$new_enc-collide/s.jsonl") == new ]] || {
  echo "existing target overwritten" >&2
  exit 1
}

echo "== superproject and submodule status work after restore"
g "$proj" status -s
g "$sub" status -s

echo "== forced update-ref failure aborts backup"
# backup reads the old layout again
mv "$HOME/git" "$T/restored-git"
mv "$T/orig-git" "$HOME/Data/git"
cat >"$T/shims/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do [[ \$a == refs/worktree-backup/* ]] && exit 1; done
exec $real_git "\$@"
EOF
chmod +x "$T/shims/git"
if bash "$here/backup.sh" "$T/dest-fail" >"$T/fail.log" 2>&1; then
  echo "backup unexpectedly succeeded" >&2
  exit 1
fi
if grep -q '^done' "$T/fail.log"; then
  echo "backup printed done despite failure" >&2
  exit 1
fi
grep FATAL "$T/fail.log"

echo "== #516: a tab in a repo path is refused before any row is written"
rm "$T/shims/git"
tabrepo=$HOME/Data/git/$(printf 'tab\tdir')
git init -q -b main "$tabrepo"
if bash "$here/backup.sh" "$T/dest-tab" >"$T/tab.log" 2>&1; then
  echo "backup unexpectedly succeeded on a tab path" >&2
  exit 1
fi
if ! grep -q 'FATAL.*tab.*dir' "$T/tab.log"; then
  echo "tab path not named in error" >&2
  exit 1
fi
[[ ! -s $T/dest-tab/git/manifest.tsv ]] || {
  echo "manifest has rows despite refusal" >&2
  exit 1
}
echo "PASS"
