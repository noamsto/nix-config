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

# --- dequoted view: backslash escapes and quote removal (#417 #418 #419) ---

@test "deny: b\\ash -c 'env', a backslash-escaped interpreter" {
  guard_bash $'b\\ash -c \'env\''
  assert_deny
}

@test "deny: bash -\\c 'env', a backslash-escaped -c flag" {
  guard_bash $'bash -\\c \'env\''
  assert_deny
}

@test "deny: f\\ish -c 'set -x', a backslash-escaped fish" {
  guard_bash $'f\\ish -c \'set -x\''
  assert_deny
}

@test "deny: b''ash -c 'env', an empty single-quote pair in the interpreter" {
  guard_bash $'b\'\'ash -c \'env\''
  assert_deny
}

@test "deny: b\"\"ash -c 'env', an empty double-quote pair in the interpreter" {
  guard_bash $'b""ash -c \'env\''
  assert_deny
}

@test "deny: \"bash\" -c 'env', a quoted interpreter" {
  guard_bash $'"bash" -c \'env\''
  assert_deny
}

@test "deny: bash '-c' 'env', a quoted -c flag" {
  guard_bash $'bash \'-c\' \'env\''
  assert_deny
}

@test "deny: echo 'bash' -c env, a quoted interpreter word" {
  guard_bash $'echo \'bash\' -c env'
  assert_deny
}

@test "deny: cat /pro\\c/1/environ, a backslash inside /proc" {
  guard_bash 'cat /pro\c/1/environ'
  assert_deny
}

@test "deny: cat /proc/1/env\\iron, a backslash inside environ" {
  guard_bash 'cat /proc/1/env\iron'
  assert_deny
}

@test "deny: cat /proc/1/e''nviron, an empty quote pair inside environ" {
  guard_bash $'cat /proc/1/e\'\'nviron'
  assert_deny
}

@test "deny: cat \\.env, a backslash before the dot" {
  guard_bash 'cat \.env'
  assert_deny
}

@test "deny: cat .e''nv, an empty single-quote pair inside .env" {
  guard_bash $'cat .e\'\'nv'
  assert_deny
}

@test "deny: cat ./.e\"\"nv, an empty double-quote pair inside .env" {
  guard_bash 'cat ./.e""nv'
  assert_deny
}

@test "deny: cat .n\\etrc, a backslash inside .netrc" {
  guard_bash 'cat .n\etrc'
  assert_deny
}

@test "deny: head .env\\.local, a backslash inside .env.local" {
  guard_bash 'head .env\.local'
  assert_deny
}

@test "deny: bash -c 'cat \\.env', an escaped .env inside an inner command" {
  guard_bash $'bash -c \'cat \\.env\''
  assert_deny
}

@test "deny: bash -c 'grep FOO .env', a content-reading grep inside an inner command" {
  guard_bash $'bash -c \'grep FOO .env\''
  assert_deny
}

@test "deny: cat .env .env.ex\\ample, an exemption must not cover the plain .env" {
  guard_bash 'cat .env .env.ex\ample'
  assert_deny
}

@test "deny: cat .env .e''nv.example, an exemption must not cover the plain .env" {
  guard_bash $'cat .env .e\'\'nv.example'
  assert_deny
}

@test "deny: grep FOO .env; bash -\\c true, an exemption in one view must not cover another" {
  guard_bash 'grep FOO .env; bash -\c true'
  assert_deny
}

@test "deny: fish -c 'set -x', unescaped" {
  guard_bash $'fish -c \'set -x\''
  assert_deny
}

@test "deny: cat /proc/1/environ, unescaped" {
  guard_bash 'cat /proc/1/environ'
  assert_deny
}

@test "deny: ba\$''sh -c 'env', an empty ANSI-C quote pair in the interpreter" {
  guard_bash $'ba$\'\'sh -c \'env\''
  assert_deny
}

@test "deny: \$'bash' -c 'env', an ANSI-C quoted interpreter" {
  guard_bash $'$\'bash\' -c \'env\''
  assert_deny
}

@test "deny: bash \$'-c' 'env', an ANSI-C quoted -c flag" {
  guard_bash $'bash $\'-c\' \'env\''
  assert_deny
}

@test "deny: bash \$\"-c\" 'env', a locale-quoted -c flag" {
  guard_bash $'bash $"-c" \'env\''
  assert_deny
}

@test "deny: cat .e\$''nv, an empty ANSI-C quote pair inside .env" {
  guard_bash $'cat .e$\'\'nv'
  assert_deny
}

@test "deny: cat /proc/1/envi\$''ron, an empty ANSI-C quote pair inside environ" {
  guard_bash $'cat /proc/1/envi$\'\'ron'
  assert_deny
}

@test "deny: bash -c \$\"env\", a locale-quoted -c body" {
  guard_bash 'bash -c $"env"'
  assert_deny
}

@test "deny: an escaped interpreter on the line after a comment with an apostrophe" {
  guard_bash $'echo hi # it\'s done\nb\\ash -c env'
  assert_deny
}

@test "deny: b\\ash -c with a backslash-newline before the body" {
  guard_bash $'b\\ash -c \\\n  \'env\''
  assert_deny
}

@test "deny: x=\$(b\\ash -c env), an escaped interpreter in a substitution" {
  # shellcheck disable=SC2016
  guard_bash 'x=$(b\ash -c env)'
  assert_deny
}

@test "deny: bash -c 'true'; b\\ash -c env, a second -c after a harmless one" {
  guard_bash $'bash -c \'true\'; b\\ash -c env'
  assert_deny
}

@test "deny: cat /proc/1/environ followed by a heredoc larger than the pipe buffer" {
  local body json
  body=$(printf 'line of filler text %s\n' {1..8000})
  ((${#body} > 120000))
  # Through stdin: one argv string this long exceeds the kernel's per-argument limit.
  json=$(printf '%s' "cat /proc/1/environ; cat <<'EOF'"$'\n'"$body"$'\n'"EOF" |
    jq -Rs '{tool_name:"Bash",tool_input:{command:.}}')
  guard_json "$json"
  assert_deny
}

@test "allow: bash -c 'echo hi'" {
  guard_bash $'bash -c \'echo hi\''
  assert_allow
}

@test "allow: cat README.md" {
  guard_bash 'cat README.md'
  assert_allow
}

@test "allow: ls /proc/1/" {
  guard_bash 'ls /proc/1/'
  assert_allow
}

@test "allow: grep '\\.env' file, a literal backslash in a pattern" {
  guard_bash $'grep \'\\.env\' file'
  assert_allow
}

@test "allow: rg \"\\.env\" src, a literal backslash in a pattern" {
  guard_bash 'rg "\.env" src'
  assert_allow
}

@test "allow: echo 'a\\.env', a literal backslash in data" {
  guard_bash $'echo \'a\\.env\''
  assert_allow
}

@test "allow: cat .e''nv.example, a quoted-in-the-middle example file" {
  guard_bash $'cat .e\'\'nv.example'
  assert_allow
}

@test "allow: rg 'foo|bash -c env x' ., the words sit inside one pattern" {
  guard_bash $'rg \'foo|bash -c env x\' .'
  assert_allow
}

@test "allow: test -f \\.env only checks existence" {
  guard_bash 'test -f \.env'
  assert_allow
}

@test "allow: grep -c FOO \\.env only counts matches" {
  guard_bash 'grep -c FOO \.env'
  assert_allow
}

@test "allow: echo \"x<CR>bash<CR>-c<CR>env\", a quoted CR is not a separator" {
  guard_bash $'echo "x\rbash\r-c\renv"'
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
