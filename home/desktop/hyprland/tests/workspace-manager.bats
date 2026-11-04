#!/usr/bin/env bats
# Regression suite for workspace-manager (home/desktop/hyprland/services).
#
# The noctalia lookup is diagnostic only: when noctalia is not running (it dies
# on resume), pgrep exits 1 and, under errexit plus pipefail, used to abort the
# script before the `hyprctl reload` that restores the laptop panel. The real
# pgrep runs here and no noctalia exists, which is that condition.

bats_require_minimum_version 1.5.0

WORKSPACE_MANAGER=${WORKSPACE_MANAGER:?WORKSPACE_MANAGER must name the script}

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export HYPRCTL_LOG="$BATS_TEST_TMPDIR/hyprctl.log"
  # Absolute shebang: the Nix build sandbox has no /usr/bin/env.
  printf '#!%s\n' "$BASH" >"$BATS_TEST_TMPDIR/bin/hyprctl"
  cat >>"$BATS_TEST_TMPDIR/bin/hyprctl" <<'STUB'
echo "$*" >>"$HYPRCTL_LOG"
if [[ $* == "monitors -j" ]]; then
  echo '[{"name":"eDP-1","disabled":false}]'
elif [[ $* == monitors ]]; then
  echo 'Monitor eDP-1 (ID 0)'
else
  echo ok
fi
STUB
  chmod +x "$BATS_TEST_TMPDIR"/bin/*
}

@test "undocked with noctalia not running: exits 0 and reloads Hyprland" {
  run bash "$WORKSPACE_MANAGER" undocked
  [ "$status" -eq 0 ]
  grep -qx reload "$HYPRCTL_LOG"
}

@test "undocked with noctalia not running: logs the warning" {
  run bash "$WORKSPACE_MANAGER" undocked
  [ "$status" -eq 0 ]
  grep -q 'WARNING: Noctalia NOT running' /tmp/workspace-manager.log
}
