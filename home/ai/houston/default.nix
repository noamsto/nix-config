{
  config,
  lib,
  osConfig,
  pkgs,
  inputs,
  ...
}: {
  systemd.user.services.houston = lib.mkIf (osConfig.hostname == "halo") {
    Unit = {
      Description = "Houston - mission control for AI coding agents in tmux";
      # tmux-startup.service brings up the user's tmux server (and its
      # control socket) on halo; houston needs that socket to exist before
      # it can talk to tmux in control mode.
      After = ["tmux-startup.service"];
      Wants = ["tmux-startup.service"];
    };

    Service = {
      ExecStart = "${inputs.houston.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/houston";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        # tmuxPackage first: houston must see the same tmux binary version
        # the user's tmux server runs, or control mode breaks on a
        # client/server version mismatch.
        "PATH=${lib.makeBinPath [
          config.programs.tmux-og.tmuxPackage
          pkgs.git
          inputs.dispatcher.packages.${pkgs.stdenv.hostPlatform.system}.crew
        ]}"
        # Matches tmux-startup.service's own TMUX_TMPDIR=%t, so both resolve
        # the same runtime dir (/run/user/1000) and therefore the same socket.
        "TMUX_TMPDIR=%t"
      ];
    };

    Install.WantedBy = ["default.target"];
  };
}
