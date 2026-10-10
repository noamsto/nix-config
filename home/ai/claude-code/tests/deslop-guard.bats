#!/usr/bin/env bats
# Regression suite for deslop-guard.sh: the non-source short-circuit (a branch
# whose diff against its deslop base touches only non-source paths may push
# without /deslop), the tag-only push exemption, and the nothing-to-push case
# for a branch behind its upstream. Source paths and branch pushes keep the
# gate. Run directly:
#   bats home/ai/claude-code/tests/deslop-guard.bats
# or: nix build .#checks.x86_64-linux.deslop-guard

bats_require_minimum_version 1.5.0

setup() {
  GUARD=${GUARD:-$BATS_TEST_DIRNAME/../deslop-guard.sh}
  export HOME="$BATS_TEST_TMPDIR/home"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  # Ignore the host's git config so the fixture is hermetic (a global
  # commit.gpgsign/ssh signing key would otherwise break the sandbox).
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  mkdir -p "$HOME" "$TMPDIR"
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  printf 'base\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm base
}

_feed() {
  printf '%s' "$1" | bash "$GUARD"
}

run_guard() {
  local json
  json=$(jq -n --arg c "$1" --arg cwd "$repo" \
    '{tool_name:"Bash",tool_input:{command:$c},session_id:"deslop-guard-test",cwd:$cwd}')
  run --separate-stderr _feed "$json"
}

assert_allow() {
  [ "$status" -eq 0 ]
  [ -z "$output" ] || {
    echo "expected allow, got: $output"
    return 1
  }
}

assert_deny() {
  [ "$status" -eq 0 ]
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$output" >/dev/null || {
    echo "expected deny, got: $output"
    return 1
  }
}

# --- allow: every changed path is non-source ---

@test "allow: branch diff is only app.json" {
  git -C "$repo" checkout -qb feat
  mkdir -p "$repo/apps/mobile"
  printf '{"v":2}\n' >"$repo/apps/mobile/app.json"
  git -C "$repo" add -A
  git -C "$repo" commit -qm json
  run_guard 'git push origin feat'
  assert_allow
}

@test "allow: mixed non-source set (md, yaml, png, lock, docs)" {
  git -C "$repo" checkout -qb feat
  mkdir -p "$repo/docs"
  printf '# changelog\n' >"$repo/CHANGELOG.md"
  printf 'a: 1\n' >"$repo/ci.yaml"
  printf 'y\n' >"$repo/flow.yml"
  printf 'PNG' >"$repo/logo.png"
  printf '{"locked":true}\n' >"$repo/flake.lock"
  printf '# guide\n' >"$repo/docs/guide.md"
  git -C "$repo" add -A
  git -C "$repo" commit -qm mixed
  run_guard 'git push'
  assert_allow
}

@test "allow: deleted non-source file" {
  printf '{"v":1}\n' >"$repo/app.json"
  git -C "$repo" add -A
  git -C "$repo" commit -qm seed
  git -C "$repo" checkout -qb feat
  git -C "$repo" rm -q app.json
  git -C "$repo" commit -qm del
  run_guard 'git push'
  assert_allow
}

@test "allow: non-source path with a space" {
  git -C "$repo" checkout -qb feat
  printf '{"v":1}\n' >"$repo/my data.json"
  git -C "$repo" add -A
  git -C "$repo" commit -qm space
  run_guard 'git push'
  assert_allow
}

@test "allow: non-source path with a newline" {
  git -C "$repo" checkout -qb feat
  printf '{"v":1}\n' >"$repo/a"$'\n'"b.json"
  git -C "$repo" add -A
  git -C "$repo" commit -qm newline
  run_guard 'git push'
  assert_allow
}

# --- deny: a source file is present ---

@test "deny: one shell script among JSON changes" {
  git -C "$repo" checkout -qb feat
  printf '{"v":1}\n' >"$repo/app.json"
  printf '#!/bin/sh\ntrue\n' >"$repo/run.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm mixed
  run_guard 'git push'
  assert_deny
}

@test "deny: one nix file among JSON changes" {
  git -C "$repo" checkout -qb feat
  printf '{"v":1}\n' >"$repo/app.json"
  printf '{}\n' >"$repo/flake.nix"
  git -C "$repo" add -A
  git -C "$repo" commit -qm mixed
  run_guard 'git push'
  assert_deny
}

@test "deny: one TypeScript file among JSON changes" {
  git -C "$repo" checkout -qb feat
  printf '{"v":1}\n' >"$repo/app.json"
  printf 'export const x = 1;\n' >"$repo/x.ts"
  git -C "$repo" add -A
  git -C "$repo" commit -qm mixed
  run_guard 'git push'
  assert_deny
}

@test "deny: deleted source file" {
  printf 'true\n' >"$repo/keep.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm seed
  git -C "$repo" checkout -qb feat
  git -C "$repo" rm -q keep.sh
  git -C "$repo" commit -qm del
  run_guard 'git push'
  assert_deny
}

@test "deny: source renamed to non-source" {
  printf 'true\n' >"$repo/old.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm seed
  git -C "$repo" checkout -qb feat
  git -C "$repo" mv old.sh old.md
  git -C "$repo" commit -qm rename
  run_guard 'git push'
  assert_deny
}

@test "deny: empty diff keeps today's behaviour" {
  run_guard 'git push'
  assert_deny
}

@test "deny: base cannot be resolved (no main, no upstream)" {
  rm -rf "$repo"
  mkdir -p "$repo"
  git -C "$repo" init -q -b topic
  printf '{"v":1}\n' >"$repo/app.json"
  git -C "$repo" add -A
  git -C "$repo" commit -qm json
  run_guard 'git push'
  assert_deny
}

# --- bypass stays working ---

@test "allow: inline bypass with a source change" {
  git -C "$repo" checkout -qb feat
  printf 'true\n' >"$repo/x.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm sh
  run_guard 'ALLOW_PUSH_WITHOUT_DESLOP=1 git push'
  assert_allow
}

@test "allow: env bypass with a source change" {
  git -C "$repo" checkout -qb feat
  printf 'true\n' >"$repo/x.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm sh
  export ALLOW_PUSH_WITHOUT_DESLOP=1
  run_guard 'git push'
  assert_allow
}

# --- tag-only pushes ---

_with_remote() {
  git init -q --bare -b main "$BATS_TEST_TMPDIR/remote.git"
  git -C "$repo" remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git -C "$repo" push -q -u origin main
}

_source_commit() {
  printf 'true\n' >"$repo/x.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm sh
}

@test "allow: push of an existing tag" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push origin v1'
  assert_allow
}

@test "allow: tag created earlier in the same command" {
  _source_commit
  run_guard 'git tag -a v1 -m "deploy: ship it" && git push origin v1'
  assert_allow
}

@test "allow: tag created via git -C earlier in the same command" {
  _source_commit
  run_guard "git -C $repo tag v1; git -C $repo push origin v1"
  assert_allow
}

@test "allow: tag push with 2>&1 and a pipe" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push origin v1 2>&1 | tail -2'
  assert_allow
}

@test "allow: tag push with spaced and file redirections" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push origin v1 > /dev/null 2> err.log &>> all.log'
  assert_allow
}

@test "allow: same-command tag push with redirect (issue repro)" {
  _source_commit
  run_guard 'git tag -a v0.0.0-test -m test && git push origin v0.0.0-test 2>&1 | tail -2'
  assert_allow
}

@test "allow: tag named push-x is not mistaken for the push word" {
  _source_commit
  git -C "$repo" tag push-x
  run_guard 'git push origin push-x'
  assert_allow
}

@test "deny: branch push" {
  _source_commit
  git -C "$repo" checkout -qb feat
  run_guard 'git push origin feat'
  assert_deny
}

@test "deny: mixed tag and branch refspecs" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push origin v1 main'
  assert_deny
}

@test "deny: unknown ref is not a tag" {
  _source_commit
  run_guard 'git push origin v1'
  assert_deny
}

@test "deny: tag creation only in a non-creating command" {
  _source_commit
  run_guard 'echo git tag main; git push origin main'
  assert_deny
}

@test "deny: tag list/delete does not create the tag" {
  _source_commit
  run_guard 'git tag -d main && git push origin main'
  assert_deny
}

@test "deny: tag push followed by a branch push" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push origin v1 && git push origin main'
  assert_deny
}

@test "deny: tag push chained with gh pr create" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push origin v1 && gh pr create --fill'
  assert_deny
}

@test "deny: --follow-tags carries commits" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push --follow-tags origin v1'
  assert_deny
}

# --- branch behind upstream ---

_behind_upstream() {
  _with_remote
  printf 'true\n' >"$repo/up.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm up
  git -C "$repo" push -q origin main
  git -C "$repo" reset -q --hard HEAD~1
}

@test "allow: branch behind upstream with nothing to push" {
  _behind_upstream
  run_guard 'git push'
  assert_allow
}

@test "allow: current-branch push behind upstream by name" {
  _behind_upstream
  run_guard 'git push origin main'
  assert_allow
}

@test "deny: behind upstream plus a local source commit" {
  _behind_upstream
  _source_commit
  run_guard 'git push'
  assert_deny
}

@test "deny: up-to-date branch pushed to another destination" {
  _with_remote
  printf 'true\n' >"$repo/x.sh"
  git -C "$repo" add -A
  git -C "$repo" commit -qm sh
  git -C "$repo" push -q origin main
  run_guard 'git push origin HEAD:release'
  assert_deny
}

@test "deny: gh pr create on a branch equal to its upstream" {
  _with_remote
  git -C "$repo" checkout -qb feat
  _source_commit
  git -C "$repo" push -q -u origin feat
  run_guard 'gh pr create --fill'
  assert_deny
}

# --- bypass probes ---

@test "allow: redirect glued to the tag refspec" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push origin v1>/dev/null'
  assert_allow
}

@test "deny: branch push on a later line after a tag push" {
  _source_commit
  git -C "$repo" tag v1
  run_guard $'git push origin v1\ngit push origin main'
  assert_deny
}

@test "deny: tag pushed to a branch destination" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push origin v1:refs/heads/main'
  assert_deny
}

@test "deny: new tag pushed to a branch destination" {
  _source_commit
  run_guard 'git tag v9 && git push origin v9:refs/heads/main'
  assert_deny
}

@test "deny: peeled tag source" {
  _source_commit
  git -C "$repo" tag v1
  run_guard 'git push origin v1^{}:main'
  assert_deny
}

@test "deny: tag that never gets created shadows a branch" {
  _source_commit
  run_guard 'false && git tag main; git push origin main'
  assert_deny
}

@test "deny: --trailer value is not the tag name" {
  _source_commit
  run_guard 'git tag --trailer main v1; git push origin main'
  assert_deny
}

@test "deny: --all under the upstream exemption" {
  _with_remote
  git -C "$repo" checkout -qb feat
  _source_commit
  git -C "$repo" checkout -q main
  run_guard 'git push --all origin'
  assert_deny
}

@test "deny: second push chained after an up-to-date push" {
  _with_remote
  git -C "$repo" checkout -qb feat
  _source_commit
  git -C "$repo" checkout -q main
  run_guard 'git push origin main && git push origin feat'
  assert_deny
}

# --- repo resolution: the push's own -C / nearest preceding cd ---

# `clean` is up to date with origin; `repo` has an unpushed source commit.
_two_checkouts() {
  _with_remote
  clean="$BATS_TEST_TMPDIR/clean"
  git clone -q "$BATS_TEST_TMPDIR/remote.git" "$clean"
  _source_commit
}

@test "deny: push in a dirty checkout after git -C on a clean one" {
  _two_checkouts
  run_guard "git -C $clean fetch && git -C $repo push origin main"
  assert_deny
}

@test "deny: push in a dirty checkout after cd to a clean one" {
  _two_checkouts
  run_guard "cd $clean && git fetch && cd $repo && git push origin main"
  assert_deny
}

@test "deny: push's own -C wins over an unrelated cd" {
  _two_checkouts
  run_guard "cd $clean && git -C $repo push origin main"
  assert_deny
}

@test "allow: push's own -C on a clean checkout after git -C on a dirty one" {
  _two_checkouts
  run_guard "git -C $repo fetch && git -C $clean push origin main"
  assert_allow
}

# cwd is the clean checkout, so a cd that goes unrecognised falls back to it.
run_guard_from() {
  local json
  json=$(jq -n --arg c "$2" --arg cwd "$1" \
    '{tool_name:"Bash",tool_input:{command:$c},session_id:"deslop-guard-test",cwd:$cwd}')
  run --separate-stderr _feed "$json"
}

@test "deny: cd inside a brace group" {
  _two_checkouts
  run_guard_from "$clean" "{ cd $repo; git push origin main; }"
  assert_deny
}

@test "deny: cd in an if condition" {
  _two_checkouts
  run_guard_from "$clean" "if cd $repo; then git push origin main; fi"
  assert_deny
}

@test "deny: chained relative cd" {
  _two_checkouts
  mkdir "$repo/sub"
  run_guard_from "$clean" "cd $repo && cd sub && git push origin main"
  assert_deny
}

@test "deny: cd-like text inside a quoted commit message" {
  _two_checkouts
  run_guard_from "$clean" "cd $repo && git commit -m 'x; cd $clean' && git push origin main"
  assert_deny
}

@test "deny: double-quoted args before and after the cd" {
  _two_checkouts
  run_guard_from "$clean" "git commit -m \"a\" && cd $repo && git commit -m \"b\" && git push origin main"
  assert_deny
}

@test "deny: single-quoted args around a ;-separated cd" {
  _two_checkouts
  run_guard_from "$clean" "echo 'hi'; cd $repo; echo 'x'; git push origin main"
  assert_deny
}

@test "deny: quoted cd path followed by a quoted separator" {
  _two_checkouts
  run_guard_from "$clean" "cd '$repo' && git commit -m 'x; y' && git push origin main"
  assert_deny
}

@test "deny: git push text inside an earlier quoted message" {
  _two_checkouts
  run_guard_from "$clean" "git commit -m \"note: git push later\" && cd $repo && git push origin main"
  assert_deny
}

@test "deny: cd-like line inside a multi-line quoted message" {
  _two_checkouts
  run_guard_from "$clean" "cd $repo && git commit -m 'first
cd docs for details' && git push origin main"
  assert_deny
}
