#!/usr/bin/env bash
# Pre-push gate: scan the commits about to be pushed with betterleaks.
#
# Run by prek, which consumes git's pre-push stdin and runs the hook once,
# exposing a single ref as PRE_COMMIT_FROM_REF / PRE_COMMIT_TO_REF /
# PRE_COMMIT_REMOTE_NAME. TO is the pushed sha; FROM is unset on a root-commit
# first push. A multi-ref push (`git push origin a b`, `--all`) still hits the
# hook once, so the range of one ref cannot be trusted. Instead the script scans
# a superset: everything reachable from TO and HEAD (so a detached HEAD pushed
# as `HEAD:refs/heads/x` is covered), every local branch and tag, minus what
# any remote-tracking ref of the remote already has (and minus FROM when it
# resolves locally). A leak on any unpushed local branch or tag therefore also
# blocks the push, intentionally.
# Limit: a second refspec naming a bare commit sha (`git push origin main
# <sha>:refs/heads/y`) is not covered, since prek consumes git's pre-push stdin.
# Needs betterleaks and git on PATH.
set -euo pipefail

zeros=0000000000000000000000000000000000000000
to=${PRE_COMMIT_TO_REF:-}
from=${PRE_COMMIT_FROM_REF:-}

# Deleting a remote ref pushes no commits.
if [[ $to == "$zeros" ]]; then
  exit 0
fi

args=("${to:-HEAD}" HEAD --branches --tags --not "--remotes=${PRE_COMMIT_REMOTE_NAME:-}")
if [[ -n $from && $from != "$zeros" ]] && git rev-parse --verify --quiet "$from^{commit}" >/dev/null; then
  args+=("$from")
fi

first=$(git rev-list --max-count=1 "${args[@]}") || {
  echo "pre-push-leak-check: git rev-list failed" >&2
  exit 1
}
if [[ -z $first ]]; then
  exit 0
fi

# --diff-merges=first-parent also covers merge conflict resolutions, as in CI.
betterleaks git --log-opts "--diff-merges=first-parent ${args[*]}" --redact --no-banner
