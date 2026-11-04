#!/usr/bin/env bash
# PreToolUse hook: block flake rebuilds while .nix files are untracked.
# flake-parts evaluates only git-tracked files, so an unstaged .nix is silently
# ignored — the rebuild fails or builds stale source (the nix-config git add gotcha).
# Fires only for rebuild verbs run inside a flake repo (git root with a flake.nix);
# everything else exits 0.

set -euo pipefail

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ $tool_name == "Bash" ]] || exit 0

command=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -n $command ]] || exit 0

# Rebuild verbs that trigger flake evaluation (Linux + nix-darwin).
echo "$command" | grep -qE '\b(nh (os|home|darwin) switch|nixos-rebuild|darwin-rebuild|home-manager switch|nix build|nix flake check)\b' || exit 0

# git runs in the intercepted command's cwd, not the hook process's cwd.
cwd=$(echo "$input" | jq -r '.cwd // empty')
cwd=${cwd:-$PWD}

# Resolve the git root and confirm it's a flake — the gotcha is flake-specific,
# so this generalizes to any flake repo, not just nix-config.
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[[ -f $root/flake.nix ]] || exit 0

untracked=$(git -C "$root" ls-files --others --exclude-standard -- '*.nix' 2>/dev/null) || exit 0
[[ -n $untracked ]] || exit 0

files=$(echo "$untracked" | tr '\n' ' ')
files=${files% }
reason="Untracked .nix files ($files) — flake eval will ignore them. Run: git -C $root add -- $files before rebuilding (flake git add gotcha)."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
