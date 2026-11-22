#!/usr/bin/env bats
# Regression suite for hyprmoncfg-post-apply: picks the xresources profile from
# the connected monitors and dispatches xresources-apply through Hyprland.

bats_require_minimum_version 1.5.0

POST_APPLY=${POST_APPLY:?POST_APPLY must name the script}

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export HYPRCTL_LOG="$BATS_TEST_TMPDIR/hyprctl.log"
  : >"$HYPRCTL_LOG"
  # Absolute shebang: the Nix build sandbox has no /usr/bin/env.
  printf '#!%s\n' "$BASH" >"$BATS_TEST_TMPDIR/bin/hyprctl"
  cat >>"$BATS_TEST_TMPDIR/bin/hyprctl" <<'STUB'
if [[ $* == "monitors -j" ]]; then
  printf '%s\n' "$MONITORS_JSON"
  exit "${MONITORS_RC:-0}"
fi
echo "$*" >>"$HYPRCTL_LOG"
STUB
  chmod +x "$BATS_TEST_TMPDIR"/bin/*
}

@test "laptop panel only: applies the laptop profile" {
  export MONITORS_JSON='[{"name":"eDP-1"}]'
  run bash "$POST_APPLY"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$HYPRCTL_LOG")" -eq 1 ]
  grep -Eq '^dispatch hl\.dsp\.exec_cmd\(".*/bin/xresources-apply laptop"\)$' "$HYPRCTL_LOG"
}

@test "laptop panel plus external: applies the docked profile" {
  export MONITORS_JSON='[{"name":"eDP-1"},{"name":"DP-7"}]'
  run bash "$POST_APPLY"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$HYPRCTL_LOG")" -eq 1 ]
  grep -Eq '^dispatch hl\.dsp\.exec_cmd\(".*/bin/xresources-apply docked"\)$' "$HYPRCTL_LOG"
}

@test "externals only (lid closed): applies the docked profile" {
  export MONITORS_JSON='[{"name":"DP-7"},{"name":"DP-8"}]'
  run bash "$POST_APPLY"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$HYPRCTL_LOG")" -eq 1 ]
  grep -Eq '^dispatch hl\.dsp\.exec_cmd\(".*/bin/xresources-apply docked"\)$' "$HYPRCTL_LOG"
}

@test "hyprctl monitors failing: exits non-zero and dispatches nothing" {
  export MONITORS_JSON=''
  export MONITORS_RC=1
  run bash "$POST_APPLY"
  [ "$status" -ne 0 ]
  [ ! -s "$HYPRCTL_LOG" ]
}
