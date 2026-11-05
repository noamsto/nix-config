#!/usr/bin/env bash
# PreToolUse hook: block overriding the git identity (-c user.name/user.email,
# --author, GIT_AUTHOR_*/GIT_COMMITTER_*, `git config user.*` writes) when the
# repo has a remote. Commits must carry the configured identity; a forged one
# lands in shared history. Repos with no remote are scratch space and exempt.
# `git config --global/--system` identity writes are always denied: they
# rewrite the user-wide identity for every later commit, whatever the cwd.

set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
[[ $tool_name == "Bash" ]] || exit 0

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -n $command ]] || exit 0

# A backslash-newline continuation is a space to the shell; join it so a
# flag on the next line stays in the same command.
continuation=$'\\\n'
command=${command//"$continuation"/ }

git_word_re='(^|[[:space:];&|(/])git[[:space:]]'
identity_keys='(user|author|committer)\.(name|email)'

# Case-insensitive on purpose for the git-side checks: config keys are
# case-insensitive. The GIT_AUTHOR_*/GIT_COMMITTER_* names are matched with it off.
identity_override() {
  local seg value cfg_write=
  # shellcheck disable=SC2016 # `${` is literal: a `${VAR}` read is not an assignment
  local env_re='(^|[^A-Za-z0-9_${])GIT_((AUTHOR|COMMITTER)_(NAME|EMAIL)|CONFIG_PARAMETERS)='
  local key_env_re="(^|[^A-Za-z0-9_\${])GIT_CONFIG_KEY_[0-9]+=[\"']?$identity_keys"
  local c_re="[[:space:]]-c[[:space:]]+[\"']?$identity_keys="
  local cenv_re="[[:space:]]--config-env[=[:space:]]+$identity_keys="
  local author_re='[[:space:]]commit[[:space:]].*--author([=[:space:]])'
  local config_re="[[:space:]]config[[:space:]]+([^[:space:]]+[[:space:]]+)*[\"']?${identity_keys}[\"']?[[:space:]]+([^[:space:]]+)"
  local redirect_re='^[0-9]*[<>;&|]'
  local global_re='([[:space:]]--(global|system)([[:space:]]|$)|[[:space:]]--file[=[:space:]]|[[:space:]]-f[[:space:]])'
  local read_re='[[:space:]](--get|--get-all|--get-regexp|get|--unset|--unset-all|unset|--list|-l)([[:space:]]|$)'

  # Per segment, so one invocation's write is told from another's read; and
  # before any early return, so a global write is seen whatever else matches.
  shopt -s nocasematch
  while IFS= read -r seg; do
    [[ $seg =~ $git_word_re ]] || continue
    if [[ $seg =~ $config_re ]]; then
      value=${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}
      # A redirection or separator after the key is a read
      # (`git config user.name 2>/dev/null`).
      [[ $value =~ $redirect_re ]] && continue
      [[ $seg =~ $read_re ]] && continue
      [[ $seg =~ $global_re ]] && global_write=1
      cfg_write=1
    fi
  done < <(tr ';&|' '\n' <<<"$command")
  shopt -u nocasematch

  [[ $command =~ $env_re ]] && return 0
  [[ -n $cfg_write ]] && return 0

  shopt -s nocasematch
  if [[ $command =~ $key_env_re ]]; then
    shopt -u nocasematch
    return 0
  fi
  if [[ $command =~ $git_word_re ]] &&
    [[ $command =~ $c_re || $command =~ $cenv_re || $command =~ $author_re ]]; then
    shopt -u nocasematch
    return 0
  fi
  shopt -u nocasematch
  return 1
}

global_write=
identity_override || exit 0

# git runs in the intercepted command's cwd, not the hook process's cwd.
cwd=$(jq -r '.cwd // empty' <<<"$input" || true)
cwd=${cwd:-$PWD}

# Directory tracking is a regex over the command, not a shell parser, so it
# only ever adds targets: every -C/--git-dir/GIT_DIR and every cd/pushd dir
# counts, and cwd is dropped only for a plain leading `cd <dir>` with no other
# directory change or subshell. A stray match can only add a denial.
dir_re='("[^"]+"|'\''[^'\'']+'\''|[^[:space:];&|]+)'
cd_re="(^|[[:space:](])(cd|pushd)[[:space:]]+$dir_re"
lead_cd_re="^[[:space:]]*cd[[:space:]]+$dir_re"
other_cd_re='(^|[^A-Za-z0-9_])(cd|pushd|popd)([^A-Za-z0-9_]|$)|[()]'
matches=()
all_matches() {
  local rest=$1 re=$2
  matches=()
  while [[ $rest =~ $re ]]; do
    matches+=("${BASH_REMATCH[${#BASH_REMATCH[@]} - 1]}")
    rest=${rest#*"${BASH_REMATCH[0]}"}
  done
}
resolved=
base=$cwd
resolve() {
  resolved=${1#[\"\']}
  resolved=${resolved%[\"\']}
  [[ $resolved == /* ]] || resolved=$base/$resolved
}

targets=()
gitdirs=()
scan=$command
if [[ $command =~ $lead_cd_re ]]; then
  lead=${BASH_REMATCH[1]}
  rest=${command#"${BASH_REMATCH[0]}"}
  if ! [[ $rest =~ $other_cd_re ]]; then
    scan=$rest
    resolve "$lead"
    targets+=("$resolved")
    base=$resolved
  fi
fi

saw_git=
while IFS= read -r seg; do
  if [[ $seg =~ $git_word_re ]]; then
    saw_git=1
    selected=
    for re in "(^|[[:space:]])-C[[:space:]]+$dir_re" \
      "(^|[[:space:]])--git-dir[=[:space:]]$dir_re" \
      "(^|[[:space:]])GIT_DIR=$dir_re"; do
      all_matches "$seg" "$re"
      for m in "${matches[@]}"; do
        resolve "$m"
        targets+=("$resolved")
        selected=1
      done
    done
    [[ -n $selected ]] || targets+=("$base")
    targets+=("${gitdirs[@]}")
  else
    all_matches "$seg" "$cd_re"
    for m in "${matches[@]}"; do
      resolve "$m"
      targets+=("$resolved")
    done
    all_matches "$seg" "(^|[[:space:]])GIT_DIR=$dir_re"
    for m in "${matches[@]}"; do
      resolve "$m"
      gitdirs+=("$resolved")
    done
  fi
done < <(tr ';&|' '\n' <<<"$scan")
[[ -n $saw_git ]] || targets+=("$base")

blocked=
for target in "${targets[@]}"; do
  # Unresolvable (not a repo, or created by this very command) fails closed.
  remotes=unresolved
  if git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    remotes=$(git -C "$target" remote 2>/dev/null) || remotes=unresolved
  fi
  [[ -z $remotes ]] || blocked=1
done
[[ -n $blocked || -n $global_write ]] || exit 0

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "commit with the configured git identity; never set user.name/user.email, --author or GIT_AUTHOR_*/GIT_COMMITTER_* in a repo with a remote"
  }
}'
