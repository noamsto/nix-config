#!/usr/bin/env bats
# Regression suite for aegis-lock-guard (home/desktop/hyprland/scripts).
#
# The guard must lock whenever the session is not already locked, even when an
# aegis-lock client is still running: clients linger after a client-initiated
# unlock, and the old process-name gate then suppressed every later idle lock.
# The dummy client mirrors the real process (Qt-wrapper comm `.quickshell-wra`,
# argv0 `quickshell`, `share/aegis-lock` in argv) so the scan is exercised
# against what production runs. Run this only inside a private PID namespace
# (the Nix check is one): the guard scans and may SIGTERM every matching process.

bats_require_minimum_version 1.5.0

GUARD=${GUARD:?GUARD must name the guard script}

# journalctl -o short-unix lines, as hypridle writes them.
journal_line() {
  printf '%s.000000 host hypridle[123]: [LOG] %s\n' "$1" "$2"
}

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export MARKER="$BATS_TEST_TMPDIR/launched"
  # Absolute shebang: the Nix build sandbox has no /usr/bin/env.
  printf '#!%s\n' "$BASH" >"$BATS_TEST_TMPDIR/bin/systemctl"
  cat >>"$BATS_TEST_TMPDIR/bin/systemctl" <<'STUB'
printf '%s\n' "${STUB_INVOCATION-}"
STUB
  # Real journalctl prints `-- No entries --` (rc 0) for an empty read unless -q.
  printf '#!%s\n' "$BASH" >"$BATS_TEST_TMPDIR/bin/journalctl"
  cat >>"$BATS_TEST_TMPDIR/bin/journalctl" <<'STUB'
if [[ -n ${STUB_JOURNAL-} ]]; then
  printf '%s\n' "$STUB_JOURNAL"
elif [[ " $* " != *" -q "* ]]; then
  echo '-- No entries --'
fi
exit "${STUB_JOURNAL_RC:-0}"
STUB
  printf '#!%s\n' "$BASH" >"$BATS_TEST_TMPDIR/bin/aegis-lock"
  cat >>"$BATS_TEST_TMPDIR/bin/aegis-lock" <<'STUB'
echo LAUNCHED
touch "$MARKER"
STUB
  chmod +x "$BATS_TEST_TMPDIR"/bin/*

  local now
  now=$(date +%s)
  START=$(journal_line $((now - 100)) "Starting hypridle")
  LOCKED="$START"$'\n'$(journal_line $((now - 95)) "Wayland session got locked")
  # The unlock predates every client a test starts.
  UNLOCKED="$LOCKED"$'\n'$(journal_line $((now - 91)) "Wayland session got unlocked")
  NO_ENTRY=$START
  export STUB_INVOCATION=abc123
  export STUB_JOURNAL=$UNLOCKED
  CLIENT_PIDS=()
  DECOY_PID=

  # A zombie has an empty cmdline, as kernel threads do outside the namespace;
  # every case scans past one.
  bash -c 'sleep 0 & exec sleep 300' 3>&- &
  ZOMBIE_PARENT_PID=$!
  wait_for_zombie "$ZOMBIE_PARENT_PID"
}

teardown() {
  local pid
  for pid in "${CLIENT_PIDS[@]}" "$DECOY_PID" "$ZOMBIE_PARENT_PID"; do
    [ -n "$pid" ] || continue
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true
  done
  return 0
}

wait_for_zombie() {
  local _ child
  for _ in $(seq 1 50); do
    for child in $(pgrep -P "$1"); do
      [ "$(cut -d' ' -f3 "/proc/$child/stat")" = Z ] && [ ! -s "/proc/$child/cmdline" ] && return 0
    done
    sleep 0.1
  done
  return 1
}

start_client() {
  [ -e "$BATS_TEST_TMPDIR/.quickshell-wrapped" ] || cp "$(command -v bash)" "$BATS_TEST_TMPDIR/.quickshell-wrapped"
  (exec -a /fake/bin/quickshell "$BATS_TEST_TMPDIR/.quickshell-wrapped" \
    -c 'sleep 300; :' x -p /fake/share/aegis-lock) 3>&- &
  CLIENT_PID=$!
  CLIENT_PIDS+=("$CLIENT_PID")
  wait_for_cmdline "$CLIENT_PID" quickshell
}

start_decoy() {
  bash -c 'sleep 300; : share/aegis-lock' 3>&- &
  DECOY_PID=$!
  wait_for_cmdline "$DECOY_PID" share/aegis-lock
}

# Block until the forked child has exec'd, so the guard never scans a half-started process.
wait_for_cmdline() {
  local _
  for _ in $(seq 1 50); do
    tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null | grep -q -- "$2" && return 0
    sleep 0.1
  done
  return 1
}

is_alive() {
  kill -0 "$1" 2>/dev/null || return 1
  local state
  state=$(cut -d' ' -f3 "/proc/$1/stat" 2>/dev/null) || return 1
  [ "$state" != Z ]
}

# `wait` reaps the child (a zombie still answers kill -0); poll first so a
# surviving client fails the assertion instead of blocking on `wait`.
assert_killed() {
  local _ rc=0
  for _ in $(seq 1 50); do
    is_alive "$1" || break
    sleep 0.1
  done
  if is_alive "$1"; then
    echo "pid $1 still alive" >&2
    return 1
  fi
  wait "$1" || rc=$?
  [ "$rc" -eq 143 ]
}

assert_alive() {
  is_alive "$1"
}

@test "unlocked with a stale client: kills it and launches a new lock" {
  start_client
  AEGIS_LOCK_FRESH_SECS=0 run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *LAUNCHED* ]]
  assert_killed "$CLIENT_PID"
}

@test "locked with a stale client: touches nothing" {
  start_client
  STUB_JOURNAL=$LOCKED AEGIS_LOCK_FRESH_SECS=0 run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" != *LAUNCHED* ]]
  [ ! -e "$MARKER" ]
  assert_alive "$CLIENT_PID"
}

@test "unlocked with a fresh client: lock is being acquired, leaves it" {
  start_client
  run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" != *LAUNCHED* ]]
  [ ! -e "$MARKER" ]
  assert_alive "$CLIENT_PID"
}

@test "unlocked with no client: launches" {
  run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *LAUNCHED* ]]
  [ -e "$MARKER" ]
}

@test "no lock entry in the invocation with a stale client: unlocked, launches" {
  start_client
  STUB_JOURNAL=$NO_ENTRY AEGIS_LOCK_FRESH_SECS=0 run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *LAUNCHED* ]]
  assert_killed "$CLIENT_PID"
}

@test "no hypridle invocation (unknown) with a client: leaves it, no launch" {
  start_client
  STUB_INVOCATION='' AEGIS_LOCK_FRESH_SECS=0 run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" != *LAUNCHED* ]]
  [ ! -e "$MARKER" ]
  assert_alive "$CLIENT_PID"
}

@test "no hypridle invocation (unknown) with no client: launches" {
  STUB_INVOCATION='' run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *LAUNCHED* ]]
  [ -e "$MARKER" ]
}

@test "a shell that merely mentions share/aegis-lock is not a client" {
  start_decoy
  AEGIS_LOCK_FRESH_SECS=0 run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *LAUNCHED* ]]
  assert_alive "$DECOY_PID"
}

@test "unlocked after a fresh client started: the unlock makes it stale, replaces it" {
  start_client
  sleep 2
  STUB_JOURNAL="$LOCKED"$'\n'$(journal_line "$(date +%s)" "Wayland session got unlocked") run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *LAUNCHED* ]]
  assert_killed "$CLIENT_PID"
}

@test "empty journal read (unknown) with a stale client: leaves it, no launch" {
  start_client
  STUB_JOURNAL='' AEGIS_LOCK_FRESH_SECS=0 run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" != *LAUNCHED* ]]
  [ ! -e "$MARKER" ]
  assert_alive "$CLIENT_PID"
}

@test "failed journal read (unknown) with a stale client: leaves it, no launch" {
  start_client
  STUB_JOURNAL_RC=1 AEGIS_LOCK_FRESH_SECS=0 run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" != *LAUNCHED* ]]
  [ ! -e "$MARKER" ]
  assert_alive "$CLIENT_PID"
}

@test "unlocked with a stale and a fresh client: leaves both, no launch" {
  start_client
  local old=$CLIENT_PID
  sleep 2.5
  start_client
  AEGIS_LOCK_FRESH_SECS=2 run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" != *LAUNCHED* ]]
  [ ! -e "$MARKER" ]
  assert_alive "$old"
  assert_alive "$CLIENT_PID"
}

@test "unlocked with two stale clients: kills both and launches" {
  start_client
  local first=$CLIENT_PID
  start_client
  AEGIS_LOCK_FRESH_SECS=0 run bash "$GUARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *LAUNCHED* ]]
  assert_killed "$first"
  assert_killed "$CLIENT_PID"
}
