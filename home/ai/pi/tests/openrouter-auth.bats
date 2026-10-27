#!/usr/bin/env bats
# Regression suite for openrouter-auth.sh: upserts pi's openrouter auth.json
# entry as a `!cat '<keyfile>'` command so the key itself never lands in the
# file. Run directly (GNU stat is required; on macOS add coreutils):
#   nix shell nixpkgs#bats nixpkgs#jq nixpkgs#coreutils -c bats home/ai/pi/tests/openrouter-auth.bats
# or: nix build .#checks.x86_64-linux.pi-openrouter-auth

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT=${SCRIPT:-$BATS_TEST_DIRNAME/../openrouter-auth.sh}
  mkdir -p "$BATS_TEST_TMPDIR/secret"
  keyfile="$BATS_TEST_TMPDIR/secret/key"
  printf '%s\n' 'sk-or-DUMMY-NEVER-IN-AUTH' >"$keyfile"
  auth="$BATS_TEST_TMPDIR/pi/agent/auth.json"
}

# A helper left frozen by a failed assertion would hold bats open forever.
teardown() {
  [ -z "${pid:-}" ] || kill -CONT "$pid" 2>/dev/null || true
}

upsert() {
  run --separate-stderr bash "$SCRIPT" "$keyfile" "$1"
}

assert_no_key() {
  ! grep -qF 'sk-or-DUMMY-NEVER-IN-AUTH' "$1"
}

seed() {
  mkdir -p "$(dirname "$auth")"
  cat >"$auth" <<'EOF'
{
  "anthropic": {"type": "api_key", "key": "sk-ant-dummy"},
  "github-copilot": {"type": "oauth", "access": "gh-a", "refresh": "gh-r", "expires": 1}
}
EOF
}

@test "creates a missing auth.json with mode 600 and the cat entry" {
  upsert "$auth"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$auth")" = 600 ]
  run jq -c .openrouter "$auth"
  [ "$output" = "{\"type\":\"api_key\",\"key\":\"!cat '$keyfile'\"}" ]
  assert_no_key "$auth"
  [ ! -e "$auth.lock" ]
}

@test "preserves other providers" {
  seed
  upsert "$auth"
  [ "$status" -eq 0 ]
  run jq -c '.anthropic, ."github-copilot"' "$auth"
  [ "${lines[0]}" = '{"type":"api_key","key":"sk-ant-dummy"}' ]
  [ "${lines[1]}" = '{"type":"oauth","access":"gh-a","refresh":"gh-r","expires":1}' ]
  assert_no_key "$auth"
}

@test "replaces an existing oauth openrouter entry" {
  mkdir -p "$(dirname "$auth")"
  echo '{"openrouter":{"type":"oauth","access":"a","refresh":"r","expires":1}}' >"$auth"
  upsert "$auth"
  [ "$status" -eq 0 ]
  run jq -c '.openrouter | keys' "$auth"
  [ "$output" = '["key","type"]' ]
  assert_no_key "$auth"
}

@test "second run leaves identical bytes" {
  seed
  upsert "$auth"
  cp "$auth" "$BATS_TEST_TMPDIR/first"
  upsert "$auth"
  [ "$status" -eq 0 ]
  cmp "$auth" "$BATS_TEST_TMPDIR/first"
  assert_no_key "$auth"
}

@test "writes through a symlinked auth.json" {
  seed
  link="$BATS_TEST_TMPDIR/pi/worker/auth.json"
  mkdir -p "$(dirname "$link")"
  ln -s "$auth" "$link"
  upsert "$link"
  [ "$status" -eq 0 ]
  [ -L "$link" ]
  [ "$(readlink "$link")" = "$auth" ]
  run jq -r .openrouter.type "$auth"
  [ "$output" = api_key ]
  assert_no_key "$auth"
  [ ! -e "$link.lock" ]
  [ ! -e "$auth.lock" ]
}

@test "malformed JSON fails and leaves the file untouched" {
  mkdir -p "$(dirname "$auth")"
  echo '{not json' >"$auth"
  upsert "$auth"
  [ "$status" -ne 0 ]
  [ "$(cat "$auth")" = '{not json' ]
  run ls -A "$(dirname "$auth")"
  [ "$output" = auth.json ]
}

@test "an empty auth.json gets the entry with mode 600" {
  mkdir -p "$(dirname "$auth")"
  : >"$auth"
  upsert "$auth"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$auth")" = 600 ]
  run jq -r .openrouter.type "$auth"
  [ "$output" = api_key ]
}

@test "multiple JSON documents fail and leave the file untouched" {
  mkdir -p "$(dirname "$auth")"
  printf '%s' '{"a":1}{"b":2}' >"$auth"
  upsert "$auth"
  [ "$status" -ne 0 ]
  [ "$(cat "$auth")" = '{"a":1}{"b":2}' ]
  run ls -A "$(dirname "$auth")"
  [ "$output" = auth.json ]
}

@test "waits for a held lock, then proceeds and releases it" {
  seed
  mkdir "$auth.lock"
  (sleep 0.3; printf '{"marker":1}' >"$auth"; rmdir "$auth.lock") &
  upsert "$auth"
  wait
  [ "$status" -eq 0 ]
  [ ! -e "$auth.lock" ]
  run jq -c '[.marker, .openrouter.type]' "$auth"
  [ "$output" = '[1,"api_key"]' ]
}

@test "waits for a lock held on the symlink path" {
  seed
  link="$BATS_TEST_TMPDIR/pi/worker/auth.json"
  mkdir -p "$(dirname "$link")"
  ln -s "$auth" "$link"
  mkdir "$link.lock"
  (sleep 0.3; printf '{"marker":1}' >"$link"; rmdir "$link.lock") &
  upsert "$link"
  wait
  [ "$status" -eq 0 ]
  run jq -c '[.marker, .openrouter.type]' "$auth"
  [ "$output" = '[1,"api_key"]' ]
  [ ! -e "$link.lock" ]
  [ ! -e "$auth.lock" ]
}

@test "times out on a fresh lock without removing it" {
  seed
  cp "$auth" "$BATS_TEST_TMPDIR/before"
  mkdir "$auth.lock"
  upsert "$auth"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"$auth.lock"* ]]
  [ -d "$auth.lock" ]
  cmp "$auth" "$BATS_TEST_TMPDIR/before"
}

@test "reclaims a stale lock" {
  seed
  mkdir "$auth.lock"
  touch -d "@$(($(date +%s) - 120))" "$auth.lock"
  upsert "$auth"
  [ "$status" -eq 0 ]
  run jq -r .openrouter.type "$auth"
  [ "$output" = api_key ]
  [ ! -e "$auth.lock" ]
}

@test "keeps the as-given lock fresh while waiting on the resolved one" {
  seed
  link="$BATS_TEST_TMPDIR/pi/worker/auth.json"
  mkdir -p "$(dirname "$link")"
  ln -s "$auth" "$link"
  mkdir "$auth.lock"
  bash "$SCRIPT" "$keyfile" "$link" 2>/dev/null &
  pid=$!
  max=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ -d "$link.lock" ]; then
      mtime=$(stat -c %.3Y "$link.lock" 2>/dev/null) || continue
      age=$(($(date +%s%3N) - ${mtime/./}))
      [ "$age" -le "$max" ] || max=$age
      if [ "$age" -ge 10000 ]; then
        rmdir "$link.lock"
        mkdir "$link.lock"
      fi
    fi
    sleep 0.05
  done
  status=0
  wait "$pid" || status=$?
  [ "$status" -ne 0 ]
  [ "$max" -lt 10000 ]
  [ -d "$auth.lock" ]
}

@test "leaves a lock pi reclaimed from it in place" {
  seed
  link="$BATS_TEST_TMPDIR/pi/worker/auth.json"
  mkdir -p "$(dirname "$link")"
  ln -s "$auth" "$link"
  mkdir "$auth.lock"
  bash "$SCRIPT" "$keyfile" "$link" 2>/dev/null &
  pid=$!
  until [ -d "$link.lock" ]; do
    kill -0 "$pid"
    sleep 0.01
  done
  # Swap only while the helper is frozen inside its 0.1s wait `sleep`, so the swap can't land mid-refresh().
  until kill -STOP "$pid" && ps -A -o ppid=,args= | grep -qE "^ *$pid sleep 0\.1\$"; do
    kill -CONT "$pid"
    kill -0 "$pid"
    sleep 0.01
  done
  rmdir "$link.lock"
  mkdir "$link.lock"
  kill -CONT "$pid"
  status=0
  wait "$pid" || status=$?
  [ "$status" -ne 0 ]
  [ -d "$link.lock" ]
  [ -d "$auth.lock" ]
}

@test "tightens a world-readable file to 600" {
  seed
  chmod 644 "$auth"
  upsert "$auth"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$auth")" = 600 ]
}

@test "wrong argument count prints usage and exits 2" {
  run --separate-stderr bash "$SCRIPT" "$keyfile"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *usage:* ]]
}
