# shellcheck shell=bash
# Lock-state helpers shared by aegis-lock-guard and aegis-lock-recover. Prepended
# to each script at build time, so this file only defines functions.

# hypridle follows ext-session-lock via the lock-notify protocol, so its journal
# is the compositor's view. logind's LockedHint is not: it stays "no" for a
# compositor-side lock. Scoped to the running hypridle: an earlier invocation's
# last word belongs to a session that no longer exists.
#
# Prints the invocation's lock events (`-o short-unix`, epoch first), matched on
# hypridle's own line format so child output in the same stream cannot forge
# one. Fails on a missing invocation or a failed or empty read; -q matters,
# since without it an empty read prints `-- No entries --` and exits 0.
hypridle_lock_events() {
  local invocation journal
  invocation=$(systemctl --user show -p InvocationID --value hypridle)
  [[ -n $invocation ]] || return 1
  journal=$(journalctl --user -q -o short-unix "_SYSTEMD_INVOCATION_ID=$invocation" --no-pager 2>/dev/null) || return 1
  [[ -n $journal ]] || return 1
  grep -E 'hypridle\[[0-9]+\]: \[LOG\] Wayland session got (locked|unlocked)$' <<<"$journal" || true
}

# Hyprland sends `locked` to a newly bound hypridle right away when the session
# is already locked, so within one invocation no lock entry means it was never
# locked. An unreadable journal stays `unknown` so it can never authorise a kill.
lock_state() {
  local events
  events=$(hypridle_lock_events) || {
    echo unknown
    return
  }
  case "$(tail -1 <<<"$events")" in
  *"got locked") echo locked ;;
  *) echo unlocked ;;
  esac
}

# Epoch seconds of the invocation's last unlock; empty when there is none.
last_unlock_epoch() {
  local line
  line=$(hypridle_lock_events | grep ' got unlocked$' | tail -1) || true
  echo "${line%%.*}"
}

# Clients run through the Nix Qt wrapper, so their comm is `.quickshell-wra`;
# match on argv instead. Requiring argv[0] to be quickshell/qs excludes shells
# that merely mention the path, this function's own caller included.
lock_client_pids() {
  local cmdline arg pid pids=()
  local -a argv
  for cmdline in /proc/[0-9]*/cmdline; do
    mapfile -d '' -t argv <"$cmdline" 2>/dev/null || continue
    # Kernel threads and zombies have an empty cmdline.
    ((${#argv[@]})) || continue
    case "${argv[0]##*/}" in
    quickshell | qs) ;;
    *) continue ;;
    esac
    for arg in "${argv[@]}"; do
      if [[ $arg == *share/aegis-lock ]]; then
        pid=${cmdline#/proc/}
        pids+=("${pid%/cmdline}")
        break
      fi
    done
  done
  echo "${pids[*]}"
}

# Fails for a pid that has exited, so a vanished client never counts as fresh.
lock_client_age() {
  local age
  age=$(ps -o etimes= -p "$1") || return 1
  age=${age// /}
  [[ -n $age ]] || return 1
  echo "$age"
}
