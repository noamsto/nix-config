# shellcheck shell=bash
# Sourced (as text, via builtins.readFile) into houston-dev-sync and
# houston-dev's writeShellApplication text — not standalone-executable.

# shellcheck disable=SC2034 # read by the script this text is prepended to
dev_dir="${HOUSTON_DEV_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/houston/dev}"

# houston runs `dispatch` (a bash script, so its /proc/<pid>/comm is
# "dispatch") as a child of houston.service for up to 120s per POST
# /api/dispatch. Restarting the unit kills its whole cgroup mid-flight and
# aborts a half-built worktree, so callers must check this before recycling
# the service. houston's cgroup also always has a `tmux -CC` child, so we
# can't just count children — we have to look for `dispatch` by name.
dispatch_busy() {
  local cg
  # Fails closed: if we can't tell, assume a dispatch is running. Only an
  # empty ControlGroup (houston not running) means there is nothing to kill.
  cg=$(systemctl --user show -p ControlGroup --value houston.service 2>/dev/null) || return 0
  [[ -n $cg ]] || return 1

  local pid comm
  [[ -r "/sys/fs/cgroup$cg/cgroup.procs" ]] || return 0
  while read -r pid; do
    read -r comm <"/proc/$pid/comm" 2>/dev/null || continue
    [[ $comm == "dispatch" ]] && return 0
  done <"/sys/fs/cgroup$cg/cgroup.procs"

  return 1
}

# Anonymous https, like nix's own github: fetch: the user's global gitconfig
# rewrites https://github.com to ssh, which would tie this to ssh keys/agent.
main_head() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    timeout "$1" git -C / ls-remote https://github.com/noamsto/houston refs/heads/main
}
