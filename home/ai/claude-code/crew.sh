# File-based coordination bus: id | identity | status | msg | roster | inbox | log
# A real CLI on PATH (not a fish fn) so BOTH the dispatcher (fish) and workers
# (their bash tool) can call it. Pure jq + append; the log is the state.

# Index-aligned codename pool (FleetView-style). identity is deterministic over
# the branch, so any caller recomputes the same name/color — never stored.
_names=(sage atlas nova ember reef iris amber coral moss slate rust plum lime rose sky onyx)
_colors=(green blue magenta orange teal purple yellow salmon olive steel rust plum lime pink sky grey)
_tmuxc=(colour71 colour33 colour201 colour208 colour44 colour141 colour220 colour210 colour108 colour110 colour166 colour96 colour154 colour205 colour117 colour244)

_identity() { # $1=branch -> {name,color,tmux}; cksum is POSIX (portable to macOS)
  local n i
  n=$(printf '%s' "$1" | cksum | cut -d' ' -f1)
  i=$(( n % ${#_names[@]} ))
  jq -nc --arg name "${_names[$i]}" --arg color "${_colors[$i]}" --arg tmux "${_tmuxc[$i]}" \
    '{name:$name, color:$color, tmux:$tmux}'
}

# Resolve the crew id: env wins; else read it from WORKER_TASK.md at the repo
# root, so a worker just calls `crew status …` with no env prefix to remember.
_crew_id() {
  if [ -n "${CREW_ID:-}" ]; then printf '%s' "$CREW_ID"; return 0; fi
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
  [ -n "${1:-}" ] || { echo "crew: identity <branch>" >&2; exit 1; }
  _identity "$1"
  exit 0
fi

# repo-keyed bus dir; --path-format=absolute so main-checkout and worktrees
# resolve to a byte-identical path (load-bearing — see #29).
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
[ -n "$common" ] || { echo "crew: not in a git repo" >&2; exit 1; }
dir="$common/crew"
log="$dir/events.jsonl"

case "$sub" in
  status | msg)
    crew=$(_crew_id)
    [ -n "$crew" ] || { echo "crew: CREW_ID unset and no WORKER_TASK.md crew_id" >&2; exit 1; }
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
  roster)
    crew="${1:-$(_crew_id)}"
    [ -f "$log" ] || exit 0
    # latest status per agent, decorated with each worker's derived codename
    base=$(jq -c -s --arg crew "$crew" '
      map(select(.crew_id==$crew and .kind=="status"))
      | group_by(.from) | map(max_by(.ts))
      | map({from, state:.body.state, pr_url:.body.pr_url,
             age_s:((now - (.ts/1000))|floor)})' "$log")
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
    echo "usage: crew id | identity <branch> | status <from> <state> [detail] [pr] | msg <from> <to> <body> | roster [crew] | inbox <agent> [crew] | log [crew]" >&2
    exit 1
    ;;
esac
