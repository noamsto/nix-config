# shellcheck shell=bash
# Restart the Determinate Nix daemon when nix.custom.conf changed since the
# last activation that recorded it. Usage: restart-determinate-daemon <conf> <state-file>
#
# The daemon parses nix.custom.conf once at startup. determinate-nixd has no
# reload command, and one launchd job (systems.determinate.nix-daemon) owns both
# its sockets, so the only supported restart is a launchd kickstart. That kills
# builds in flight on the daemon: launchd keeps the sockets open, so new clients
# queue, but running ones cannot be drained.
set -euo pipefail

conf=$1
state=$2
label=system/systems.determinate.nix-daemon

# Never fail the switch over this helper.
[ -f "$conf" ] || exit 0

new=$(sha256sum "$conf" | cut -d' ' -f1)
old=
[ -f "$state" ] && old=$(cat "$state")

if [ "$new" = "$old" ]; then
  exit 0
fi

# First run (no recorded hash): record only. A restart here would kill builds on
# a switch that may have changed nothing; run kickstart by hand once if needed.
if [ -z "$old" ]; then
  mkdir -p "$(dirname "$state")"
  printf '%s\n' "$new" >"$state"
  exit 0
fi

echo "restarting Determinate Nix daemon: $conf changed (${old:0:8} -> ${new:0:8}); running builds are interrupted"
if launchctl kickstart -k "$label"; then
  printf '%s\n' "$new" >"$state"
else
  echo "warning: could not restart $label; will retry on the next switch" >&2
fi
