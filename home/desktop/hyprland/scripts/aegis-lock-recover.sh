#!/usr/bin/env bash
# Rebind a lock client to a session lock whose client died or hung.
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
# compositor-side lock. Scoped to the running hypridle: an earlier invocation's
# last word belongs to a session that no longer exists.
lock_state() {
  local invocation last
  invocation=$(systemctl --user show -p InvocationID --value hypridle)
  [[ -n $invocation ]] || {
    echo unknown
    return
  }
  last=$(journalctl --user "_SYSTEMD_INVOCATION_ID=$invocation" --no-pager 2>/dev/null |
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
  done < <(pgrep -x 'qs|quickshell' || true)
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

# A client that still holds the lock but cannot be unlocked from the VT is hung:
# it can stall after queueing unlock_and_destroy but before flushing it (seen
# when an output appears mid-unlock). SIGABRT leaves a coredump with its stacks
# for `coredumpctl info qs`, and its death orphans the lock for the new client.
clients=$(lock_client_pids)
if [[ -n $clients ]]; then
  echo "Aborting stuck lock client (pid: $clients); coredump: coredumpctl info qs"
  # shellcheck disable=SC2086 # one word per pid
  kill -ABRT $clients
  for _ in $(seq 50); do
    [[ -z $(lock_client_pids) ]] && break
    sleep 0.1
  done
  if [[ -n $(lock_client_pids) ]]; then
    echo "Lock client still alive after SIGABRT; not spawning a second one." >&2
    exit 1
  fi
fi

systemctl --user reset-failed "$UNIT" 2>/dev/null || true
systemd-run --user --collect --unit="$UNIT" aegis-lock

echo "Lock client spawned. Switch to $(hypr_vt) and authenticate."
