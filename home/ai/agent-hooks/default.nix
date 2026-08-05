# Engine-neutral tool-call guards. Claude Code wires them as `hooks.PreToolUse`
# (see ../claude-code); pi runs them through ../pi/hook-bridge.ts.
#
# Protocol (Claude Code's PreToolUse contract, which the pi bridge also speaks):
# read a JSON payload on stdin carrying `tool_name`, `tool_input`, and `cwd`;
# write a `hookSpecificOutput` decision on stdout, or exit 0 silently to
# abstain. `permissionDecision: "deny"` blocks; `additionalContext` is advisory.
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
}
