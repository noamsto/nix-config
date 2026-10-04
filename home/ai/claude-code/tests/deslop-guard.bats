#!/usr/bin/env bats
# Regression suite for deslop-guard.sh's non-source short-circuit: a branch whose
# diff against its deslop base touches only non-source paths may push without
# /deslop, while any source path keeps the gate. Run directly:
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
