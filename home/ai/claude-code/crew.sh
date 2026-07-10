# shellcheck shell=bash
# File-based coordination bus: id | identity | status | msg | watch | roster | inbox | log
# A real CLI on PATH (not a fish fn) so BOTH the dispatcher (fish) and workers
# (their bash tool) can call it. Pure jq + append; the log is the state. The
# shebang + `set -euo pipefail` are prepended by writeShellApplication, so this
# source omits them (the shell= directive above keeps standalone shellcheck happy).

# Index-aligned codename pool (FleetView-style). identity is deterministic over
# the branch, so any caller recomputes the same name/color — never stored.
# _tmuxc are mid-tone 256-palette codes chosen for legibility on BOTH Catppuccin
# Latte (light) and Mocha (dark): each clears ~2.5:1 contrast (most >3:1) on
# either base, so the badge lazytmux tints doesn't wash out when the theme flips.
# The old bright/pale set (colour44/141/220/154/117…) was dark-mode-only.
_names=(sage atlas nova ember reef iris amber coral moss slate rust plum lime rose sky onyx)
_colors=(green blue magenta orange teal purple yellow salmon olive steel rust plum lime pink sky grey)
_tmuxc=(colour28 colour32 colour127 colour130 colour30 colour98 colour136 colour167 colour100 colour67 colour166 colour96 colour64 colour162 colour25 colour244)

_identity() { # $1=branch -> {name,color,tmux}; cksum is POSIX (portable to macOS)
  local n i
  n=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  i=$((n % ${#_names[@]}))
  jq -nc --arg name "${_names[$i]}" --arg color "${_colors[$i]}" --arg tmux "${_tmuxc[$i]}" \
    '{name:$name, color:$color, tmux:$tmux}'
}

# _lock_acquire <lockdir> <owner_pid> — atomic mkdir gate with dead-PID reclaim.
# mkdir is atomic on POSIX, so it is the ONLY gate: exactly one caller wins.
# Returns 0 (acquired; owner_pid written inside for liveness) or 1 (held by a
# DIFFERENT live PID, or lost the reclaim race). If the held owner equals the
# requested owner, returns 0 idempotently — re-running /dispatcher in the same
# session (same session-stable PID) is a no-op success, not a refusal. rm -rf
# here is safe — the lock dir is transient coordination state, never user data.
_lock_acquire() {
  local ld="$1" owner="$2" held
  if mkdir "$ld" 2>/dev/null; then
    printf '%s\n' "$owner" >"$ld/pid"
    return 0
  fi
  held=$(cat "$ld/pid" 2>/dev/null || true)
  if [ "$held" = "$owner" ]; then
    return 0 # idempotent: this same owner already holds it
  fi
  if [ -n "$held" ] && kill -0 "$held" 2>/dev/null; then
    return 1
  fi
  rm -rf "$ld" # stale (owner PID dead/empty) — reclaim through the same mkdir gate
  if mkdir "$ld" 2>/dev/null; then
    printf '%s\n' "$owner" >"$ld/pid"
    return 0
  fi
  return 1
}

_lock_release() { rm -rf "$1"; }

# Resolve the crew id: env wins; else read it from WORKER_TASK.md at the repo
# root, so a worker just calls `crew status …` with no env prefix to remember.
_crew_id() {
  if [ -n "${CREW_ID:-}" ]; then
    printf '%s' "$CREW_ID"
    return 0
  fi
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$top" ] && [ -f "$top/WORKER_TASK.md" ]; then
    grep -m1 '^crew_id:' "$top/WORKER_TASK.md" | cut -d' ' -f2 || true
  fi
}

sub="${1:-}"
shift || true

# `id` and `identity` need no repo / no crew id.
if [ "$sub" = id ]; then
  printf '%s\n' "${CREW_ID:-$(date +%s)-$$}"
  exit 0
fi
if [ "$sub" = identity ]; then
  [ -n "${1:-}" ] || {
    echo "crew: identity <branch>" >&2
    exit 1
  }
  _identity "$1"
  exit 0
fi

# repo-keyed bus dir; --path-format=absolute so main-checkout and worktrees
# resolve to a byte-identical path (load-bearing — see #29).
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] || {
  echo "crew: not in a git repo" >&2
  exit 1
}
dir="$common/crew"
log="$dir/events.jsonl"

case "$sub" in
status | msg)
  crew=$(_crew_id)
  [ -n "$crew" ] || {
    echo "crew: CREW_ID unset and no WORKER_TASK.md crew_id" >&2
    exit 1
  }
  mkdir -p "$dir"
  if [ "$sub" = status ]; then
    # status <from> <state> [detail] [pr_url]
    line=$(jq -nc --arg crew "$crew" --arg from "${1:-}" --arg state "${2:-}" \
      --arg detail "${3:-}" --arg pr "${4:-}" \
      '{ts:(now*1000|floor), crew_id:$crew, from:$from, to:("dispatcher:"+$crew),
          kind:"status",
          body:({state:$state}
                + (if $detail!="" then {detail:$detail} else {} end)
                + (if $pr!="" then {pr_url:$pr} else {} end))}')
  else
    # msg <from> <to> <body>
    line=$(jq -nc --arg crew "$crew" --arg from "${1:-}" --arg to "${2:-}" --arg body "${3:-}" \
      '{ts:(now*1000|floor), crew_id:$crew, from:$from, to:$to, kind:"msg", body:$body}')
  fi
  printf '%s\n' "$line" >>"$log"
  ;;
reply)
  # reply <to> <body> — sugar over `msg`; from is dispatcher:<crew> so the
  # dispatcher needn't reconstruct its own id.
  crew=$(_crew_id)
  [ -n "$crew" ] || {
    echo "crew: CREW_ID unset and no WORKER_TASK.md crew_id" >&2
    exit 1
  }
  mkdir -p "$dir"
  line=$(jq -nc --arg crew "$crew" --arg to "${1:-}" --arg body "${2:-}" \
    '{ts:(now*1000|floor), crew_id:$crew, from:("dispatcher:"+$crew), to:$to, kind:"msg", body:$body}')
  printf '%s\n' "$line" >>"$log"
  ;;
await)
  # await <agent> [--timeout S] [--interval S] — block until a msg addressed to
  # <agent> arrives (ts strictly after the await started), print it, exit 0;
  # exit 3 on timeout. No LLM tokens burned: this is a held bash call, not a
  # spin loop. A late reply is never lost — it stays in the durable log for the
  # next activation.
  crew=$(_crew_id)
  [ -n "$crew" ] || {
    echo "crew: CREW_ID unset and no WORKER_TASK.md crew_id" >&2
    exit 1
  }
  me="${1:-}"
  [ -n "$me" ] || {
    echo "crew: await <agent> [--timeout S] [--interval S]" >&2
    exit 1
  }
  shift || true
  timeout=300
  interval=2
  while [ $# -gt 0 ]; do
    case "$1" in
    --timeout)
      [ -n "${2:-}" ] || {
        echo "crew: --timeout needs a value" >&2
        exit 1
      }
      timeout="$2"
      shift 2
      ;;
    --interval)
      [ -n "${2:-}" ] || {
        echo "crew: --interval needs a value" >&2
        exit 1
      }
      interval="$2"
      shift 2
      ;;
    *)
      echo "crew: await: unknown arg '$1'" >&2
      exit 1
      ;;
    esac
  done
  start=$(jq -nc 'now*1000|floor')
  deadline=$((start + timeout * 1000))
  while :; do
    if [ -f "$log" ]; then
      ans=$(jq -c --arg crew "$crew" --arg me "$me" --argjson since "$start" \
        'select(.crew_id==$crew and .kind=="msg" and .to==$me and .ts>$since)' "$log" 2>/dev/null | tail -n1 || true)
      [ -n "$ans" ] && {
        printf '%s\n' "$ans"
        exit 0
      }
    fi
    [ "$(jq -nc 'now*1000|floor')" -ge "$deadline" ] && {
      echo "crew: await timed out after ${timeout}s (no reply to $me)" >&2
      exit 3
    }
    sleep "$interval"
  done
  ;;
watch)
  # watch [--since TS] [--states a,b,c] [--timeout S] [--interval S] — block until
  # any worker event qualifies (a status whose state is in --states, or a msg to
  # the dispatcher), print {"cursor":TS,"events":[…]} and exit 0; exit 3 on
  # timeout (no stdout). Default --timeout is a finite long park (3300s / 55min):
  # an indefinite watch is rejected, because a reaped indefinite watch is
  # undetectable. When --since is omitted the cursor is self-seeded from
  # dispatcher.cursor (see below) so a stale caller cursor can't re-deliver.
  # Zero-token held poll, like `await`. Strict `>` matches `await` (same-ms edge).
  crew=$(_crew_id)
  [ -n "$crew" ] || {
    echo "crew: CREW_ID unset and no WORKER_TASK.md crew_id" >&2
    exit 1
  }
  mkdir -p "$dir"
  since=0
  since_explicit=0
  states="blocked,pr_open,done,failed"
  timeout=3300
  interval=2
  while [ $# -gt 0 ]; do
    case "$1" in
    --since)
      [ -n "${2:-}" ] || {
        echo "crew: --since needs a value" >&2
        exit 1
      }
      since="$2"
      since_explicit=1
      shift 2
      ;;
    --states)
      [ -n "${2:-}" ] || {
        echo "crew: --states needs a value" >&2
        exit 1
      }
      states="$2"
      shift 2
      ;;
    --timeout)
      [ -n "${2:-}" ] || {
        echo "crew: --timeout needs a value" >&2
        exit 1
      }
      timeout="$2"
      shift 2
      ;;
    --interval)
      [ -n "${2:-}" ] || {
        echo "crew: --interval needs a value" >&2
        exit 1
      }
      interval="$2"
      shift 2
      ;;
    *)
      echo "crew: watch: unknown arg '$1'" >&2
      exit 1
      ;;
    esac
  done
  case "$since" in '' | *[!0-9]*)
    echo "crew: --since must be an integer ms timestamp" >&2
    exit 1
    ;;
  esac
  case "$timeout" in '' | *[!0-9]*)
    echo "crew: --timeout must be a positive integer number of seconds" >&2
    exit 1
    ;;
  esac
  [ "$timeout" -gt 0 ] || {
    echo "crew: --timeout must be > 0 (indefinite watch unsupported: a reaped watch would be undetectable)" >&2
    exit 1
  }
  statesjson=$(printf '%s' "$states" | jq -Rc 'split(",") | map(select(length>0))')
  [ "$statesjson" = "[]" ] && {
    echo "crew: --states must be non-empty" >&2
    exit 1
  }
  cursor_file="$dir/dispatcher.cursor"
  if [ "$since_explicit" = 0 ]; then
    seed=$(cat "$cursor_file" 2>/dev/null || true)
    case "$seed" in '' | *[!0-9]*) seed=0 ;; esac
    since="$seed"
  fi
  wlock="$dir/dispatcher.watch.lock.d"
  _lock_acquire "$wlock" "$$" || {
    echo "crew: another dispatcher watch is already running for this crew (dispatcher.watch.lock.d)" >&2
    exit 1
  }
  trap '_lock_release "$wlock"' EXIT
  me="dispatcher:$crew"
  start=$(jq -nc 'now*1000|floor')
  deadline=$((start + timeout * 1000))
  while :; do
    if [ -f "$log" ]; then
      batch=$(jq -c -s --arg crew "$crew" --arg me "$me" --argjson since "$since" --argjson states "$statesjson" '
          map(select(.crew_id==$crew and .ts>$since
                and ( (.kind=="status" and (.body.state as $s | $states | index($s)))
                      or (.kind=="msg" and (.to==$me or .to=="*")) )))
          | sort_by(.ts)
          | select(length>0)
          | {cursor:(.[-1].ts), events:.}' "$log" 2>/dev/null || true)
      [ -n "$batch" ] && {
        printf '%s\n' "$batch"
        last=$(printf '%s' "$batch" | jq -r '.cursor')
        tmp=$(mktemp "$dir/.cursor.XXXXXX")
        printf '%s\n' "$last" >"$tmp"
        mv -f "$tmp" "$cursor_file"
        exit 0
      }
    fi
    [ "$(jq -nc 'now*1000|floor')" -ge "$deadline" ] && {
      echo "crew: watch timed out after ${timeout}s (no events > $since)" >&2
      exit 3
    }
    sleep "$interval"
  done
  ;;
roster)
  crew="${1:-$(_crew_id)}"
  [ -f "$log" ] || exit 0
  # latest status per agent, decorated with each worker's derived codename
  base=$(jq -c -s --arg crew "$crew" '
      map(select(.crew_id==$crew and .kind=="status"))
      | group_by(.from) | map(
          (max_by(.ts)) as $latest
          | {from: $latest.from,
             state: $latest.body.state,
             # carry forward last-known pr_url — the terminal `done` event drops it
             pr_url: (map(.body.pr_url) | map(select(. != null)) | last),
             age_s: ((now - ($latest.ts/1000))|floor)})' "$log")
  idmap='{}'
  for from in $(printf '%s' "$base" | jq -r '.[].from | select(startswith("worker:"))'); do
    id=$(_identity "${from#worker:}")
    idmap=$(printf '%s' "$idmap" | jq -c --arg k "$from" --argjson v "$id" '. + {($k): $v}')
  done
  printf '%s' "$base" | jq --argjson m "$idmap" 'map(. + ($m[.from] // {}))'
  ;;
inbox)
  # messages only — `roster` owns status (every status is addressed to the
  # dispatcher, so without this the inbox is status spam).
  crew="${2:-$(_crew_id)}"
  [ -f "$log" ] || exit 0
  jq -c --arg crew "$crew" --arg me "${1:-}" \
    'select(.crew_id==$crew and .kind=="msg" and (.to==$me or .to=="*"))' "$log"
  ;;
log)
  crew="${1:-$(_crew_id)}"
  [ -f "$log" ] || exit 0
  jq -c --arg crew "$crew" 'select(.crew_id==$crew)' "$log"
  ;;
*)
  echo "usage: crew id | identity <branch> | status <from> <state> [detail] [pr] | msg <from> <to> <body> | reply <to> <body> | await <agent> [--timeout S] [--interval S] | watch [--since TS] [--states a,b,c] [--timeout S] [--interval S] | roster [crew] | inbox <agent> [crew] | log [crew]" >&2
  exit 1
  ;;
esac
