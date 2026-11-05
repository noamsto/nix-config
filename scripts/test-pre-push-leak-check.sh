#!/usr/bin/env bash
# Scratch-repo test for pre-push-leak-check.sh, driven through a real
# prek-installed pre-push hook. Needs betterleaks and prek on PATH:
#   nix shell nixpkgs#betterleaks nixpkgs#prek -c bash scripts/test-pre-push-leak-check.sh
set -euo pipefail

script=$(realpath "$(dirname "$0")/pre-push-leak-check.sh")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail=0
ok() { echo "ok   - $1"; }
bad() {
  echo "FAIL - $1"
  fail=1
}

# Same fields as the Nix hook, entry straight at the script.
cfg=$tmp/prek.yaml
cat >"$cfg" <<YAML
repos:
  - repo: local
    hooks:
      - id: leak-check
        name: leak-check
        entry: $script
        language: system
        always_run: true
        pass_filenames: false
        stages: [pre-push]
YAML

new_repo() { # name -> bare remote $tmp/name.git, hooked clone $tmp/name
  git init -q --bare -b main "$tmp/$1.git"
  git clone -q "$tmp/$1.git" "$tmp/$1" 2>/dev/null
  git -C "$tmp/$1" config core.hooksPath "$tmp/$1/.git/hooks"
  (cd "$tmp/$1" && prek install -q -t pre-push -c "$cfg")
}

commit() { # file content message
  printf '%s\n' "$2" >"$1"
  git add "$1"
  git commit -q --no-verify -m "$3"
}

# Assembled at runtime so no whole key-shaped literal lives in the repo.
key="wJalrXUtnFEMI/K7MDENG/$(printf 'bPxRfiCYzXyQ8vTn2L')"
leak_line="aws_secret_access_key = $key"

push() { git push "$@" 2>&1 || true; }
pushed() { git ls-remote --exit-code "$remote" "$1" >/dev/null 2>&1; }

# (f1) first push to an empty remote (root commit: TO set, FROM unset) is scanned.
new_repo first
cd "$tmp/first"
remote=$tmp/first.git
commit secret.txt "$leak_line" "root with leak"
out=$(push origin main)
if ! pushed refs/heads/main && [[ $out != *"$key"* && $out == *"leaks found"* ]]; then ok "first push to empty remote is scanned and refused"; else bad "first push leak: $out"; fi

new_repo work
cd "$tmp/work"
remote=$tmp/work.git

# (a) clean commit pushes.
commit a.txt "hello" "clean root"
out=$(push origin main)
if pushed refs/heads/main; then ok "clean push succeeds"; else bad "clean push: $out"; fi

# (d) fake AWS key refused, raw key not printed.
commit b.txt "$leak_line" "add leak"
out=$(push origin main)
if [[ $(git rev-parse HEAD) != "$(git ls-remote "$remote" refs/heads/main | cut -f1)" && $out != *"$key"* && $out == *"leaks found"* ]]; then
  ok "leaky push refused, key redacted"
else bad "leaky push: $out"; fi
git reset -q --hard origin/main

# (f2) new branch must not rescan commits already on the remote.
git checkout -q -b old-leak
commit c.txt "$leak_line" "leak on branch"
git push -q --no-verify origin old-leak 2>/dev/null
git checkout -q -b newbranch
commit d.txt "clean" "clean on top"
out=$(push origin newbranch)
if pushed refs/heads/newbranch; then ok "new branch skips commits already on the remote"; else bad "new branch rescan: $out"; fi

# (h) direct invocations: env only, no stdin.
git checkout -q main
before=$(git rev-parse HEAD)
commit e.txt "$leak_line" "leak again"
if PRE_COMMIT_REMOTE_NAME=origin PRE_COMMIT_FROM_REF=$before PRE_COMMIT_TO_REF=HEAD "$script" </dev/null >/dev/null 2>&1; then
  bad "direct FROM..TO scan should fail"
else ok "direct FROM..TO scan fails on leak"; fi
if PRE_COMMIT_REMOTE_NAME=origin PRE_COMMIT_FROM_REF=$before PRE_COMMIT_TO_REF=0000000000000000000000000000000000000000 "$script" </dev/null >/dev/null 2>&1; then
  ok "delete push is a no-op"
else bad "delete push should be a no-op"; fi
if PRE_COMMIT_REMOTE_NAME=origin PRE_COMMIT_FROM_REF=$(git rev-parse HEAD) PRE_COMMIT_TO_REF=HEAD "$script" </dev/null >/dev/null 2>&1; then
  ok "empty range passes"
else bad "empty range should pass"; fi

# (m) multi-ref pushes: prek runs the hook once with FROM/TO of a single ref,
# so the script must scan a superset. Both orders must be refused.
new_repo multi
cd "$tmp/multi"
remote=$tmp/multi.git
commit a.txt "hello" "clean root"
git push -q --no-verify origin main 2>/dev/null
git checkout -q -b leaky
commit l.txt "$leak_line" "leak on leaky"
git checkout -q main
git checkout -q -b clean
commit c.txt "clean" "clean on clean"
git checkout -q main
for order in "leaky clean" "clean leaky"; do
  # shellcheck disable=SC2086 # order is two ref names
  out=$(push origin $order)
  if ! pushed refs/heads/leaky && ! pushed refs/heads/clean && [[ $out != *"$key"* && $out == *"leaks found"* ]]; then
    ok "multi-ref push ($order) refused, no ref lands"
  else bad "multi-ref push ($order): $out"; fi
done

# (n) --all with a leaky branch that is not checked out.
out=$(push --all origin)
if ! pushed refs/heads/leaky && ! pushed refs/heads/clean && [[ $out == *"leaks found"* ]]; then
  ok "push --all refused on leaky non-checked-out branch"
else bad "push --all: $out"; fi

# (q) leaky detached HEAD pushed as a second refspec alongside a clean branch.
git branch -q -D leaky # its leak would otherwise be caught via --branches
git checkout -q --detach main
commit d.txt "$leak_line" "leak on detached head"
for order in "clean HEAD:refs/heads/det" "HEAD:refs/heads/det clean"; do
  # shellcheck disable=SC2086 # order is two refspecs
  out=$(push origin $order)
  if ! pushed refs/heads/det && ! pushed refs/heads/clean && [[ $out == *"leaks found"* ]]; then
    ok "detached HEAD refspec ($order) refused, no ref lands"
  else bad "detached HEAD refspec ($order): $out"; fi
done
git checkout -q main

# (o) git failure must not fail open.
if PRE_COMMIT_REMOTE_NAME=origin PRE_COMMIT_FROM_REF='' PRE_COMMIT_TO_REF=refs/heads/does-not-exist "$script" </dev/null >/dev/null 2>&1; then
  bad "unresolvable TO ref should fail"
else ok "unresolvable TO ref fails closed"; fi

# (p) FROM set but unknown locally (remote moved ahead, never fetched): still scans.
git checkout -q -b unfetched main
commit u.txt "$leak_line" "leak behind unknown FROM"
if PRE_COMMIT_REMOTE_NAME=origin PRE_COMMIT_FROM_REF=1111111111111111111111111111111111111111 PRE_COMMIT_TO_REF=HEAD "$script" </dev/null >/dev/null 2>&1; then
  bad "unresolvable FROM should still scan and fail on leak"
else ok "unresolvable FROM falls back to the superset scan"; fi

exit "$fail"
