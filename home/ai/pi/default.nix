{
  pkgs,
  lib,
  ...
}: let
  guards = import ../agent-hooks {inherit pkgs;};

  # ../claude-code owns its own nix wiring for these scripts, so they're built
  # separately here rather than shared. Both scripts self-filter on
  # tool_name, so one guard list can serve pi's bash and read tool calls alike.
  skeleton-guard = pkgs.writeShellScriptBin "agent-read-skeleton-guard" (builtins.readFile ../claude-code/skeleton-guard.sh);
  psql-guard = pkgs.writeShellScriptBin "agent-psql-guard" (builtins.readFile ../claude-code/psql-guard.sh);

  # Deny guards first, advisory last: hook-bridge.ts stops at the first deny, so
  # a blocked call shouldn't also spend time on advice it will never show.
  hookPaths = lib.concatStringsSep ":" [
    "${guards.git-default-branch-guard}/bin/agent-git-default-branch-guard"
    "${guards.nix-stage-guard}/bin/agent-nix-stage-guard"
    "${skeleton-guard}/bin/agent-read-skeleton-guard"
    "${psql-guard}/bin/agent-psql-guard"
    "${guards.git-commit-autostage-guard}/bin/agent-git-commit-autostage-guard"
    "${guards.tmux-live-server-guard}/bin/agent-tmux-live-server-guard"
  ];

  # pi rewrites ~/.pi/agent/settings.json itself, so nix can't own it. The
  # read-only layer rides on the CLI resource flags instead.
  #
  # Skills and commands are the same catalogs Claude Code already consumes:
  # ~/.claude/skills is a flat dir of per-skill symlinks (locally-authored
  # skills, the agent-skills bundle, and out-of-store ones); ~/.claude/commands
  # is the shared repo dir. pi follows symlinked skill dirs, so this gives
  # exact skill parity without a second catalog to keep in sync. Additive to
  # pi's own ~/.pi/agent/skills and any project .pi/skills / .agents/skills.
  #
  # exec -a pi: argv[0] so ps and tmux show `pi`, not the store wrapper.
  pi-wrapper = pkgs.writeShellScriptBin "pi" ''
    export PI_AGENT_HOOKS="${hookPaths}"
    exec -a pi ${pkgs.pi}/bin/pi \
      -e ${./hook-bridge.ts} \
      --skill "$HOME/.claude/skills" \
      --prompt-template "$HOME/.claude/commands" \
      "$@"
  '';
in {
  # llm-agents only builds pi on Linux.
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [pi-wrapper];
}
