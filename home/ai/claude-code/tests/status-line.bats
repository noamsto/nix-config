#!/usr/bin/env bats
# Regression suite for status-line.sh's 7d countdown: the monthly reset from
# tmux-og's agent-usage cache caps it when earlier. Run directly:
#   bats home/ai/claude-code/tests/status-line.bats
# or: nix build .#checks.x86_64-linux.deslop-guard (the check bundles this suite)

# shellcheck disable=SC2030,SC2031 # bats runs each test body in its own subshell

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT=${SCRIPT:-$BATS_TEST_DIRNAME/../status-line.sh}
  export OG_AGENT_USAGE_DIR="$BATS_TEST_TMPDIR/usage"
  mkdir -p "$OG_AGENT_USAGE_DIR"
}

_render() {
  local now d5 json
  now=$(date +%s)
  d5=$((now + 5 * 86400 + 3600))
  json=$(jq -n --argjson r "$d5" \
    '{rate_limits: {five_hour: {used_percentage: 10, resets_at: ($r - 400000)}, seven_day: {used_percentage: 60, resets_at: $r}}}')
  printf '%s' "$json" | bash -euo pipefail "$SCRIPT"
}

_cache() {
  local offset=$1
  jq -n --argjson t "$(($(date +%s) + offset))" '{monthly: {reset_at: $t}}' \
    >"$OG_AGENT_USAGE_DIR/claude.json"
}

@test "monthly reset earlier than 7d caps the countdown" {
  _cache $((2 * 86400 + 3600))
  run _render
  [[ $output == *"7d 60% (2d"* ]]
}

@test "no cache keeps the 7d countdown" {
  run _render
  [[ $output == *"7d 60% (5d"* ]]
}

@test "cache without monthly field keeps the 7d countdown" {
  echo '{"other": 1}' >"$OG_AGENT_USAGE_DIR/claude.json"
  run _render
  [[ $output == *"7d 60% (5d"* ]]
}

@test "malformed cache keeps the 7d countdown" {
  echo 'not json' >"$OG_AGENT_USAGE_DIR/claude.json"
  run _render
  [[ $output == *"7d 60% (5d"* ]]
}

@test "past monthly reset keeps the 7d countdown" {
  _cache -3600
  run _render
  [[ $output == *"7d 60% (5d"* ]]
}

@test "later monthly reset keeps the 7d countdown" {
  _cache $((9 * 86400))
  run _render
  [[ $output == *"7d 60% (5d"* ]]
}

@test "symlinked cache file is ignored" {
  _cache $((2 * 86400 + 3600))
  mv "$OG_AGENT_USAGE_DIR/claude.json" "$BATS_TEST_TMPDIR/real.json"
  ln -s "$BATS_TEST_TMPDIR/real.json" "$OG_AGENT_USAGE_DIR/claude.json"
  run _render
  [[ $output == *"7d 60% (5d"* ]]
}

@test "dir resolved from XDG_RUNTIME_DIR when OG_AGENT_USAGE_DIR is unset" {
  unset OG_AGENT_USAGE_DIR
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/xdg/"
  export OG_AGENT_USAGE_DIR="$XDG_RUNTIME_DIR/og-agent-usage-$UID"
  mkdir -p "$OG_AGENT_USAGE_DIR"
  _cache $((2 * 86400 + 3600))
  unset OG_AGENT_USAGE_DIR
  run _render
  [[ $output == *"7d 60% (2d"* ]]
}

@test "wrong-typed monthly field keeps the 7d countdown" {
  echo '{"monthly": "x"}' >"$OG_AGENT_USAGE_DIR/claude.json"
  run _render
  [[ $output == *"7d 60% (5d"* ]]
}

@test "non-object cache keeps the 7d countdown" {
  echo '[1]' >"$OG_AGENT_USAGE_DIR/claude.json"
  run _render
  [[ $output == *"7d 60% (5d"* ]]
}

@test "string monthly reset keeps the 7d countdown" {
  printf '{"monthly": {"reset_at": "%s"}}' "$(($(date +%s) + 86400))" >"$OG_AGENT_USAGE_DIR/claude.json"
  run _render
  [[ $output == *"7d 60% (5d"* ]]
}
