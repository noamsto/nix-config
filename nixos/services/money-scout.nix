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

  watch = pkgs.writeShellApplication {
    name = "money-scout-watch";
    runtimeInputs = [pkgs.nix pkgs.git pkgs.coreutils];
    text = ''
      cd ${lib.escapeShellArg cfg.repoDir}
      # A checkout update can add dependencies; install only when the lockfile moved.
      if [ ! node_modules/.package-lock.json -nt package-lock.json ]; then
        nix develop --command npm ci --no-audit --no-fund
      fi
      exec nix develop --command ./bin/money scout watch --write
    '';
  };

  relay = pkgs.writeShellApplication {
    name = "scout-relay";
    runtimeInputs = [pkgs.jq pkgs.coreutils];
    text = ''
      job="''${1:?usage: scout-relay <job>}"
      dir=${lib.escapeShellArg cfg.reportDir}
      today="$(TZ=Asia/Jerusalem date +%F)"
      if [ ! -r "$dir/status.json" ]; then
        echo "scout $job: no status file — the $job timer has never run"
        exit 1
      fi
      if ! jq -e --arg j "$job" --arg d "$today" '.[$j].ok == true and .[$j].date == $d' "$dir/status.json" >/dev/null; then
        reason="$(jq -r --arg j "$job" '.[$j].error // "no run today"' "$dir/status.json")"
        echo "scout $job failed: $reason"
        exit 1
      fi
      cat "$dir/$job.txt"
    '';
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
    relayScript = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = relay;
      description = "Prints the day's report for a job (`scout-relay watch`), or fails loudly.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.money-scout = {};
    users.users.${cfg.user}.extraGroups = ["money-scout"];

    systemd = {
      tmpfiles.rules = ["d ${cfg.reportDir} 2750 ${cfg.user} money-scout - -"];

      user.services.money-scout-watch = {
        description = "portfolio-agent: check IPS rules and write the scout report";
        unitConfig.ConditionUser = cfg.user;
        environment.MONEY_SCOUT_DIR = cfg.reportDir;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${watch}/bin/money-scout-watch";
          TimeoutStartSec = "20min";
        };
      };

      user.timers.money-scout-watch = {
        description = "Daily scout watch before the US open";
        unitConfig.ConditionUser = cfg.user;
        wantedBy = ["timers.target"];
        # Not Persistent: a catch-up run at boot would mark alerts as sent with
        # no relay after it. A missed day surfaces as the relay's "no run today".
        timerConfig = {
          OnCalendar = "Mon..Fri *-*-* 15:15:00 Asia/Jerusalem";
        };
      };
    };
  };
}
