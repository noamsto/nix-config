# shellcheck shell=bash
# Runs on the houston-dev-sync timer (every 2min). Builds `main` when it
# moves, then flips it live once it's safe to restart houston.service.
: "${nixpkgs_src:?}" "${dev_dir:?}"

note() {
  mkdir -p "$dev_dir"
  printf '%s %s\n' "$(date -Is)" "$*" >"$dev_dir/last-sync"
  echo "$*" >&2
}

[[ -e "$dev_dir/enabled" ]] || exit 0

main_sha=$(main_head 60) || {
  note "fetch failed: git ls-remote errored"
  exit 1
}
main_sha=${main_sha%%[[:space:]]*}
if [[ ! $main_sha =~ ^[0-9a-f]{40}$ ]]; then
  note "fetch failed: unexpected ls-remote output"
  exit 1
fi

sha=""
[[ -e "$dev_dir/sha" ]] && sha=$(<"$dev_dir/sha")
next_sha=""
[[ -e "$dev_dir/next-sha" ]] && next_sha=$(<"$dev_dir/next-sha")

if [[ -e "$dev_dir/next" && $next_sha == "$main_sha" ]]; then
  : # already staged — fall through to activation
elif [[ $sha == "$main_sha" && -e "$dev_dir/current" && ! -e "$dev_dir/next" ]]; then
  note "up to date at $main_sha"
  exit 0
else
  failed_sha=""
  attempts=0
  if [[ -e "$dev_dir/failed" ]]; then
    read -r failed_sha attempts <"$dev_dir/failed" || true
  fi
  [[ $attempts =~ ^[0-9]+$ ]] || attempts=0

  if [[ $failed_sha == "$main_sha" && $attempts -ge 3 ]]; then
    note "build of $main_sha failed $attempts times; waiting for a new commit (houston-dev sync retries)"
    exit 0
  fi

  echo "building $main_sha" >&2
  if ! nix build "github:noamsto/houston/$main_sha" \
    --override-input nixpkgs "path:$nixpkgs_src" \
    --out-link "$dev_dir/next"; then
    if [[ $failed_sha == "$main_sha" ]]; then
      attempts=$((attempts + 1))
    else
      attempts=1
    fi
    mkdir -p "$dev_dir"
    printf '%s %s\n' "$main_sha" "$attempts" >"$dev_dir/failed"
    note "build of $main_sha failed (attempt $attempts)"
    exit 1
  fi

  echo "$main_sha" >"$dev_dir/next-sha"
  rm -f "$dev_dir/failed"
fi

if [[ ! -e "$dev_dir/enabled" ]]; then
  # `houston-dev off` ran while we were building — don't deploy behind its back.
  rm -f "$dev_dir/next" "$dev_dir/next-sha"
  exit 0
fi

if dispatch_busy; then
  note "built $main_sha; restart deferred: dispatch in flight"
  exit 0
fi

# `nix build` (not `mv`) re-registers the GC root under its new name; moving
# the out-link file would leave nix's auto GC root pointing at the old name.
if ! nix build "$(readlink -f "$dev_dir/next")" --out-link "$dev_dir/current"; then
  note "activation of $main_sha failed: could not link $dev_dir/current"
  exit 1
fi
mv "$dev_dir/next-sha" "$dev_dir/sha"
rm -f "$dev_dir/next"

if [[ ${HOUSTON_DEV_NO_RESTART:-} == 1 ]]; then
  echo "HOUSTON_DEV_NO_RESTART: would restart houston" >&2
else
  if ! systemctl --user try-restart houston.service; then
    note "deployed $main_sha but restart failed; houston-dev off to fall back"
    exit 1
  fi
fi

note "deployed $main_sha"
