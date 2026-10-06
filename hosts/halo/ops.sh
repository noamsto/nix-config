# shellcheck shell=bash
# halo-ops: halo-local ops CLI plus the entry points of the halo-* units.
# FLAKE, LEMOND_PORT, LOCK_COMMIT_FILTER, OPS_STATE and OPS_USER come from ops.nix.

NIX_BUILD_FLAGS=(--max-jobs 2 --cores 4 --no-link)

die() {
  echo "halo-ops: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
usage: halo-ops <command>
  rebuild                    fast-forward the checkout, build and switch halo
  update-prepare [inputs...] update inputs and gate them (exit 10: already up to date)
  update-push                commit and push the gated candidate lock
  reboot                     reboot halo
  status                     uptime, generation, failed units, inference state, memory
  logs <unit> [-n N]         follow a unit's journal
  restart <lemond|ds4>       restart an inference server (stops the other one)
  console <on|off>           start or stop the display manager
USAGE
}

sync_main() {
  cd "$FLAKE" || die "cannot cd to $FLAKE"
  git fetch origin main
  [[ "$(git symbolic-ref --short HEAD)" == main ]] || die "$FLAKE is not on branch main"
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "$FLAKE has uncommitted tracked changes"
  git merge --ff-only origin/main
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] ||
    die "$FLAKE has local commits not on origin/main"
}

# Start a unit while following its journal; exit status is the unit's.
run_unit() {
  local unit=$1 epoch rc=0
  epoch=$(date +%s)
  journalctl -f -o cat -u "$unit" --since "@$epoch" &
  trap 'kill $! 2>/dev/null || true' EXIT
  systemctl start --no-ask-password "$unit" || rc=$?
  sleep 1
  exit "$rc"
}

toplevel_attr() {
  echo ".#nixosConfigurations.$1.config.system.build.toplevel"
}

# Prints only the store path on stdout; the caller captures it.
build_system() {
  sync_main >&2
  local rev
  rev=$(git rev-parse HEAD)
  nix build "${NIX_BUILD_FLAGS[@]}" --print-out-paths \
    "git+file://$FLAKE?rev=$rev#nixosConfigurations.halo.config.system.build.toplevel"
}

rebuild_unit() {
  local path
  path=$(runuser -u "$OPS_USER" -- "$0" _build-system)
  [[ $path =~ ^/nix/store/[^/]+$ ]] || die "refusing store path: $path"
  [[ -x "$path/bin/switch-to-configuration" ]] || die "no switch-to-configuration in $path"
  nix-env -p /nix/var/nix/profiles/system --set "$path"
  "$path/bin/switch-to-configuration" switch
}

lock_message() {
  git show HEAD:flake.lock | jq -c -f "$LOCK_COMMIT_FILTER" --slurpfile new "$1"
}

update_prepare_unit() {
  local inputs=() name root_inputs
  if [[ -f "$OPS_STATE/update-inputs" ]]; then
    mapfile -t inputs <"$OPS_STATE/update-inputs"
  fi

  sync_main
  trap 'git checkout -- flake.lock' EXIT
  rm -f "$OPS_STATE"/candidate.{lock,base,summary}

  local names=()
  root_inputs=$(jq -r '.nodes[.root].inputs | keys[]' flake.lock)
  for name in "${inputs[@]}"; do
    [[ -n $name ]] || continue
    [[ $name =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid input name: $name"
    grep -qxF -- "$name" <<<"$root_inputs" || die "not a root input of flake.lock: $name"
    names+=("$name")
  done

  nix flake update "${names[@]}"

  local result
  result=$(lock_message flake.lock)
  if [[ "$(jq -r .changed <<<"$result")" != true ]]; then
    echo "already up to date"
    return 0
  fi

  local host
  for host in halo thinkpad-p14s-g5 thinkpad-p14s-g6; do
    echo "building $host"
    nix build "${NIX_BUILD_FLAGS[@]}" "$(toplevel_attr "$host")"
  done
  echo "evaluating mbp-m4-pro"
  nix eval --raw .#darwinConfigurations.mbp-m4-pro.config.system.build.toplevel.drvPath >/dev/null

  cp flake.lock "$OPS_STATE/candidate.lock"
  git rev-parse HEAD >"$OPS_STATE/candidate.base"
  jq -r '.subject, "", .body' <<<"$result" >"$OPS_STATE/candidate.summary"
}

update_push_unit() {
  [[ -f "$OPS_STATE/candidate.lock" && -f "$OPS_STATE/candidate.base" ]] ||
    die "no candidate; run update-prepare first"
  local base
  base=$(<"$OPS_STATE/candidate.base")

  sync_main
  [[ "$(git rev-parse HEAD)" == "$base" && "$(git rev-parse origin/main)" == "$base" ]] ||
    die "main moved since the candidate was prepared; re-run update-prepare"

  trap 'git checkout -- flake.lock' EXIT
  cp "$OPS_STATE/candidate.lock" flake.lock
  local result
  result=$(lock_message flake.lock)
  git commit -m "$(jq -r .subject <<<"$result")" -m "$(jq -r .body <<<"$result")" -- flake.lock

  if ! git push origin HEAD:main; then
    git reset --keep "$base"
    die "push failed; reset to $base"
  fi
  rm -f "$OPS_STATE"/candidate.{lock,base,summary}
}

update_prepare() {
  # is-active reports a running oneshot as "activating" and exits non-zero.
  [[ "$(systemctl show -P ActiveState halo-update-prepare.service)" =~ ^(activating|active|deactivating|reloading)$ ]] &&
    die "an update is already being prepared"
  if (($# > 0)); then
    printf '%s\n' "$@" >"$OPS_STATE/update-inputs"
  else
    : >"$OPS_STATE/update-inputs"
  fi
  (run_unit halo-update-prepare.service)
  [[ -f "$OPS_STATE/candidate.lock" ]] || exit 10
  cat "$OPS_STATE/candidate.summary"
}

status() {
  local profile current models mem_total mem_avail
  uptime
  echo
  profile=$(readlink /nix/var/nix/profiles/system)
  current=$(readlink -f /run/current-system)
  echo "generation: $profile"
  if [[ "$(readlink -f /nix/var/nix/profiles/system)" == "$current" ]]; then
    echo "running system matches the profile"
  else
    echo "running system differs from the profile ($current)"
  fi
  echo
  echo "failed units:"
  systemctl --failed --no-legend --plain
  echo
  local unit
  for unit in lemond lemond-preload ds4-server display-manager; do
    printf '%-16s %s\n' "$unit" "$(systemctl is-active "$unit" || true)"
  done
  if models=$(curl -s --max-time 3 "http://127.0.0.1:$LEMOND_PORT/api/v1/health" |
    jq -r '.all_models_loaded[]?.model_name'); then
    echo "loaded models: ${models:-none}"
  else
    echo "loaded models: unreachable"
  fi
  mem_total=$(awk '/^MemTotal:/ {printf "%.1f", $2/1048576}' /proc/meminfo)
  mem_avail=$(awk '/^MemAvailable:/ {printf "%.1f", $2/1048576}' /proc/meminfo)
  echo "memory: ${mem_avail} GiB available of ${mem_total} GiB"
}

logs() {
  local unit=${1:-} n=50
  shift || true
  [[ $unit =~ ^[A-Za-z0-9@._:-]+$ && $unit != -* ]] || die "invalid unit: $unit"
  if [[ ${1:-} == -n ]]; then
    n=${2:-}
    [[ $n =~ ^[0-9]+$ ]] || die "-n needs a number"
  fi
  exec journalctl -u "$unit" -f -n "$n"
}

restart() {
  local unit
  case "${1:-}" in
  lemond) unit=lemond.service ;;
  ds4) unit=ds4-server.service ;;
  *) die "restart <lemond|ds4>" ;;
  esac
  systemctl restart --no-ask-password "$unit"
  printf '%-18s %s\n' lemond.service "$(systemctl is-active lemond.service || true)" \
    ds4-server.service "$(systemctl is-active ds4-server.service || true)"
}

console() {
  case "${1:-}" in
  on) systemctl start --no-ask-password display-manager.service ;;
  off) systemctl stop --no-ask-password display-manager.service ;;
  *) die "console <on|off>" ;;
  esac
}

cmd=${1:-help}
shift || true
case "$cmd" in
rebuild) run_unit halo-rebuild.service ;;
update-prepare) update_prepare "$@" ;;
update-push) run_unit halo-update-push.service ;;
reboot) run_unit halo-reboot.service ;;
status) status ;;
logs) logs "$@" ;;
restart) restart "$@" ;;
console) console "$@" ;;
_build-system) build_system ;;
_rebuild-unit) rebuild_unit ;;
_update-prepare-unit) update_prepare_unit ;;
_update-push-unit) update_push_unit ;;
help | -h | --help) usage ;;
*)
  usage >&2
  exit 2
  ;;
esac
