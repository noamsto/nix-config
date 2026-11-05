#!/usr/bin/env bats
# Regression suite for attribution-guard.sh, run directly (no PreToolUse
# harness). Run: bats home/ai/agent-hooks/tests/attribution-guard.bats
# or: nix build .#checks.aarch64-darwin.agent-hooks

bats_require_minimum_version 1.5.0

setup_file() {
  export WORK=$BATS_FILE_TMPDIR

  # Files a command may name as its message/body source.
  printf '## Summary\n\nnormal body, no footer\n' >"$WORK/clean.md"
  printf '## Summary\n\n🤖 Generated with [Claude Code]\n' >"$WORK/body.md"
  printf 'fix: a thing\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' >"$WORK/msg.txt"
}

setup() {
  GUARD=${GUARD:-$BATS_TEST_DIRNAME/../attribution-guard.sh}
  WORK=$BATS_FILE_TMPDIR
}

_feed() {
  printf '%s' "$1" | bash "$GUARD"
}

# guard_bash <command> [cwd]
guard_bash() {
  local json
  json=$(jq -n --arg c "$1" --arg d "${2:-}" \
    '{tool_name:"Bash",tool_input:{command:$c}} + (if $d != "" then {cwd:$d} else {} end)')
  run --separate-stderr _feed "$json"
}

guard_json() {
  run --separate-stderr _feed "$1"
}

assert_deny() {
  [ "$status" -eq 0 ]
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$output" >/dev/null || {
    echo "$output"
    return 1
  }
}

assert_allow() {
  [ "$status" -eq 0 ]
  [ -z "$output" ] || {
    echo "$output"
    return 1
  }
}

# --- deny: inline text ---

@test "deny: gh pr create inline --body with the footer" {
  guard_bash 'gh pr create --title x --body "🤖 Generated with [Claude Code]"'
  assert_deny
}

@test "deny: git commit -m with a Co-Authored-By Claude trailer" {
  guard_bash $'git commit -m "fix: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>"'
  assert_deny
}

@test "deny: marker match is case-insensitive" {
  guard_bash 'git commit -m "generated with claude code"'
  assert_deny
}

@test "deny: git tag -a -m with the footer" {
  guard_bash 'git tag -a v1.0 -m "🤖 Generated with Claude Code"'
  assert_deny
}

@test "deny: git commit-tree with a Co-Authored-By trailer" {
  guard_bash 'git commit-tree HEAD^{tree} -m "x\n\nCo-Authored-By: Claude <noreply@anthropic.com>"'
  assert_deny
}

@test "deny: gh issue create --body with the footer" {
  guard_bash 'gh issue create --title t --body "🤖 Generated with [Claude Code]"'
  assert_deny
}

@test "deny: gh api with an inline body field" {
  guard_bash "gh api repos/o/r/issues -f body='Generated with [Claude Code]'"
  assert_deny
}

# --- deny: HEREDOC body ---

@test "deny: HEREDOC body carries the footer" {
  guard_bash $'gh pr create --title x --body-file - <<\'EOF\'\n## Summary\n\n🤖 Generated with [Claude Code]\nEOF'
  assert_deny
}

# --- deny: body/message file ---

@test "deny: gh --body-file names a file with the footer" {
  guard_bash "gh pr create --body-file $WORK/body.md"
  assert_deny
}

@test "deny: gh --body-file= with a relative path resolves against cwd" {
  guard_bash 'gh pr create --body-file=body.md' "$WORK"
  assert_deny
}

@test "deny: git commit -F names a message file with a trailer" {
  guard_bash 'git commit -F msg.txt' "$WORK"
  assert_deny
}

@test "deny: git commit --file= names a message file with a trailer" {
  guard_bash "git commit --file=$WORK/msg.txt"
  assert_deny
}

@test "deny: git commit -F<file> attached short form reads the message file" {
  guard_bash "git commit -F$WORK/msg.txt"
  assert_deny
}

@test "deny: gh -F<file> attached short form reads the body file" {
  guard_bash "gh pr create -F$WORK/body.md"
  assert_deny
}

# --- allow: qualifying command without a marker ---

@test "allow: gh pr create without a marker" {
  guard_bash 'gh pr create --title x --body "just the change"'
  assert_allow
}

@test "allow: git commit -m without a marker" {
  guard_bash 'git commit -m "fix: a thing"'
  assert_allow
}

@test "allow: git tag -a -m without a marker" {
  guard_bash 'git tag -a v1.0 -m "release"'
  assert_allow
}

@test "allow: gh issue comment without a marker" {
  guard_bash 'gh issue comment 1 --body "on it"'
  assert_allow
}

@test "allow: --body-file naming a clean file" {
  guard_bash "gh pr create --body-file $WORK/clean.md"
  assert_allow
}

@test "allow: git commit -F naming a clean file" {
  guard_bash "git commit -F $WORK/clean.md"
  assert_allow
}

# --- allow: marker text outside a commit/PR/issue command ---

@test "allow: rg merely mentioning the text" {
  guard_bash "rg 'Generated with' ."
  assert_allow
}

@test "allow: echo merely mentioning the text" {
  guard_bash "echo '🤖 Generated with [Claude Code]'"
  assert_allow
}

@test "allow: git log grep merely mentioning the text" {
  guard_bash "git log --grep='Generated with Claude Code'"
  assert_allow
}

@test "allow: gh api without a body field" {
  guard_bash "gh api repos/o/r/commits -f per_page=5 'Generated with Claude Code'"
  assert_allow
}

# --- allow: non-Bash tool, missing file ---

@test "allow: a non-Bash tool is untouched" {
  guard_json '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
  assert_allow
}

@test "allow: a missing body file is not a denial" {
  guard_bash "gh pr create --body-file $WORK/does-not-exist.md"
  assert_allow
}
