# shellcheck shell=bash
usage() {
  cat >&2 <<'USAGE'
usage: halo <command>
  rebuild                      rebuild halo from its own checkout
  update [inputs...] [--skip <input>]... [--switch]
                               update flake.lock on halo, push, optionally rebuild
  reboot
  status
  logs <unit> [-n N]
  restart <lemond|ds4>
  console <on|off>
  push                         build on halo from this checkout and switch it
USAGE
  exit 2
}

tty=()
[[ -t 1 ]] && tty=(-t)

# ssh joins its arguments into one remote shell string, so quote each one.
remote() {
  local args=()
  local a
  for a in "$@"; do args+=("$(printf '%q' "$a")"); done
  # shellcheck disable=SC2029 # args are quoted above on purpose
  ssh "${tty[@]}" halo halo-ops "${args[@]}"
}

confirm() {
  if [[ ! -t 0 ]]; then
    echo "halo: confirmation needs a terminal, aborting" >&2
    exit 1
  fi
  local a
  read -r -p "$1 [y/N] " a
  [[ $a == [yY]* ]]
}

[[ $# -ge 1 ]] || usage
cmd=$1
shift

case $cmd in
rebuild | status | logs | console)
  remote "$cmd" "$@"
  ;;
restart)
  [[ ${1-} ]] || usage
  case $1 in
  ds4)
    if ssh halo systemctl is-active --quiet lemond.service; then
      confirm "ds4 takes the box over and stops lemond. Continue?" || exit 1
    fi
    ;;
  lemond) echo "note: starting lemond stops ds4 (Conflicts)" ;;
  esac
  remote restart "$@"
  ;;
reboot)
  ssh halo true || {
    echo "halo: cannot reach halo" >&2
    exit 1
  }
  confirm "Reboot halo?" || exit 1
  rc=0
  remote reboot || rc=$?
  # The reboot drops the connection mid-command.
  if [[ $rc -eq 255 ]]; then
    echo "halo is rebooting"
  elif [[ $rc -ne 0 ]]; then
    exit "$rc"
  fi
  ;;
update)
  switch=0
  inputs=()
  while [[ $# -gt 0 ]]; do
    case $1 in
    --switch) switch=1 ;;
    --skip)
      [[ ${2-} ]] || usage
      inputs+=(--skip "$2")
      shift
      ;;
    *) inputs+=("$1") ;;
    esac
    shift
  done
  rc=0
  remote update-prepare "${inputs[@]}" || rc=$?
  if [[ $rc -eq 10 ]]; then
    echo "already up to date"
    exit 0
  fi
  [[ $rc -eq 0 ]] || exit "$rc"
  confirm "Commit and push this lock update to origin main?" || {
    echo "aborted, nothing pushed" >&2
    exit 1
  }
  remote update-push
  if [[ $switch -eq 1 ]]; then remote rebuild; fi
  ;;
push)
  dir=$FLAKE
  if top=$(git rev-parse --show-toplevel 2>/dev/null) && [[ -f $top/hosts/halo/ops.nix ]]; then
    dir=$top
  fi
  # halo builds because x86_64-linux cannot build on the mac; gentle limits
  # because halo keeps its model pinned in memory.
  nixos-rebuild switch --flake "$dir#halo" --target-host halo --build-host halo \
    --sudo --ask-sudo-password --max-jobs 2 --cores 4
  ;;
*) usage ;;
esac
