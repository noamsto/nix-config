#!/usr/bin/env bash
# Claude Code keeps only the last --settings flag, so the wrapper merges the
# caller's layers into its overlay. Hook arrays, permission lists and auto-mode
# rule lists concatenate; layers that would null or retype the hooks or
# permission lists are rejected (add-only: a guard against mistakes, not a
# security boundary, as callers can run the unwrapped binary).
# The output is content-addressed and never deleted: Claude reads (and may
# re-read) it after the wrapper execs. The XDG runtime dir is tmpfs cleared at
# logout; the fallback per-user $TMPDIR dir is left to OS temp cleaning.
# Identical merges share one file. Usage: claude-settings-merge <overlay> <layer>...
set -euo pipefail
umask 077

overlay=$1
shift

# Layer values can hold env secrets: name a value only if it is an existing path
# or has no JSON/whitespace characters; anything else is inline content.
describe() {
  if [ -e "$1" ] || [[ $1 != *[\{\[\"[:space:]]* ]]; then
    echo "--settings '$1'"
  else
    echo "inline --settings #$2"
  fi
}

# Hooks or permission rules of the wrong shape would let a layer drop overlay entries.
# shellcheck disable=SC2016
removes_overlay='
  (has("hooks") and (.hooks | type) != "object")
  or (.hooks // {} | any(.[]; type != "array"))
  or (has("permissions") and (.permissions | type) != "object")
  or (.permissions // {} | to_entries | any(.[]; (.key | IN("allow", "deny", "ask")) and (.value | type != "array")))
  or .disableAllHooks == true'

# shellcheck disable=SC2016
merge_def='
  def merge($a; $b; $path):
    if ($a | type) == "object" and ($b | type) == "object" then
      reduce ($b | keys_unsorted[]) as $k ($a;
        .[$k] = (if has($k) then merge(.[$k]; $b[$k]; $path + [$k]) else $b[$k] end))
    elif ($a | type) == "array" and ($b | type) == "array" and ($path | length) == 2
         and ($path[0] == "hooks"
              or ($path[0] == "permissions" and ($path[1] | IN("allow", "deny", "ask")))
              or ($path[0] == "autoMode" and ($path[1] | IN("environment", "allow", "soft_deny", "hard_deny")))) then
      $a + $b
    else $b end;'

layers=()
n=0
for v in "$@"; do
  n=$((n + 1))
  if [ -f "$v" ] && [ -r "$v" ]; then
    layer=$(<"$v")
  else
    layer=$v
  fi
  if ! printf '%s' "$layer" | jq -es 'length == 1 and (.[0] | type) == "object"' >/dev/null 2>&1; then
    echo "claude: $(describe "$v" "$n") is neither a readable file nor a single JSON object" >&2
    exit 1
  fi
  # Only jq's "false" exit (1) passes; a jq error must reject, not merge.
  status=0
  printf '%s' "$layer" | jq -es ".[0] | ($removes_overlay)" >/dev/null || status=$?
  if [ "$status" -ne 1 ]; then
    echo "claude: $(describe "$v" "$n") would remove the overlay's hooks or permission rules" >&2
    exit 1
  fi
  layers+=("$layer")
done

# Layers go over stdin, not argv, to stay out of /proc/cmdline and under ARG_MAX.
merged=$({
  cat "$overlay"
  printf '%s\n' "${layers[@]}"
} |
  jq -s "$merge_def reduce .[1:][] as \$l (.[0]; merge(.; \$l; []))")

if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  dir=$XDG_RUNTIME_DIR/claude-settings
else
  dir=${TMPDIR:-/tmp}/claude-settings-$(id -u)
fi
mkdir -p "$dir"
if [ -L "$dir" ] || [ ! -O "$dir" ]; then
  echo "claude: refusing settings dir '$dir': symlink or not owned by you" >&2
  exit 1
fi
chmod 700 "$dir"

tmp=$(mktemp "$dir/.settings.XXXXXX")
printf '%s\n' "$merged" >"$tmp"
read -r hash _ < <(sha256sum "$tmp")
mv -f "$tmp" "$dir/settings-$hash.json"
echo "$dir/settings-$hash.json"
