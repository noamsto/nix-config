#!/usr/bin/env bats
# Regression suite for xresources-apply (home/desktop/hyprland/scripts).
#
# Runs a real Xvfb server and a real xrdb, so the assertions run against the
# same kind of fresh X resource database a restarted XWayland presents — the
# state in which a docked session was left on the laptop DPI. The first test
# pins the legacy loader's behaviour (a static merge ignores the active
# profile) so the suite fails if the fix ever regresses back to it.

bats_require_minimum_version 1.5.0

SCRIPT=${XRAPPLY:?XRAPPLY must name the xresources-apply script}

setup_file() {
  # -noreset is load-bearing: without it the X server resets and wipes the
  # resource database when the last client (each xrdb invocation) disconnects.
  XVFB_DISPLAY=":$((RANDOM % 1000 + 100))"
  export XVFB_DISPLAY
  Xvfb "$XVFB_DISPLAY" -screen 0 1024x768x24 -noreset \
    >"$BATS_FILE_TMPDIR/xvfb.log" 2>&1 &
  XVFB_PID=$!
  export XVFB_PID
  for _ in $(seq 1 40); do
    [ -S "/tmp/.X11-unix/X${XVFB_DISPLAY#:}" ] && break
    sleep 0.25
  done
  if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    cat "$BATS_FILE_TMPDIR/xvfb.log" >&2
    return 1
  fi
}

teardown_file() {
  kill "$XVFB_PID" 2>/dev/null || true
}

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  printf 'Xft.dpi: 111\n' >"$HOME/.Xresources"
  printf 'Xft.dpi: 96\n' >"$HOME/.Xresources.docked"
  printf 'Xft.dpi: 192\n' >"$HOME/.Xresources.laptop"
  export XDG_STATE_HOME="$HOME/.local/state"
  export DISPLAY="$XVFB_DISPLAY"
}

state_file() {
  printf '%s\n' "$XDG_STATE_HOME/hyprland/monitor-profile"
}

dpi() {
  xrdb -nocpp -query | sed -n 's/^Xft\.dpi:[[:space:]]*//p'
}

@test "legacy static merge leaves a docked server on the laptop DPI (red)" {
  xrdb -nocpp -merge "$HOME/.Xresources"
  [ "$(dpi)" = 111 ]
}

@test "docked profile applies 96 to a fresh server and is recorded" {
  run bash "$SCRIPT" docked
  [ "$status" -eq 0 ]
  [ "$(dpi)" = 96 ]
  [ "$(cat "$(state_file)")" = docked ]
}

@test "no-argument replay applies the recorded docked profile" {
  bash "$SCRIPT" docked
  bash "$SCRIPT"
  [ "$(dpi)" = 96 ]
}

@test "undocked profile applies the laptop DPI" {
  bash "$SCRIPT" undocked
  [ "$(dpi)" = 192 ]
}

@test "no recorded profile falls back to the historical default" {
  bash "$SCRIPT"
  [ "$(dpi)" = 111 ]
}

@test "unknown recorded profile falls back to the laptop DPI" {
  bash "$SCRIPT" undocked
  printf 'garbage\n' >"$(state_file)"
  bash "$SCRIPT"
  [ "$(dpi)" = 192 ]
}
