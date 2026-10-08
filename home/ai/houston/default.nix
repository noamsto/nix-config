{
  config,
  lib,
  osConfig,
  pkgs,
  inputs,
  ...
}: let
  isHalo = osConfig.hostname == "halo";
  enabled = osConfig.agentDashboard.enable;
  # houston only trusts Host values it can derive itself; the tsnet node's
  # name is not one of them.
  hostnameArgs = lib.optionals (osConfig.services.localProxy.tailscale.enable or false) ["-hostname" osConfig.services.localProxy.tailscale.fqdn];
  houstonPkg = inputs.houston.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Picks dev vs pinned at process start, so `houston-dev on/off` needs no
  # rebuild. No runtimeInputs: they would prepend to houston.service's PATH.
  launcher = pkgs.writeShellApplication {
    name = "houston";
    text = ''
      dev_dir="''${HOUSTON_DEV_DIR:-''${XDG_STATE_HOME:-$HOME/.local/state}/houston/dev}"
      if [[ -e "$dev_dir/enabled" && -x "$dev_dir/current/bin/houston" ]]; then
        exec "$dev_dir/current/bin/houston" "$@"
      fi
      exec ${houstonPkg}/bin/houston "$@"
    '';
  };

  # Passes hookyard's normalized envelope straight to houston: houston
  # detects the envelope by its `engine` field and reads the event from
  # `canonical_event`/`native_event` itself, so no reshaping is needed here.
  # `houston hook` always exits 0. Stdout is redirected away even though
  # houston never writes to it today: the pre_tool handler below runs in the
  # verdict lane, where hookyard parses a handler's stdout as a potential
  # Allow/Ask/Deny decision, so a future houston version growing a stray
  # stdout line must not be able to start influencing that classification.
  bridge = pkgs.writeShellApplication {
    name = "houston-hookyard-bridge";
    # The hook writer must run the same build as the server reading its state.
    runtimeInputs = [launcher];
    text = ''
      houston hook >/dev/null || true
    '';
  };

  # houston's own `EventXxx` constants (houston/hook/hook.go) are Claude
  # Code's native hook names. `session_start`/`pre_tool`/`post_tool`/`turn_end`
  # (= Stop) are hookyard's canonical events; `Notification` and `SessionEnd`
  # have no canonical equivalent, so they ride engine-scoped. `prompt_submit`
  # is included too: houston's `apply()` treats UserPromptSubmit as a new
  # turn starting (state -> thinking, Turn++). `pre_compact` and
  # `pi:session_shutdown`, `pi:agent_settled`, and the engine-scoped session
  # ends are added to the observe set. A pi session has no canonical
  # SessionEnd, so `pi:session_shutdown` is engine-scoped and, without it, a
  # pi session that exits stays "waiting" forever in Fleet. `pi:agent_settled`
  # is pi's final "run settled" signal: houston treats every pi `turn_end` as
  # intermediate, so without it a pi run stays "thinking" after its last turn.
  # `codex:SessionEnd` and `cursor:sessionEnd` are engine-scoped like Claude
  # Code's own SessionEnd because neither engine has a canonical equivalent;
  # houston maps all three session ends to ended and pi `agent_settled` to
  # waiting.
  #
  # `pre_tool` is the only event with a decision slot (hookyard's
  # internal/verdict.HasDecisionSlot), and houston's pi turn_end rule depends
  # on pre_tool landing synchronously, so it alone runs in the verdict lane
  # across all engines; the rest run `fire_and_forget`.
  manifest = pkgs.writeText "houston-hookyard.json" (builtins.toJSON {
    handlers = [
      {
        id = "houston.state";
        exec = "${bridge}/bin/houston-hookyard-bridge";
        events = ["pre_tool"];
        engines = ["claude-code" "codex" "cursor" "pi"];
        match = [];
        timeout_ms = 1000;
      }
      {
        id = "houston.state.observe";
        exec = "${bridge}/bin/houston-hookyard-bridge";
        events = [
          "session_start"
          "prompt_submit"
          "post_tool"
          "turn_end"
          "pre_compact"
          "claude-code:Notification"
          "claude-code:SessionEnd"
          "codex:SessionEnd"
          "cursor:sessionEnd"
          "pi:session_shutdown"
          "pi:agent_settled"
        ];
        engines = ["claude-code" "codex" "cursor" "pi"];
        match = [];
        lane = "fire_and_forget";
      }
    ];
  });

  sync = pkgs.writeShellApplication {
    name = "houston-dev-sync";
    runtimeInputs = [pkgs.git pkgs.coreutils osConfig.nix.package pkgs.systemd];
    text =
      ''
        nixpkgs_src=${inputs.nixpkgs}
      ''
      + builtins.readFile ./houston-dev-common.sh
      + builtins.readFile ./houston-dev-sync.sh;
  };

  cli = pkgs.writeShellApplication {
    name = "houston-dev";
    runtimeInputs = [pkgs.git pkgs.coreutils pkgs.systemd];
    text =
      ''
        pinned=${houstonPkg}
        pinned_rev=${inputs.houston.rev or "unknown"}
      ''
      + builtins.readFile ./houston-dev-common.sh
      + builtins.readFile ./houston-dev.sh;
  };
in {
  programs.hookyard.manifests = lib.mkIf enabled [manifest];

  systemd.user = lib.mkMerge [
    (lib.mkIf enabled {
      services.houston = {
        Unit = {
          Description = "Houston - mission control for AI coding agents in tmux";
          # tmux-startup.service brings up the user's tmux server (and its
          # control socket); houston needs that socket to exist before it can
          # talk to tmux in control mode.
          After = ["tmux-startup.service"];
          Wants = ["tmux-startup.service"];
        };

        Service = {
          ExecStart = lib.concatStringsSep " " (["${launcher}/bin/houston"] ++ hostnameArgs);
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [
            # tmuxPackage first: houston must see the same tmux binary version
            # the user's tmux server runs, or control mode breaks on a
            # client/server version mismatch.
            #
            # The Dispatch tab execs `dispatch` by PATH lookup, and dispatch
            # itself resolves `wt`/`gh`/`direnv` from ambient PATH rather than
            # wrapping them (dispatcher flake.nix).
            "PATH=${lib.makeBinPath [
              config.programs.tmux-og.tmuxPackage
              pkgs.git
              pkgs.gh
              pkgs.worktrunk
              pkgs.direnv
              inputs.dispatcher.packages.${pkgs.stdenv.hostPlatform.system}.crew
              inputs.dispatcher.packages.${pkgs.stdenv.hostPlatform.system}.dispatch
            ]}"
            # Matches tmux-startup.service's own TMUX_TMPDIR=%t, so both resolve
            # the same runtime dir (/run/user/1000) and therefore the same socket.
            "TMUX_TMPDIR=%t"
          ];
        };

        # Same switch tmux-startup uses for `headless`: on a desktop host the
        # lingering user manager would otherwise pull tmux-startup (and
        # graphical-session.target with it) up at boot, before the compositor.
        Install.WantedBy = [
          (
            if osConfig.machine.serverMode or false
            then "default.target"
            else "graphical-session.target"
          )
        ];
      };
    })

    (lib.mkIf isHalo {
      services.houston-dev-sync = {
        Unit.Description = "Build and deploy github:noamsto/houston main when houston dev mode is on";
        Service = {
          Type = "oneshot";
          ExecStart = "${sync}/bin/houston-dev-sync";
          # oneshot has no start timeout by default; a stalled fetch would keep
          # the unit "activating" and the timer could never fire it again.
          TimeoutStartSec = "30min";
        };
      };

      # Always on; the sync no-ops while dev mode is off. HM owns the timer's
      # wants links, so `houston-dev` could not enable it at runtime.
      timers.houston-dev-sync = {
        Unit.Description = "Poll github:noamsto/houston main for houston dev mode";
        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = "2min";
        };
        Install.WantedBy = ["timers.target"];
      };
    })
  ];

  home.packages = lib.mkIf isHalo [cli];
}
