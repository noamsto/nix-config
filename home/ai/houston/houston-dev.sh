# shellcheck shell=bash
: "${pinned:?}"
: "${pinned_rev:?}" "${dev_dir:?}"

usage() {
  echo "usage: houston-dev on|off|status|sync" >&2
}

cmd=${1:-}
[[ -n $cmd ]] || {
  usage
  exit 2
}

case "$cmd" in
on)
  mkdir -p "$dev_dir"
  # Forces a redeploy + restart even if a sync racing a past `off` left sha behind.
  rm -f "$dev_dir/sha"
  touch "$dev_dir/enabled"
  systemctl --user start --no-block houston-dev-sync.service
  echo "houston dev mode on; following main. Watch: journalctl --user -u houston-dev-sync -f"
  ;;

off)
  if dispatch_busy; then
    waited=0
    while dispatch_busy && [[ $waited -lt 30 ]]; do
      [[ $waited -eq 0 ]] && echo "waiting for in-flight dispatch…" >&2
      sleep 5
      waited=$((waited + 1))
    done
    if dispatch_busy; then
      echo "dispatch still running; dev mode left on — try again" >&2
      exit 1
    fi
  fi
  rm -f "$dev_dir/enabled" "$dev_dir/current" "$dev_dir/sha" "$dev_dir/next" \
    "$dev_dir/next-sha" "$dev_dir/failed"
  if ! systemctl --user try-restart houston.service; then
    echo "dev mode off, but restarting houston failed; it runs pinned $pinned_rev once restarted" >&2
    exit 1
  fi
  echo "houston dev mode off; houston runs pinned $pinned_rev"
  ;;

status)
  if [[ -e "$dev_dir/enabled" ]]; then
    echo "mode: on"
  else
    echo "mode: off"
  fi

  if [[ -e "$dev_dir/sha" ]]; then
    echo "deployed: $(<"$dev_dir/sha")"
  else
    echo "deployed: none"
  fi

  [[ -e "$dev_dir/next-sha" ]] && echo "staged: $(<"$dev_dir/next-sha")"
  [[ -e "$dev_dir/failed" ]] && echo "failed: $(<"$dev_dir/failed")"

  main_sha=$(main_head 10 2>/dev/null) &&
    main_sha=${main_sha%%[[:space:]]*}
  echo "main: ${main_sha:-unknown}"
  echo "pinned: $pinned_rev"

  pid=$(systemctl --user show -p MainPID --value houston.service 2>/dev/null) || pid=""
  if [[ -z $pid || $pid == 0 ]]; then
    echo "running: stopped"
  else
    exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null) || exe="unknown"
    store=${exe#/nix/store/}
    store=/nix/store/${store%%/*}
    if [[ -e "$dev_dir/current" && $store == "$(readlink -f "$dev_dir/current")" ]]; then
      echo "running: dev $(<"$dev_dir/sha")"
    elif [[ $store == "$pinned" ]]; then
      echo "running: pinned"
    else
      echo "running: other ($exe)"
    fi
  fi

  if [[ -e "$dev_dir/last-sync" ]]; then
    echo "last sync: $(<"$dev_dir/last-sync")"
  else
    echo "last sync: never"
  fi
  ;;

sync)
  rm -f "$dev_dir/failed"
  rc=0
  systemctl --user start houston-dev-sync.service || rc=$?
  [[ -e "$dev_dir/last-sync" ]] && cat "$dev_dir/last-sync"
  exit "$rc"
  ;;

*)
  usage
  exit 2
  ;;
esac
