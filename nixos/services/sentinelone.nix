{
  lib,
  pkgs,
  config,
  inputs,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types optionalString getExe;
  cfg = config.services.sentinelone;

  # Stock .deb layout: /opt/sentinelone has real files (not symlinks into
  # /nix/store). The agent reads /proc/PID/exe via its eBPF probe and refuses
  # anything whose canonical path isn't under /opt/sentinelone/bin/ — so the
  # binaries have to live on the host filesystem, not be bind-mounted or
  # symlinked from the package.
  initScript = pkgs.writeShellScriptBin "sentinelone-init.sh" ''
    set -eu

    # One-shot migration from the previous module layout (dataDir was
    # /var/lib/sentinelone, /opt/sentinelone was a symlink). Preserves the
    # registered agent UUID and certs instead of re-registering fresh.
    if [ -L /opt/sentinelone ]; then
      rm -f /opt/sentinelone
      mv /var/lib/sentinelone /opt/sentinelone
    fi

    mkdir -p ${cfg.dataDir}

    # Earlier iterations of this module left bin/ebpfs/ranger as symlinks into
    # /nix/store; rsync would follow them and fail. Drop them before sync.
    for sub in bin ebpfs ranger; do
      if [ -L "${cfg.dataDir}/$sub" ]; then
        rm -f "${cfg.dataDir}/$sub"
      fi
    done
    mkdir -p ${cfg.dataDir}/bin

    # Refresh binaries from the package on every init (cheap; required after
    # package upgrades). Real files, not symlinks, so /proc/PID/exe matches.
    ${pkgs.rsync}/bin/rsync -a --delete \
      ${cfg.package}/opt/sentinelone/bin/ \
      ${cfg.dataDir}/bin/
    ${pkgs.rsync}/bin/rsync -a --delete \
      ${cfg.package}/opt/sentinelone/ebpfs/ \
      ${cfg.dataDir}/ebpfs/
    ${pkgs.rsync}/bin/rsync -a --delete \
      ${cfg.package}/opt/sentinelone/ranger/ \
      ${cfg.dataDir}/ranger/

    if [ ! -f "${cfg.dataDir}/configuration/install_config" ]; then
      find "${cfg.package}/opt/sentinelone/" -mindepth 1 -maxdepth 1 \
        ! -name "bin" ! -name "ebpfs" ! -name "ranger" \
        -exec cp -r {} "${cfg.dataDir}/" \;

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
    fi

    chown -R sentinelone:sentinelone ${cfg.dataDir}
    find ${cfg.dataDir} -group sentinelone -exec chmod 0755 {} +
  '';

  # Thin wrapper so `sentinelctl` is in PATH. Exec's the real binary at
  # /opt/sentinelone/bin/sentinelctl, giving /proc/PID/exe the path the
  # agent's signature check expects.
  sentinelctlWrapper = pkgs.writeShellScriptBin "sentinelctl" ''
    exec ${cfg.dataDir}/bin/sentinelctl "$@"
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
      description = ''
        Runtime directory for the agent. Must be /opt/sentinelone — the
        shipped binaries hardcode this path and the agent's signature
        check rejects anything else.
      '';
      default = "/opt/sentinelone";
      readOnly = true;
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

    systemd.services.sentinelone-init = {
      wantedBy = ["sentinelone.service"];
      before = ["sentinelone.service"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = getExe initScript;
      };
    };

    systemd.services.sentinelone = {
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
        ExecStart = "${cfg.dataDir}/bin/sentinelone-agent";
        WorkingDirectory = "${cfg.dataDir}/bin";
        SyslogIdentifier = "${cfg.dataDir}/log";
        WatchdogSec = "30s";
        Restart = "on-failure";
        RestartSec = "4";
        MemoryMax = "infinity";
        ExecStop = "${cfg.dataDir}/bin/sentinelctl control stop";
        NotifyAccess = "all";
        KillMode = "process";
        TasksMax = "infinity";
      };
      wantedBy = ["multi-user.target"];
    };
  };
}
