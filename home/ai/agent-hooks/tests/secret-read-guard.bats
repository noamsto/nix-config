#!/usr/bin/env bats
# Regression suite for secret-read-guard.sh, run directly (no PreToolUse
# harness). Run: bats home/ai/agent-hooks/tests/secret-read-guard.bats
# or: nix build .#checks.x86_64-linux.agent-hooks

bats_require_minimum_version 1.5.0

setup() {
  GUARD=${GUARD:-$BATS_TEST_DIRNAME/../secret-read-guard.sh}
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

# --- deny: bare dumpers, wrapped and terminated in every accepted way ---

@test "deny: bare env" {
  guard_bash 'env'
  assert_deny
}

@test "deny: bare printenv" {
  guard_bash 'printenv'
  assert_deny
}

@test "deny: absolute path to env" {
  guard_bash '/usr/bin/env'
  assert_deny
}

@test "deny: relative path to printenv" {
  guard_bash './bin/printenv'
  assert_deny
}

@test "deny: command env" {
  guard_bash 'command env'
  assert_deny
}

@test "deny: command -- env" {
  guard_bash 'command -- env'
  assert_deny
}

@test "deny: sudo env" {
  guard_bash 'sudo env'
  assert_deny
}

@test "deny: sudo -u root env" {
  guard_bash 'sudo -u root env'
  assert_deny
}

@test "deny: env terminated by semicolon" {
  guard_bash 'env; ls'
  assert_deny
}

@test "deny: env piped to grep" {
  guard_bash 'env | grep X'
  assert_deny
}

@test "deny: env after &&" {
  guard_bash 'ls && env'
  assert_deny
}

@test "deny: env inside parens" {
  guard_bash '(env)'
  assert_deny
}

@test "deny: env followed by comment" {
  guard_bash 'env # c'
  assert_deny
}

@test "deny: env with output redirect" {
  guard_bash 'env >/tmp/x'
  assert_deny
}

@test "deny: env with fd redirect" {
  guard_bash 'env 2>&1'
  assert_deny
}

@test "deny: env on its own line after a newline" {
  guard_bash $'ls\nenv'
  assert_deny
}

@test "deny: env -0 still dumps, just NUL-separated" {
  guard_bash 'env -0'
  assert_deny
}

@test "deny: bare set" {
  guard_bash 'set'
  assert_deny
}

@test "deny: declare -p with no name" {
  guard_bash 'declare -p'
  assert_deny
}

@test "deny: declare -p NAME still dumps that variable" {
  guard_bash 'declare -p FOO'
  assert_deny
}

@test "deny: export -p" {
  guard_bash 'export -p'
  assert_deny
}

@test "deny: typeset -p" {
  guard_bash 'typeset -p'
  assert_deny
}

@test "deny: declare -x with no name" {
  guard_bash 'declare -x'
  assert_deny
}

@test "deny: set -S NAME always prints" {
  guard_bash 'set -S FOO'
  assert_deny
}

@test "deny: tmux show-environment" {
  guard_bash 'tmux show-environment'
  assert_deny
}

@test "deny: systemctl --user show-environment" {
  guard_bash 'systemctl --user show-environment'
  assert_deny
}

@test "deny: launchctl getenv NAME" {
  guard_bash 'launchctl getenv FOO'
  assert_deny
}

@test "deny: bash -c 'env'" {
  guard_bash $'bash -c \'env\''
  assert_deny
}

@test "deny: sh -c \"printenv\"" {
  guard_bash 'sh -c "printenv"'
  assert_deny
}

@test "deny: bash -c 'declare -p'" {
  guard_bash $'bash -c \'declare -p\''
  assert_deny
}

@test "deny: fish -c 'set -gx' with no name" {
  guard_bash $'fish -c \'set -gx\''
  assert_deny
}

@test "deny: fish -c 'set -S'" {
  guard_bash $'fish -c \'set -S\''
  assert_deny
}

@test "deny: echo \"\$(env)\" dumps through a substitution" {
  # shellcheck disable=SC2016
  guard_bash 'echo "$(env)"'
  assert_deny
}

@test "deny: echo backtick-printenv-backtick" {
  # shellcheck disable=SC2016
  guard_bash 'echo `printenv`'
  assert_deny
}

@test "deny: cat /proc/self/environ" {
  guard_bash 'cat /proc/self/environ'
  assert_deny
}

@test "deny: echo of a secret-named variable" {
  # shellcheck disable=SC2016
  guard_bash 'echo $MY_API_KEY'
  assert_deny
}

@test "deny: cat .env" {
  guard_bash 'cat .env'
  assert_deny
}

@test "deny: grep over .env with default output" {
  guard_bash 'grep FOO .env'
  assert_deny
}

# --- allow: ordinary, non-dumping uses of the same words ---

@test "allow: env FOO=1 make runs make, not a dump" {
  guard_bash 'env FOO=1 make'
  assert_allow
}

@test "allow: envsubst is not env" {
  guard_bash 'envsubst < a'
  assert_allow
}

@test "allow: echo env, env is just an argument" {
  guard_bash 'echo env'
  assert_allow
}

@test "allow: printenv HOME reads a single name" {
  guard_bash 'printenv HOME'
  assert_allow
}

@test "allow: rg over a quoted pattern mentioning env" {
  guard_bash $'rg \'env|printenv\' f'
  assert_allow
}

@test "allow: command -v env only checks for the binary" {
  guard_bash 'command -v env'
  assert_allow
}

@test "allow: echo then env, then is not a real separator here" {
  guard_bash 'echo then env'
  assert_allow
}

@test "allow: env -i make runs make in a cleared env" {
  guard_bash 'env -i make'
  assert_allow
}

@test "allow: xargs env cmd runs cmd, not a dump" {
  guard_bash 'xargs env cmd'
  assert_allow
}

@test "allow: set -x is bash xtrace, not a dump" {
  guard_bash 'set -x'
  assert_allow
}

@test "allow: fish -c 'set -gx PATH a' is an assignment" {
  guard_bash $'fish -c \'set -gx PATH a\''
  assert_allow
}

@test "allow: bash -c 'true' has no dumper" {
  guard_bash $'bash -c \'true\''
  assert_allow
}

@test "allow: cat .env.example is a committed template" {
  guard_bash 'cat .env.example'
  assert_allow
}

@test "allow: grep -c FOO .env only counts matches" {
  guard_bash 'grep -c FOO .env'
  assert_allow
}

@test "allow: test -f .env only checks existence" {
  guard_bash 'test -f .env'
  assert_allow
}

# --- non-Bash tools ---

@test "deny: Read .env" {
  guard_json '{"tool_name":"Read","tool_input":{"file_path":".env"}}'
  assert_deny
}

@test "allow: Read .env.example" {
  guard_json '{"tool_name":"Read","tool_input":{"file_path":".env.example"}}'
  assert_allow
}

@test "deny: Grep .env with output_mode content" {
  guard_json '{"tool_name":"Grep","tool_input":{"path":".env","output_mode":"content"}}'
  assert_deny
}

@test "allow: Grep .env with output_mode count" {
  guard_json '{"tool_name":"Grep","tool_input":{"path":".env","output_mode":"count"}}'
  assert_allow
}

@test "allow: unrelated tool_name Write" {
  guard_json '{"tool_name":"Write","tool_input":{}}'
  assert_allow
}

@test "allow: empty input" {
  guard_json '{}'
  assert_allow
}

# --- known bugs: assert the INTENDED deny, skipped until the fix lands ---

@test "deny: env -u NAME still dumps the rest of the environment" {
  skip "#414: bare env -u NAME still dumps the environment"
  guard_bash 'env -u NAME'
  assert_deny
}

@test "deny: p\\rintenv, a backslash-escaped printenv" {
  skip "#412: a backslash-escaped word (p\\rintenv) still runs printenv"
  guard_bash 'p\rintenv'
  assert_deny
}

@test "deny: timeout 5 env still dumps" {
  skip "#397: timeout is not a recognised command-position prefix"
  guard_bash 'timeout 5 env'
  assert_deny
}
