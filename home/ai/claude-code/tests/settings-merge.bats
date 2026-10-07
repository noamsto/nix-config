#!/usr/bin/env bats
# Regression suite for settings-merge.sh: deep-merges the nix overlay with the
# caller's --settings layers, concatenating hooks and permission rules, and
# rejects layers that would remove overlay hooks or rules. Run directly:
#   bats home/ai/claude-code/tests/settings-merge.bats
# or: nix build .#checks.x86_64-linux.deslop-guard

bats_require_minimum_version 1.5.0

setup() {
  MERGE=${MERGE:-$BATS_TEST_DIRNAME/../settings-merge.sh}
  export HOME="$BATS_TEST_TMPDIR/home"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
  mkdir -p "$HOME" "$TMPDIR" "$XDG_RUNTIME_DIR"
  overlay="$BATS_TEST_TMPDIR/overlay.json"
  cat >"$overlay" <<'EOF'
{
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "overlay-pre"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "overlay-ups"}]}]
  },
  "statusLine": {"type": "command", "command": "overlay-status"},
  "permissions": {"allow": ["Bash(ls *)"], "deny": ["Bash(rm -rf *)"]},
  "model": "opus",
  "env": {"A": "1"}
}
EOF
}

merge() {
  run --separate-stderr bash "$MERGE" "$overlay" "$@"
}

assert_fail() {
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *claude:* ]]
}

@test "inline layer keeps overlay hooks, statusLine, permissions and adds its keys" {
  merge '{"enabledPlugins":{"x@y":false}}'
  [ "$status" -eq 0 ]
  jq -e '.enabledPlugins["x@y"] == false
    and (.hooks.PreToolUse | length) == 1
    and (.hooks.UserPromptSubmit | length) == 1
    and .statusLine.command == "overlay-status"
    and .permissions.allow == ["Bash(ls *)"]
    and .permissions.deny == ["Bash(rm -rf *)"]' "$output"
}

@test "caller hooks concatenate after the overlay's" {
  merge '{"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"caller-pre"}]}]}}'
  [ "$status" -eq 0 ]
  jq -e '(.hooks.PreToolUse | length) == 2
    and .hooks.PreToolUse[0].hooks[0].command == "overlay-pre"
    and .hooks.PreToolUse[1].hooks[0].command == "caller-pre"
    and (.hooks.UserPromptSubmit | length) == 1' "$output"
}

@test "permissions concatenate, caller scalar wins, objects deep-merge" {
  merge '{"permissions":{"allow":["Bash(git *)"]},"model":"sonnet","env":{"B":"2"}}'
  [ "$status" -eq 0 ]
  jq -e '.permissions.allow == ["Bash(ls *)", "Bash(git *)"]
    and .permissions.deny == ["Bash(rm -rf *)"]
    and .model == "sonnet"
    and .env == {"A": "1", "B": "2"}' "$output"
}

@test "layers apply in order: a later scalar wins" {
  printf '{"model":"haiku","env":{"C":"3"}}' >"$BATS_TEST_TMPDIR/first.json"
  merge "$BATS_TEST_TMPDIR/first.json" '{"model":"sonnet"}'
  [ "$status" -eq 0 ]
  jq -e '.model == "sonnet" and .env == {"A": "1", "C": "3"}' "$output"
}

@test "invalid JSON fails" {
  merge '{bad'
  assert_fail
}

@test "nonexistent path fails and names the path" {
  merge "$BATS_TEST_TMPDIR/nope.json"
  assert_fail
  [[ "$stderr" == *"$BATS_TEST_TMPDIR/nope.json"* ]]
}

@test "non-object JSON fails" {
  merge '[1]'
  assert_fail
}

@test "output is private and under XDG_RUNTIME_DIR/claude-settings" {
  merge '{}'
  [ "$status" -eq 0 ]
  [[ "$output" == "$XDG_RUNTIME_DIR/claude-settings/"* ]]
  [ "$(stat -c %a "$output")" = 600 ]
  [ "$(stat -c %a "$XDG_RUNTIME_DIR/claude-settings")" = 700 ]
}

@test "identical inputs give an identical path" {
  merge '{"model":"sonnet"}'
  [ "$status" -eq 0 ]
  first=$output
  merge '{"model":"sonnet"}'
  [ "$output" = "$first" ]
}

@test "without XDG_RUNTIME_DIR the file is in a stable private per-user dir" {
  unset XDG_RUNTIME_DIR
  merge '{"model":"sonnet"}'
  [ "$status" -eq 0 ]
  first=$output
  [[ "$first" == "$TMPDIR/claude-settings-$(id -u)/"* ]]
  [ "$(stat -c %a "$TMPDIR/claude-settings-$(id -u)")" = 700 ]
  jq -e '.model == "sonnet"' "$first"
  merge '{"model":"sonnet"}'
  [ "$output" = "$first" ]
}

@test "a symlinked state dir is refused" {
  unset XDG_RUNTIME_DIR
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  ln -s "$BATS_TEST_TMPDIR/elsewhere" "$TMPDIR/claude-settings-$(id -u)"
  merge '{}'
  assert_fail
}

@test "inline content with leading space is never echoed" {
  merge ' {"env":{"X":"CANARY1"}'
  assert_fail
  [[ "$stderr" != *CANARY1* ]]
}

@test "inline content with leading newline is never echoed" {
  merge $'\n{"env":{"X":"CANARY2"}'
  assert_fail
  [[ "$stderr" != *CANARY2* ]]
}

@test "several JSON texts in one value fail with a claude: message" {
  merge '{"hooks":5} {}'
  assert_fail
}

@test "a layer over 200 KB merges" {
  jq -n '{permissions: {allow: [range(20000) | "Bash(cmd-\(.) *)"]}}' >"$BATS_TEST_TMPDIR/big.json"
  [ "$(stat -c %s "$BATS_TEST_TMPDIR/big.json")" -gt 200000 ]
  merge "$BATS_TEST_TMPDIR/big.json"
  [ "$status" -eq 0 ]
  jq -e '(.permissions.allow | length) == 20001' "$output"
}

@test "layers that would remove overlay hooks or rules fail" {
  local layer
  for layer in \
    '{"hooks":null}' \
    '{"hooks":{"PreToolUse":null}}' \
    '{"permissions":{"allow":"x"}}' \
    '{"permissions":null}' \
    '{"permissions":{"allow":null}}' \
    '{"permissions":{"deny":null}}' \
    '{"disableAllHooks":true}'; do
    merge "$layer"
    assert_fail
  done
}
