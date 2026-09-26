#!/usr/bin/env bash
# PreToolUse hook: ask before a `gh` post to a public repo carries private
# context — a private repo's `owner/name`, an agent session URL, a scratchpad
# path, a home-directory path, or a secret gitleaks recognizes. Once posted,
# GitHub's edit history keeps it public even after the body is fixed.
#
# `ask`, not `deny`: whether a name is a leak is a judgment call, and on
# Claude Code the prompt lets it through. pi has no prompt and degrades ask to
# deny, which is the safe side.
#
# Private repos come from `gh api user/repos?visibility=private` (org repos
# included), cached for a day. Bare repo names are not matched: private repos
# named `api`, `docs` or `notes` would flag half of all prose. A target in that
# same list is private, so private-to-private posts pass. When the list can't
# be fetched and no cache exists, the guard abstains.

set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
[[ $tool_name == "Bash" ]] || exit 0

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -n $command ]] || exit 0

post_re='(^|[;&|(][[:space:]]*|[[:space:]])gh[[:space:]]+((issue|pr)[[:space:]]+(create|comment|edit|review)|release[[:space:]]+(create|edit)|api)([[:space:]]|$)'
[[ $command =~ $post_re ]] || exit 0
# Scan from the `gh` call on, so a leading `cd ~/git/private-repo &&` is not
# mistaken for body text.
text=${BASH_REMATCH[0]}${command#*"${BASH_REMATCH[0]}"}

# `gh api` without a field or input sends no body.
if [[ ${BASH_REMATCH[2]} == api ]]; then
  [[ $text =~ [[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]) ]] || exit 0
fi

cwd=$(jq -r '.cwd // empty' <<<"$input" || true)
cwd=${cwd:-$PWD}
# The Bash tool resets its cwd each call, so a post from another checkout
# arrives as `cd <dir> && gh …`.
if [[ $command =~ (^|[;&|][[:space:]]*|[[:space:]])cd[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^[:space:];&|]+) ]]; then
  dir=${BASH_REMATCH[2]}
  dir=${dir#[\"\']}
  dir=${dir%[\"\']}
  dir=${dir/#\~/$HOME}
  [[ $dir == /* ]] || dir=$cwd/$dir
  cwd=$dir
fi

slug='([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)'
target=
if [[ $text =~ (-R|--repo)[[:space:]=]+[\"\']?([A-Za-z0-9_.-]+/)?$slug ]]; then
  target=${BASH_REMATCH[3]}
elif [[ $text =~ github\.com/$slug/(issues|pull|releases) ]]; then
  target=${BASH_REMATCH[1]}
elif [[ $text =~ repos/$slug(/|[[:space:]\"\']|$) ]]; then
  target=${BASH_REMATCH[1]}
else
  remote=$(git -C "$cwd" remote get-url origin 2>/dev/null || true)
  [[ $remote =~ github\.com[:/]$slug ]] && target=${BASH_REMATCH[1]}
fi
target=${target%.git}
target=${target,,}
[[ -n $target ]] || exit 0

cache=${XDG_CACHE_HOME:-$HOME/.cache}/agent-public-leak-guard/private-repos
if [[ -z $(find "$cache" -mmin -1440 2>/dev/null) ]]; then
  mkdir -p "$(dirname "$cache")"
  if fetched=$(timeout 3 gh api 'user/repos?visibility=private&per_page=100' --paginate --jq '.[].full_name' 2>/dev/null); then
    printf '%s\n' "${fetched,,}" >"$cache.tmp" && mv "$cache.tmp" "$cache"
  fi
fi
[[ -s $cache ]] || exit 0

grep -qxF "$target" "$cache" && exit 0

# Bodies also arrive by file: `--body-file`/`-F <path>`, `--input <path>`,
# and `gh api`'s `-F body=@<path>`. The path itself is dropped from the scanned
# text: a body file in the scratchpad is not a leak, its contents may be.
# `-F` takes a path only without `=`; `gh api -F key=value` is a field.
file_arg_re='(--body-file|--input)[[:space:]=]+[^[:space:]]+|-F[[:space:]]+[^[:space:]=]+([[:space:]]|$)|=@[^[:space:]]+'
body=$(sed -E "s#$file_arg_re##g" <<<"$text")
while read -r path; do
  [[ -n $path && $path != - ]] || continue
  [[ $path == /* ]] || path=$cwd/$path
  if [[ -f $path ]]; then
    body+=$'\n'$(<"$path")
  fi
done < <(grep -oE "$file_arg_re" <<<"$text" |
  sed -E 's/^(--body-file|-F|--input)[[:space:]=]+//; s/^.*=@//; s/[[:space:]]+$//; s/^["'\'']//; s/["'\'']$//' || true)

hits=$(grep -oiwF -f "$cache" <<<"$body" | tr '[:upper:]' '[:lower:]' | sort -u || true)
hits+=$'\n'$(grep -oE 'claude\.ai/code/session_[A-Za-z0-9]+|/tmp/claude-[^[:space:]]*|'"$HOME"'/[^[:space:]]*' <<<"$body" | sort -u || true)
hits+=$'\n'$(gitleaks stdin --no-banner -l error --redact -f json -r - <<<"$body" 2>/dev/null |
  jq -r '.[] | "secret: \(.RuleID)"' | sort -u || true)
hits=$(sed '/^$/d' <<<"$hits")
[[ -n $hits ]] || exit 0

jq -n --arg target "$target" --arg hits "$hits" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("This posts to \($target), which is not in your private repos, and the text carries private context:\n\($hits)\nRewrite it for an outside reader: drop private repo names and links, session URLs and local paths, and describe the finding so someone without that access can act on it and reproduce it.")
  }
}'
