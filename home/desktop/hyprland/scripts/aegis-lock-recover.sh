#!/usr/bin/env bash
# Rebind a lock client to a session lock whose client died.
#
# When an ext-session-lock client dies without unlocking, the compositor is
# required to stay locked - leaving a lock surface with nothing behind it to
# authenticate against. Spawning a fresh client takes over the orphaned lock
# (needs misc:allow_session_lock_restore). Run from a TTY: Ctrl+Alt+F2.

set -euo pipefail

UNIT="aegis-lock-recover"

usage() {
  cat <<'EOF'
Usage: aegis-lock-recover [--status] [--force]

  --status  Report lock state and exit.
  --force   Spawn a lock client even when the session reads as unlocked.
EOF
}

# hypridle follows ext-session-lock via the lock-notify protocol, so its journal
# is the compositor's view. logind's LockedHint is not: it stays "no" for a
# compositor-side lock.
lock_state() {
  local last
  last=$(journalctl --user -u hypridle --no-pager 2>/dev/null |
    grep -oE "Wayland session got (locked|unlocked)" |
    tail -1)

  case "$last" in
  *"got locked") echo locked ;;
  *"got unlocked") echo unlocked ;;
  *) echo unknown ;;
  esac
}

# Matched by executable name, not `pgrep -f`: an -f pattern also matches any
# shell whose command line merely mentions it, this script's own caller included.
lock_client_pids() {
  local pid pids=()
  while read -r pid; do
    if tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q "share/aegis-lock"; then
      pids+=("$pid")
    fi
  done < <(pgrep -x quickshell || true)
  echo "${pids[*]}"
}

hypr_vt() {
  local session
  for session in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
    if [[ $(loginctl show-session "$session" -p Type --value) == wayland ]]; then
      loginctl show-session "$session" -p TTY --value
      return
    fi
  done
}

force=false
case "${1:-}" in
--status)
  status_clients=$(lock_client_pids)
  status_vt=$(hypr_vt)
  echo "lock state:   $(lock_state)"
  echo "lock clients: ${status_clients:-none}"
  echo "hyprland vt:  ${status_vt:-unknown}"
  exit 0
  ;;
--force) force=true ;;
-h | --help)
  usage
  exit 0
  ;;
"") ;;
*)
  usage
  exit 1
  ;;
esac

state=$(lock_state)
if [[ $state != locked && $force == false ]]; then
  echo "Session reads as '$state' - nothing to recover."
  echo "Spawning a client now would LOCK the session. Pass --force to do that deliberately."
  exit 1
fi

clients=$(lock_client_pids)
if [[ -n $clients ]]; then
  echo "A lock client is already running (pid: $clients)."
  echo "Switch to $(hypr_vt) and authenticate there."
  exit 0
fi

systemctl --user reset-failed "$UNIT" 2>/dev/null || true
systemd-run --user --collect --unit="$UNIT" aegis-lock

echo "Lock client spawned. Switch to $(hypr_vt) and authenticate."
