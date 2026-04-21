{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types optionalString getExe;
  cfg = config.services.sentinelone;

  # The agent verifies /proc/PID/exe of anything connecting to its control
  # socket and rejects binaries outside /opt/sentinelone/bin/. Inside the
  # service's mount namespace that path is a bind-mount from the package, so
  # we run sentinelctl via nsenter to join that namespace first.
  sentinelctlWrapper = pkgs.writeShellApplication {
    name = "sentinelctl";
    runtimeInputs = [pkgs.procps pkgs.util-linux];
    text = ''
      pid=$(pgrep -f 's1-orchestrator' | head -n1)
      if [ -z "''${pid}" ]; then
        echo "sentinelone service not running" >&2
        exit 1
      fi
      exec nsenter -m -t "$pid" -- /opt/sentinelone/bin/sentinelctl "$@"
    '';
  };

  initScript = pkgs.writeShellScriptBin "sentinelone-init.sh" ''
    mkdir -p ${cfg.dataDir}

    if [ ! -f "${cfg.dataDir}/configuration/install_config" ]; then
      find "${cfg.package}/opt/sentinelone/" -mindepth 1 -maxdepth 1 ! -name "bin" ! -name "ebpfs" ! -name "ranger" -exec cp -r {} "${cfg.dataDir}/" \;

      cat << EOF > ${cfg.dataDir}/configuration/install_config
    S1_AGENT_MANAGEMENT_TOKEN=$(cat ${cfg.sentinelOneManagementTokenPath})
    S1_AGENT_DEVICE_TYPE=desktop
    S1_AGENT_AUTO_START=true
    ${optionalString (cfg.customerId != null) "S1_AGENT_CUSTOMER_ID=${cfg.customerId}"}
    EOF

      cat << EOF > ${cfg.dataDir}/configuration/installation_params.json
    {
      "PACKAGE_TYPE": "deb",
      "SERVICE_TYPE": "systemd"
    }
    EOF

      decoded=$(base64 -d < ${cfg.sentinelOneManagementTokenPath})
      siteKey=$(printf %s "$decoded" | ${getExe pkgs.jq} .site_key)
      mgmtUrl=$(printf %s "$decoded" | ${getExe pkgs.jq} .url)
      cat << EOF > ${cfg.dataDir}/configuration/basic.conf
    {
        "mgmt_device-type": 1,
        "mgmt_site-key": $siteKey,
        "mgmt_url": $mgmtUrl
    }
    EOF

      chown -R sentinelone:sentinelone ${cfg.dataDir}
      find ${cfg.dataDir} -group sentinelone -exec chmod 0755 {} +
    fi
  '';
in {
  options.services.sentinelone = {
    enable = mkEnableOption "SentinelOne Service";

    package = mkOption {
      type = types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.sentinelone;
      description = "The SentinelOne package to use.";
    };

    customerId = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Customer-specific identifier for the host. Common practice is
        <email>-<serial-number>.
      '';
      example = "me@example.com-FTXYZWW";
    };

    sentinelOneManagementTokenPath = mkOption {
      type = types.path;
      description = ''
        Path to the file containing the SentinelOne management/site token.
        Use a secret manager such as agenix — e.g.
        config.age.secrets.sentinelone-token.path.
      '';
      example = "/run/agenix/sentinelone-token";
    };

    dataDir = mkOption {
      type = types.path;
      description = "Directory in which the agent stores its runtime data.";
      default = "/var/lib/sentinelone";
    };
  };

  config = mkIf cfg.enable {
    users.users.sentinelone = {
      isSystemUser = true;
      createHome = true;
      shell = "${pkgs.shadow}/bin/nologin";
      group = "sentinelone";
    };
    users.groups.sentinelone = {};

    environment.systemPackages = [sentinelctlWrapper];

    systemd = {
      services.sentinelone-init = {
        wantedBy = ["sentinelone.service"];
        before = ["sentinelone.service"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = getExe initScript;
        };
      };

      services.sentinelone = {
        description = "SentinelOne";
        path = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.zlib
          pkgs.elfutils
          pkgs.bash
        ];
        unitConfig = {
          Description = "SentinelOne";
          After = ["uptrack-prefetch.service" "uptrack.service"];
          RefuseManualStop = "yes";
          StartLimitInterval = "90";
          StartLimitBurst = "4";
        };
        serviceConfig = {
          Type = "exec";
          ExecStart = "${cfg.package}/bin/sentinelone-agent";
          WorkingDirectory = "/opt/sentinelone/bin";
          SyslogIdentifier = "${cfg.dataDir}/log";
          WatchdogSec = "30s";
          Restart = "on-failure";
          RestartSec = "4";
          MemoryMax = "infinity";
          ExecStop = "${cfg.package}/bin/sentinelctl control stop";
          NotifyAccess = "all";
          KillMode = "process";
          TasksMax = "infinity";
          BindPaths = ["${cfg.dataDir}:/opt/sentinelone"];
          BindReadOnlyPaths = [
            "${cfg.package}/opt/sentinelone/bin:/opt/sentinelone/bin"
            "${cfg.package}/opt/sentinelone/ebpfs:/opt/sentinelone/ebpfs"
            "${cfg.package}/opt/sentinelone/ranger:/opt/sentinelone/ranger"
          ];
        };
        wantedBy = ["multi-user.target"];
      };
    };
  };
}
