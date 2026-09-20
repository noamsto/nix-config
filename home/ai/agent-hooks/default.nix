# Engine-neutral tool-call guards. Both Claude Code (see ../claude-code) and pi
# (see ../pi/guards.nix) run them as hookyard `pre_tool` handlers; hookyard is
# the only transport either engine uses.
#
# Protocol (Claude Code's PreToolUse contract, which is also hookyard's handler
# contract): read a JSON payload on stdin carrying `tool_name`, `tool_input`,
# and `cwd`; write a `hookSpecificOutput` decision on stdout, or exit 0 silently
# to abstain. `permissionDecision: "deny"` blocks; `additionalContext` is
# advisory. `tool_name` is hookyard's canonical vocabulary, so a guard branching
# on `Bash`/`Read` covers pi's `bash`/`read` without knowing they exist.
#
# A guard MUST exit 0 on the same run it prints a decision. hookyard discards
# the stdout of a handler that exits non-zero and records it as an abstain, so
# a `set -euo pipefail` script that prints its deny and then fails on a later
# line keeps printing and silently stops enforcing. Every guard here therefore
# ends on its `jq -n`; append nothing after it.
#
# `additionalContext` reaches the model on Claude Code either way. On pi it
# rides a denial's reason and has no standalone channel (noamsto/hookyard#72),
# so an advisory-only guard is silent there.
#
# `permissionDecision: "ask"` is a hard block on pi, not a prompt: pi's channel
# is binary, so hookyard degrades ask to deny. Claude Code still prompts. That
# makes ../claude-code/psql-guard.sh's destructive-psql branch unrunnable from
# pi, and unlike ./tmux-live-server-guard.sh (LIVE_TMUX=1) and
# ./git-default-branch-guard.sh (ALLOW_COMMIT_ON_DEFAULT=1) it has no env
# opt-in to reach for.
#
# Imported as a function, NOT a home-manager module:
#   import ../agent-hooks {inherit pkgs;}
# Do not add ./agent-hooks to ../default.nix's `imports`.
{pkgs}: {
  git-default-branch-guard =
    pkgs.writeShellScriptBin "agent-git-default-branch-guard"
    (builtins.readFile ./git-default-branch-guard.sh);

  nix-stage-guard =
    pkgs.writeShellScriptBin "agent-nix-stage-guard"
    (builtins.readFile ./nix-stage-guard.sh);

  git-commit-autostage-guard =
    pkgs.writeShellScriptBin "agent-git-commit-autostage-guard"
    (builtins.readFile ./git-commit-autostage-guard.sh);

  secret-read-guard =
    pkgs.writeShellScriptBin "agent-secret-read-guard"
    (builtins.readFile ./secret-read-guard.sh);

  tmux-live-server-guard =
    pkgs.writeShellScriptBin "agent-tmux-live-server-guard"
    (builtins.readFile ./tmux-live-server-guard.sh);
}
