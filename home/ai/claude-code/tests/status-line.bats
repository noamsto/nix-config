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
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR" "$PROJ"
  unset CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_AUTOCOMPACT_PCT_OVERRIDE DISABLE_COMPACT DISABLE_AUTO_COMPACT
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

# --- Context measured against the auto-compact trigger ---

_ctx() {
  local pct=${1:-10}
  jq -n --arg p "$pct" --arg d "${NO_PROJ-$PROJ}" --arg m "${MODEL_ID:-claude-opus-5}" --arg c "${CTX_SIZE:-1000000}" '
    {model: {id: $m, display_name: "Opus"},
     context_window: {context_window_size: ($c | tonumber), used_percentage: ($p | tonumber)}}
    + (if $d == "" then {} else {workspace: {project_dir: $d}} end)' |
    bash -euo pipefail "$SCRIPT"
}

_settings() {
  mkdir -p "$(dirname "$1")"
  printf '%s' "$2" >"$1"
}

_user_settings() { _settings "$CLAUDE_CONFIG_DIR/settings.json" "$1"; }

_assert_no_marker() { [[ $output != *"no-ac"* ]]; }

@test "no auto-compact setting measures against the full window" {
  run _ctx
  [ "$status" -eq 0 ]
  [[ $output == *"100k/1M"* ]]
  _assert_no_marker
}

@test "env window shrinks the denominator to the trigger" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
  run _ctx
  [[ $output == *"100k/167k"* ]]
  _assert_no_marker
}

@test "env window 400000 gives a 367k trigger" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "env window below 100000 is clamped up" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=50000
  run _ctx
  [[ $output == *"100k/67k"* ]]
}

@test "env window beyond 12 digits is capped to the model window" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=99999999999999999999999
  run _ctx
  [[ $output == *"100k/967k"* ]]
}

@test "env window above 1000000 is capped before clamping" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=5000000
  run _ctx
  [[ $output == *"100k/967k"* ]]
}

@test "invalid env window is ignored" {
  local v
  for v in abc -5 0 1e5 '' ' '; do
    CLAUDE_CODE_AUTO_COMPACT_WINDOW=$v run _ctx
    [ "$status" -eq 0 ]
    [[ $output == *"100k/1M"* ]]
  done
}

@test "env window with leading zeros is read as decimal" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=0400000
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "top-level autoCompactWindow in user settings" {
  _user_settings '{"autoCompactWindow": 400000}'
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "user settings fall back to HOME/.claude without CLAUDE_CONFIG_DIR" {
  unset CLAUDE_CONFIG_DIR
  _settings "$HOME/.claude/settings.json" '{"autoCompactWindow": 400000}'
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "configured window above the model window is capped to it" {
  _user_settings '{"autoCompactWindow": 500000}'
  CTX_SIZE=300000 run _ctx
  [[ $output == *"30k/267k"* ]]
}

@test "out-of-range top-level autoCompactWindow is ignored" {
  local v
  for v in 50000 99999 1000001 5000000 0 -5 150000.5 '"auto"' '"400000"' true null; do
    _user_settings "{\"autoCompactWindow\": $v}"
    run _ctx
    [ "$status" -eq 0 ]
    [[ $output == *"100k/1M"* ]]
  done
}

@test "top-level bounds are inclusive" {
  _user_settings '{"autoCompactWindow": 100000}'
  run _ctx
  [[ $output == *"100k/67k"* ]]
  _user_settings '{"autoCompactWindow": 1000000}'
  run _ctx
  [[ $output == *"100k/967k"* ]]
}

@test "out-of-range per-model autoCompactWindow is ignored" {
  local v
  for v in 50000 1000001 0 -5 150000.5 '"400000"' true; do
    _user_settings "{\"modelSettings\": {\"claude-opus-5\": {\"autoCompactWindow\": $v}}}"
    run _ctx
    [ "$status" -eq 0 ]
    [[ $output == *"100k/1M"* ]]
  done
}

@test "invalid per-model value falls back to the top-level window" {
  _user_settings '{"autoCompactWindow": 400000, "modelSettings": {"claude-opus-5": {"autoCompactWindow": 50000}}}'
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "invalid higher-layer top-level value keeps a lower-layer per-model window" {
  local v
  _user_settings '{"modelSettings": {"claude-opus-5": {"autoCompactWindow": 200000}}}'
  for v in 50000 5000000 150000.5 '"auto"'; do
    _settings "$PROJ/.claude/settings.json" "{\"autoCompactWindow\": $v}"
    run _ctx
    [[ $output == *"100k/167k"* ]]
  done
}

@test "modelSettings for the model beats top-level autoCompactWindow" {
  _user_settings '{"autoCompactWindow": 400000, "modelSettings": {"claude-opus-5": {"autoCompactWindow": 200000}}}'
  run _ctx
  [[ $output == *"100k/167k"* ]]
}

@test "modelSettings for another model is ignored" {
  _user_settings '{"autoCompactWindow": 400000, "modelSettings": {"claude-sonnet-5": {"autoCompactWindow": 200000}}}'
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "model id suffixes are stripped for the modelSettings lookup" {
  _user_settings '{"modelSettings": {"claude-opus-5": {"autoCompactWindow": 200000}}}'
  MODEL_ID='claude-opus-5-20260101[1m]' run _ctx
  [[ $output == *"100k/167k"* ]]
}

@test "project settings beats user settings" {
  _user_settings '{"autoCompactWindow": 400000}'
  _settings "$PROJ/.claude/settings.json" '{"autoCompactWindow": 300000}'
  run _ctx
  [[ $output == *"100k/267k"* ]]
}

@test "project settings.local beats project and user settings" {
  _user_settings '{"autoCompactWindow": 400000}'
  _settings "$PROJ/.claude/settings.json" '{"autoCompactWindow": 300000}'
  _settings "$PROJ/.claude/settings.local.json" '{"autoCompactWindow": 200000}'
  run _ctx
  [[ $output == *"100k/167k"* ]]
}

@test "project settings are skipped when the payload has no project dir" {
  mkdir -p "$PROJ"
  _settings "$PROJ/.claude/settings.json" '{"autoCompactWindow": 400000}'
  cd "$PROJ"
  NO_PROJ='' run _ctx
  [[ $output == *"100k/1M"* ]]
}

@test "env window overrides settings" {
  _user_settings '{"autoCompactWindow": 200000}'
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "auto window is ignored" {
  _user_settings '{"autoCompactWindow": "auto"}'
  run _ctx
  [[ $output == *"100k/1M"* ]]
}

@test "project top-level auto is ignored and keeps a user window" {
  _user_settings '{"autoCompactWindow": 400000}'
  _settings "$PROJ/.claude/settings.local.json" '{"autoCompactWindow": "auto"}'
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "project model-level auto clears a user window" {
  _user_settings '{"autoCompactWindow": 400000}'
  _settings "$PROJ/.claude/settings.local.json" '{"modelSettings": {"claude-opus-5": {"autoCompactWindow": "auto"}}}'
  run _ctx
  [[ $output == *"100k/1M"* ]]
}

@test "project number replaces a user per-model auto" {
  _user_settings '{"modelSettings": {"claude-opus-5": {"autoCompactWindow": "auto"}}}'
  _settings "$PROJ/.claude/settings.json" '{"autoCompactWindow": 400000}'
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "project top-level window discards a user per-model window" {
  _user_settings '{"modelSettings": {"claude-opus-5": {"autoCompactWindow": 300000}}}'
  _settings "$PROJ/.claude/settings.json" '{"autoCompactWindow": 500000}'
  run _ctx
  [[ $output == *"100k/467k"* ]]
}

@test "same-layer per-model window beats its own top-level window" {
  _user_settings '{"modelSettings": {"claude-opus-5": {"autoCompactWindow": 300000}}}'
  _settings "$PROJ/.claude/settings.json" '{"autoCompactWindow": 500000, "modelSettings": {"claude-opus-5": {"autoCompactWindow": 200000}}}'
  run _ctx
  [[ $output == *"100k/167k"* ]]
}

@test "project per-model window beats a user top-level window" {
  _user_settings '{"autoCompactWindow": 400000}'
  _settings "$PROJ/.claude/settings.json" '{"modelSettings": {"claude-opus-5": {"autoCompactWindow": 200000}}}'
  run _ctx
  [[ $output == *"100k/167k"* ]]
}

@test "modelSettings keys are normalised like the payload id" {
  local k
  for k in claude-opus-5-20260101 claude-opus-5@20260101 'claude-opus-5[1m]'; do
    _user_settings "{\"modelSettings\": {\"$k\": {\"autoCompactWindow\": 200000}}}"
    run _ctx
    [[ $output == *"100k/167k"* ]]
  done
}

@test "an exact modelSettings key beats other keys that normalise to the model" {
  _user_settings '{"modelSettings": {"claude-opus-5": {"autoCompactWindow": 200000}, "claude-opus-5[1m]": {"autoCompactWindow": 300000}}}'
  run _ctx
  [[ $output == *"100k/167k"* ]]
  _user_settings '{"modelSettings": {"claude-opus-5[1m]": {"autoCompactWindow": 300000}, "claude-opus-5": {"autoCompactWindow": 200000}}}'
  run _ctx
  [[ $output == *"100k/167k"* ]]
}

@test "without an exact key the first normalised modelSettings match wins" {
  _user_settings '{"modelSettings": {"claude-opus-5-20260101": {"autoCompactWindow": 200000}, "claude-opus-5[1m]": {"autoCompactWindow": 300000}}}'
  run _ctx
  [[ $output == *"100k/167k"* ]]
}

@test "@-dated payload id is stripped for the modelSettings lookup" {
  _user_settings '{"modelSettings": {"claude-opus-5": {"autoCompactWindow": 200000}}}'
  MODEL_ID='claude-opus-5@20260101' run _ctx
  [[ $output == *"100k/167k"* ]]
}

@test "model-level auto window replaces the top-level window" {
  _user_settings '{"autoCompactWindow": 400000, "modelSettings": {"claude-opus-5": {"autoCompactWindow": "auto"}}}'
  run _ctx
  [[ $output == *"100k/1M"* ]]
}

@test "pct override caps the trigger on the full window" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=50
  run _ctx
  [[ $output == *"100k/490k"* ]]
}

@test "pct override never exceeds the default trigger" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=100
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000
  run _ctx
  [[ $output == *"100k/367k"* ]]
}

@test "pct override combines with a configured window" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90.7
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000
  run _ctx
  [[ $output == *"100k/344k"* ]]
}

@test "decimal pct override keeps its fraction" {
  export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=0.5
  run _ctx
  [[ $output == *"100k/4k"* ]]
  CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=20.5 run _ctx
  [[ $output == *"100k/200k"* ]]
  CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=20.5004 run _ctx
  [[ $output == *"100k/200k"* ]]
}

@test "invalid pct override is ignored" {
  local v
  for v in 0 0.0 101 100.5 100.0001 150 abc -3 1e2 50abc '1;id'; do
    CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=$v run _ctx
    [ "$status" -eq 0 ]
    [[ $output == *"100k/1M"* ]]
  done
}

@test "DISABLE_AUTO_COMPACT keeps the full window and marks no-ac" {
  export DISABLE_AUTO_COMPACT=1
  run _ctx
  [[ $output == *"100k/1M"* ]]
  [[ $output == *"no-ac"* ]]
}

@test "DISABLE_COMPACT is case-insensitive truthy" {
  export DISABLE_COMPACT=TRUE
  run _ctx
  [[ $output == *"no-ac"* ]]
}

@test "falsy disable env does not mark no-ac" {
  export DISABLE_AUTO_COMPACT=0
  run _ctx
  [[ $output == *"100k/1M"* ]]
  _assert_no_marker
}

@test "disabled auto-compact ignores a configured window" {
  export DISABLE_AUTO_COMPACT=1
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
  run _ctx
  [[ $output == *"100k/1M"* ]]
  [[ $output == *"no-ac"* ]]
}

@test "autoCompactEnabled false in settings marks no-ac" {
  _user_settings '{"autoCompactEnabled": false}'
  run _ctx
  [[ $output == *"100k/1M"* ]]
  [[ $output == *"no-ac"* ]]
}

@test "autoCompactEnabled false in .claude.json marks no-ac" {
  _settings "$CLAUDE_CONFIG_DIR/.claude.json" '{"autoCompactEnabled": false}'
  run _ctx
  [[ $output == *"no-ac"* ]]
}

@test "settings autoCompactEnabled true beats .claude.json false" {
  _user_settings '{"autoCompactEnabled": true}'
  _settings "$CLAUDE_CONFIG_DIR/.claude.json" '{"autoCompactEnabled": false}'
  run _ctx
  _assert_no_marker
}

@test "project settings.local autoCompactEnabled false beats user true" {
  _user_settings '{"autoCompactEnabled": true}'
  _settings "$PROJ/.claude/settings.local.json" '{"autoCompactEnabled": false}'
  run _ctx
  [[ $output == *"no-ac"* ]]
}

@test "malformed settings leave the output unchanged" {
  _user_settings 'not json'
  _settings "$PROJ/.claude/settings.json" '[1]'
  _settings "$PROJ/.claude/settings.local.json" ''
  _settings "$CLAUDE_CONFIG_DIR/.claude.json" '{{'
  run _ctx
  [ "$status" -eq 0 ]
  [[ $output == *"100k/1M"* ]]
  _assert_no_marker
}

@test "colour follows the share of the trigger, not the full window" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000
  run _ctx 30
  [[ $output == *$'\033[1;33m'*"300k/367k"* ]]
  run _ctx 35
  [[ $output == *$'\033[1;31m'*"350k/367k"* ]]
  run _ctx 10
  [[ $output == *$'\033[1;32m'*"100k/367k"* ]]
}

@test "configured used tokens come from the precise percentage" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000
  run _ctx 16.9
  [[ $output == *$'\033[1;31m'*"169k/167k"* ]]
}

@test "unconfigured used tokens still come from the truncated percentage" {
  run _ctx 16.9
  [[ $output == *"160k/1M"* ]]
}

@test "colour without a setting follows the full window" {
  run _ctx 35
  [[ $output == *$'\033[1;32m'*"350k/1M"* ]]
}

@test "missing context size with a configured window does not crash" {
  export CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000
  run _render
  [ "$status" -eq 0 ]
  [[ $output == *"0k/0k"* ]]
}
