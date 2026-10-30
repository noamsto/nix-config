#!/usr/bin/env bash
# Entry point for every lock trigger.
#
# Lock clients linger after an unlock (quickshell 0.3.2 never emits
# WlSessionLock's lockStateChanged on a client-initiated unlock, so aegis-lock's
# quit handler never runs), so a live client does not mean a locked session.
# Lock whenever the session is not locked, replacing stale clients. A lid-close
# delivers two lock_cmd runs ~1 s apart and Hyprland only reports `locked` once
# the lock is confirmed, so a fresh client is still acquiring it: leave it. A
# client is fresh only if it is young and started after the last unlock; a
# young one that predates it (lock, fingerprint unlock, lid close) is stale.
# Clients are killed only when the state reads unlocked; if that read were ever
# wrong, misc:allow_session_lock_restore lets the new client take over the lock.

set -euo pipefail

fresh_secs=${AEGIS_LOCK_FRESH_SECS:-10}

state=$(lock_state)
clients=$(lock_client_pids)

if [[ $state == locked ]]; then
  exit 0
fi

if [[ -n $clients ]]; then
  # Without a trustworthy state a live client may be the one holding the lock.
  [[ $state == unlocked ]] || exit 0
  unlocked_at=$(last_unlock_epoch)
  now=$(date +%s)
  for pid in $clients; do
    age=$(lock_client_age "$pid") || continue
    ((age < fresh_secs)) || continue
    if [[ -z $unlocked_at ]] || ((now - age > unlocked_at)); then
      exit 0
    fi
  done
  # shellcheck disable=SC2086 # one word per pid
  kill -TERM $clients 2>/dev/null || true
fi

exec aegis-lock
