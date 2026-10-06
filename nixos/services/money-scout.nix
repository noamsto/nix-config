# Daily portfolio scout (portfolio-agent). The watch runs as the repo owner,
# who holds the broker credentials, and writes plain reports to a shared dir;
# the Telegram relay (Hermes) only ever reads that dir.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.moneyScout;

  scoutJob = name: command:
    pkgs.writeShellApplication {
      name = "money-scout-${name}";
      runtimeInputs = [pkgs.nix pkgs.git pkgs.coreutils];
      text = ''
        cd ${lib.escapeShellArg cfg.repoDir}
        # A checkout update can add dependencies; install only when the lockfile moved.
        if [ ! node_modules/.package-lock.json -nt package-lock.json ]; then
          nix develop --command npm ci --no-audit --no-fund
        fi
        exec nix develop --command ./bin/money ${command}
      '';
    };

  watch = scoutJob "watch" "scout watch --write";
  crowd = scoutJob "crowd" "scout crowd --write";

  # op:// references, not secrets: op run resolves them with the service account.
  researchEnv = pkgs.writeText "money-research.env" ''
    CLAUDE_CODE_OAUTH_TOKEN="op://portfolio-agent/Claude research token/credential"
  '';

  research = pkgs.writeShellApplication {
    name = "money-scout-research";
    runtimeInputs = [pkgs._1password-cli pkgs.coreutils];
    text = ''
      OP_SERVICE_ACCOUNT_TOKEN="$(cat ${lib.escapeShellArg cfg.opTokenFile})"
      export OP_SERVICE_ACCOUNT_TOKEN
      # claude and the finnhub MCP server's bun come from the user's profile.
      export PATH="/etc/profiles/per-user/${cfg.user}/bin:$PATH"
      exec op run --env-file=${researchEnv} -- ${scoutJob "research-run" "scout research"}/bin/money-scout-research-run
    '';
  };

  relay = import ./money-scout-relay.nix {
    inherit pkgs lib;
    inherit (cfg) reportDir;
  };
in {
  options.services.moneyScout = {
    enable = lib.mkEnableOption "the portfolio-agent daily scout";
    user = lib.mkOption {
      type = lib.types.str;
      default = config.username;
      description = "Owner of the portfolio-agent checkout and its broker credentials.";
    };
    repoDir = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.user}/git/portfolio-agent";
    };
    reportDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/money-scout";
    };
    opTokenFile = lib.mkOption {
      type = lib.types.str;
      description = "File holding the portfolio-agent 1Password service-account token (owner only).";
    };
    relayScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = relay;
      description = "Prints the day's report for a job (`scout-relay watch`), or fails loudly.";
    };
    researchRelayScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = import ./money-scout-research-relay.nix {
        inherit pkgs lib;
        inherit (cfg) reportDir;
      };
      description = "Prints research reports and errors not yet relayed.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.money-scout = {};
    users.users.${cfg.user}.extraGroups = ["money-scout"];

    systemd = {
      tmpfiles.rules = [
        "d ${cfg.reportDir} 2750 ${cfg.user} money-scout - -"
        # hermes drops requests here: group-writable, sticky so it cannot delete
        # files it does not own; the runner (the dir owner) claims and removes them.
        "d ${cfg.reportDir}/requests 3770 ${cfg.user} money-scout - -"
        "d ${cfg.reportDir}/research 2750 ${cfg.user} money-scout - -"
      ];

      user = {
        services = {
          money-scout-watch = {
            description = "portfolio-agent: check IPS rules and write the scout report";
            unitConfig.ConditionUser = cfg.user;
            environment.MONEY_SCOUT_DIR = cfg.reportDir;
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${watch}/bin/money-scout-watch";
              TimeoutStartSec = "20min";
            };
          };

          money-scout-crowd = {
            description = "portfolio-agent: grade trending tickers and write the crowd digest";
            unitConfig.ConditionUser = cfg.user;
            environment.MONEY_SCOUT_DIR = cfg.reportDir;
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${crowd}/bin/money-scout-crowd";
              # Two thinking-model gradings, each allowed 30 min on the local server.
              TimeoutStartSec = "90min";
            };
          };

          money-scout-research = {
            description = "portfolio-agent: run queued Telegram research requests through Claude";
            unitConfig = {
              ConditionUser = cfg.user;
              # A failing runner stops after 3 starts instead of looping on its path unit.
              StartLimitIntervalSec = "5min";
              StartLimitBurst = 3;
            };
            environment = {
              MONEY_SCOUT_DIR = cfg.reportDir;
              CLAUDE_CONFIG_DIR = "%S/money-research/claude";
            };
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${research}/bin/money-scout-research";
              # Created under $XDG_STATE_HOME for a user unit, which %S also names.
              StateDirectory = "money-research/claude";
              # Worst case: about 6 min of snapshot, plus 2 requests at 10 min of
              # Claude each, plus npm ci and a devshell rebuild.
              TimeoutStartSec = "45min";
            };
          };
        };

        paths.money-scout-research = {
          description = "Start the research runner when a request arrives";
          unitConfig.ConditionUser = cfg.user;
          wantedBy = ["paths.target"];
          pathConfig.PathExistsGlob = "${cfg.reportDir}/requests/*.json";
        };

        timers = {
          money-scout-watch = {
            description = "Daily scout watch before the US open";
            unitConfig.ConditionUser = cfg.user;
            wantedBy = ["timers.target"];
            # Not Persistent: a catch-up run at boot would mark alerts as sent with
            # no relay after it. A missed day surfaces as the relay's "no run today".
            timerConfig = {
              OnCalendar = "Mon..Fri *-*-* 15:15:00 Asia/Jerusalem";
            };
          };

          money-scout-crowd = {
            description = "Daily crowd digest, before the 07:00 relay";
            unitConfig.ConditionUser = cfg.user;
            wantedBy = ["timers.target"];
            # 05:15: US after-hours earnings have settled, and the 105 minutes
            # to the 07:00 relay outlast the 90-minute timeout. Not Persistent: a
            # catch-up after the relay would spend Adanos quota on a digest no
            # relay ever posts.
            timerConfig = {
              OnCalendar = "Mon..Fri *-*-* 05:15:00 Asia/Jerusalem";
            };
          };
        };
      };
    };
  };
}
