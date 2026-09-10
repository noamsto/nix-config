{
  pkgs,
  lib,
  ...
}: let
  guards = import ../agent-hooks {inherit pkgs;};

  # Deny guards first, advisory last: hook-bridge.ts stops at the first deny, so
  # a blocked call shouldn't also spend time on advice it will never show.
  hookPaths = lib.concatStringsSep ":" [
    "${guards.git-default-branch-guard}/bin/agent-git-default-branch-guard"
    "${guards.nix-stage-guard}/bin/agent-nix-stage-guard"
    "${guards.git-commit-autostage-guard}/bin/agent-git-commit-autostage-guard"
    "${guards.tmux-live-server-guard}/bin/agent-tmux-live-server-guard"
  ];

  # pi rewrites ~/.pi/agent/settings.json itself, so nix can't own it. The
  # read-only layer rides on the CLI resource flags instead.
  #
  # exec -a pi: argv[0] so ps and tmux show `pi`, not the store wrapper.
  pi-wrapper = pkgs.writeShellScriptBin "pi" ''
    export PI_AGENT_HOOKS="${hookPaths}"
    exec -a pi ${pkgs.pi}/bin/pi -e ${./hook-bridge.ts} "$@"
  '';
in {
  # llm-agents only builds pi on Linux.
  home.packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [pi-wrapper];
}
