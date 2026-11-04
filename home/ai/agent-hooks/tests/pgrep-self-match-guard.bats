#!/usr/bin/env bats
# Regression suite for pgrep-self-match-guard.sh, run directly (no PreToolUse
# harness). Run: bats home/ai/agent-hooks/tests/pgrep-self-match-guard.bats
# or: nix build .#checks.x86_64-linux.agent-hooks

bats_require_minimum_version 1.5.0

setup() {
  GUARD=${GUARD:-$BATS_TEST_DIRNAME/../pgrep-self-match-guard.sh}
}

_feed() {
  printf '%s' "$1" | bash "$GUARD"
}

guard_bash() {
  local json
  json=$(jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}')
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

# --- deny ---

@test "deny: pgrep -f with regex pattern" {
  guard_bash 'pgrep -f "bats .*-j 8"'
  assert_deny
}

@test "deny: pgrep -af" {
  guard_bash "pgrep -af 'nix flake check'"
  assert_deny
}

@test "deny: pgrep -fa" {
  guard_bash 'pgrep -fa foo'
  assert_deny
}

@test "deny: pkill -f" {
  guard_bash 'pkill -f foo'
  assert_deny
}

@test "deny: pgrep --full" {
  guard_bash 'pgrep --full foo'
  assert_deny
}

@test "deny: pgrep -u root -f" {
  guard_bash 'pgrep -u root -f foo'
  assert_deny
}

@test "deny: incident loop" {
  guard_bash 'for i in $(seq 1 20); do pgrep -f "bats .*-j 8" >/dev/null || break; sleep 30; done'
  assert_deny
}

@test "deny: absolute path pkill" {
  guard_bash '/usr/bin/pkill -f foo'
  assert_deny
}

@test "deny: sudo pkill -f" {
  guard_bash 'sudo pkill -f foo'
  assert_deny
}

@test "deny: after assignment statement" {
  guard_bash 'x=1; pgrep -f foo'
  assert_deny
}

@test "deny: inside command substitution" {
  guard_bash 'echo $(pgrep -f foo)'
  assert_deny
}

@test "deny: while pgrep -f" {
  guard_bash 'while pgrep -f foo; do sleep 1; done'
  assert_deny
}

@test "deny: until ! pgrep -f" {
  guard_bash 'until ! pgrep -f foo; do sleep 1; done'
  assert_deny
}

@test "deny: if pgrep -f" {
  guard_bash 'if pgrep -f foo; then echo y; fi'
  assert_deny
}

@test "deny: NAME=value prefix" {
  guard_bash 'FOO=1 pgrep -f x'
  assert_deny
}

@test "deny: env prefix" {
  guard_bash 'env pgrep -f x'
  assert_deny
}

@test "deny: nohup prefix" {
  guard_bash 'nohup pkill -f x'
  assert_deny
}

@test "deny: timeout prefix" {
  guard_bash 'timeout 5 pgrep -f x'
  assert_deny
}

@test "deny: timeout wrapping bash -c loop" {
  guard_bash 'timeout 300 bash -c "while pgrep -f foo; do sleep 1; done"'
  assert_deny
}

@test "deny: bash -c" {
  guard_bash 'bash -c "pgrep -f foo"'
  assert_deny
}

@test "deny: sh -c single-quoted" {
  guard_bash "sh -c 'pgrep -f foo'"
  assert_deny
}

@test "deny: bash -lc" {
  guard_bash "bash -lc 'pgrep -f foo'"
  assert_deny
}

@test "deny: watch -n1" {
  guard_bash 'watch -n1 pgrep -f foo'
  assert_deny
}

@test "deny: watch -n 1" {
  guard_bash 'watch -n 1 pgrep -f foo'
  assert_deny
}

@test "deny: quoted line starting with pgrep fails closed" {
  guard_bash $'git commit -m $\'fix\npgrep -f loop\''
  assert_deny
}

@test "deny: backslash-newline continuation before the flag" {
  guard_bash $'while pgrep \\\n  -f "bats .*-j 8" >/dev/null; do sleep 30; done'
  assert_deny
}

@test "deny: output carries exact reason" {
  guard_bash 'pkill -f foo'
  assert_deny
  [ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")" = "pgrep/pkill -f matches its own shell; use the bracket trick ('[b]ats') or wait on a captured pid (cmd & p=\$!; wait \$p)" ]
}

# --- allow ---

@test "allow: bracket trick" {
  guard_bash "pgrep -f '[b]ats'"
  assert_allow
}

@test "allow: bracket trick with -af" {
  guard_bash "pgrep -af '[n]ix flake check'"
  assert_allow
}

@test "allow: pgrep -x" {
  guard_bash 'pgrep -x bats'
  assert_allow
}

@test "allow: plain pgrep" {
  guard_bash 'pgrep bats'
  assert_allow
}

@test "allow: plain pkill" {
  guard_bash 'pkill bats'
  assert_allow
}

@test "allow: pidof" {
  guard_bash 'pidof bats'
  assert_allow
}

@test "allow: pgrep -F pidfile" {
  guard_bash 'pgrep -F pidfile'
  assert_allow
}

@test "allow: bracket trick then chained command" {
  guard_bash "pgrep -f '[b]ats' && echo y"
  assert_allow
}

@test "allow: pgrep only in commit message" {
  guard_bash 'git commit -m "fix pgrep -f loop"'
  assert_allow
}

@test "allow: pgrep only in quoted echo" {
  guard_bash "echo 'pgrep -f x'"
  assert_allow
}

@test "allow: while with bracket trick" {
  guard_bash "while pgrep -f '[f]oo'; do sleep 1; done"
  assert_allow
}

@test "allow: bash -c with bracket trick" {
  guard_bash "bash -c \"pgrep -f '[f]oo'\""
  assert_allow
}

@test "allow: bash -c with pgrep -x" {
  guard_bash "bash -c 'pgrep -x foo'"
  assert_allow
}

@test "allow: non-Bash tool" {
  guard_json '{"tool_name":"Read","tool_input":{"command":"pgrep -f foo"}}'
  assert_allow
}
