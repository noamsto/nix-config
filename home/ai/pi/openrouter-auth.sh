#!/usr/bin/env bash
# Upserts pi's openrouter auth.json entry as `!cat '<keyfile>'`; only the path
# is stored, KEYFILE is never opened.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: openrouter-auth.sh KEYFILE AUTH_JSON" >&2
  exit 2
fi
keyfile=$1

# crew links the dispatcher worker's auth.json to the interactive one; mv onto
# the link would replace it with a regular file and sever the sharing.
target=$(readlink -m "$2")
dir=$(dirname "$target")

umask 077
mkdir -p "$dir"

tmp=
locks=()
stamps=()
stamp() { stat -c '%i %y' "$1" 2>/dev/null; }
cleanup() {
  rm -f "$tmp"
  for i in "${!locks[@]}"; do
    if [ "$(stamp "${locks[i]}")" = "${stamps[i]}" ]; then
      rmdir "${locks[i]}"
    fi
  done
}
trap cleanup EXIT

# pi locks auth.json with proper-lockfile's `<file>.lock` dir, so a token
# refresh can't interleave with this rewrite. It locks the path it was given
# without resolving links, so take the lock under both names. pi reclaims a
# lock whose mtime is over 10s old, so waits touch the held locks, and an
# inode+mtime stamp tells our lock from one pi reclaimed. A foreign lock older
# than 30s counts as stale, so a pi killed while holding it doesn't wedge every
# switch.
refresh() {
  for i in "${!locks[@]}"; do
    if [ "$(stamp "${locks[i]}")" != "${stamps[i]}" ]; then
      echo "openrouter-auth.sh: lost lock ${locks[i]}" >&2
      exit 1
    fi
    touch -c "${locks[i]}"
    stamps[i]=$(stamp "${locks[i]}")
  done
}

acquire() {
  for _ in $(seq 100); do
    if mkdir "$1" 2>/dev/null; then
      locks+=("$1")
      stamps+=("$(stamp "$1")")
      return
    fi
    if [ $(($(date +%s) - $(stat -c %Y "$1" 2>/dev/null || date +%s))) -gt 30 ]; then
      rmdir "$1" 2>/dev/null || true
      continue
    fi
    refresh
    sleep 0.1
  done
  echo "openrouter-auth.sh: timed out waiting for lock $1" >&2
  exit 1
}

acquire "$2.lock"
if ! [ "$target.lock" -ef "$2.lock" ]; then
  acquire "$target.lock"
fi

tmp=$(mktemp "$dir/.auth.json.XXXXXX")

if [ -e "$target" ]; then
  input=$(cat "$target")
else
  input='{}'
fi

jq -s --arg p "$keyfile" '
  (if length == 0 then {}
   elif length == 1 and (.[0] | type) == "object" then .[0]
   else error("auth.json must hold exactly one JSON object") end)
  | .openrouter = {type: "api_key", key: ("!cat " + ($p | @sh))}
' <<<"$input" >"$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$target"
