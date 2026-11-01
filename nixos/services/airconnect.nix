{inputs, ...}: {
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types getExe' optionals concatStringsSep;
  cfg = config.services.airconnect;

  # airupnp and aircast each grab their own RTSP/RTP/HTTP window; overlapping
  # ranges make the second daemon fail to bind, so keep them disjoint.
  upnpPorts = {
    base = 49200;
    count = 64;
  };
  castPorts = {
    base = 49280;
    count = 64;
  };

  mkBridge = exe: ports: {
    description = "AirConnect ${exe} (→ AirPlay bridge)";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target" "avahi-daemon.service"];
    serviceConfig = {
      ExecStart = concatStringsSep " " (
        [
          (getExe' cfg.package exe)
          "-Z" # disable interactive mode, stay in foreground for systemd
          "-a ${toString ports.base}:${toString ports.count}"
          "-x %S/${exe}/config.xml"
        ]
        ++ optionals (cfg.interface != null) ["-b ${cfg.interface}"]
        ++ cfg.extraArgs
      );
      Restart = "on-failure";
      RestartSec = 30;
      DynamicUser = true;
      StateDirectory = exe;
      WorkingDirectory = "%S/${exe}";
    };
  };

  ranges = ports: [
    {
      from = ports.base;
      to = ports.base + ports.count;
    }
  ];
in {
  options.services.airconnect = {
    enable = mkEnableOption "AirConnect — bridge UPnP/Sonos & Chromecast devices to AirPlay";

    package = mkOption {
      type = types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.airconnect;
      defaultText = lib.literalExpression "inputs.self.packages.\${system}.airconnect";
      description = "The AirConnect package to use.";
    };

    upnp = mkOption {
      type = types.bool;
      default = true;
      description = "Run airupnp, bridging UPnP/DLNA/Sonos devices.";
    };

    chromecast = mkOption {
      type = types.bool;
      default = true;
      description = "Run aircast, bridging Chromecast/Google Cast devices.";
    };

    interface = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "192.0.2.50";
      description = "Network interface name or IP to bind to (airconnect -b). Null lets it auto-select.";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["-l" "1000:2000"];
      description = "Extra arguments passed to both bridges (e.g. `-l 1000:2000` latency for Sonos/Heos).";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Open the ports AirConnect needs: mDNS (5353/udp), the UPnP discovery
        port (49152/udp), and each bridge's RTSP/RTP/HTTP range. Speakers connect
        back *inbound* to fetch the audio stream, so these must be reachable.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.upnp || cfg.chromecast;
        message = "services.airconnect: enable at least one of `upnp` or `chromecast`.";
      }
    ];

    systemd.services =
      (lib.optionalAttrs cfg.upnp {airupnp = mkBridge "airupnp" upnpPorts;})
      // (lib.optionalAttrs cfg.chromecast {aircast = mkBridge "aircast" castPorts;});

    networking.firewall = mkIf cfg.openFirewall {
      allowedUDPPorts = [5353] ++ optionals cfg.upnp [49152];
      allowedTCPPortRanges =
        optionals cfg.upnp (ranges upnpPorts)
        ++ optionals cfg.chromecast (ranges castPorts);
      allowedUDPPortRanges =
        optionals cfg.upnp (ranges upnpPorts)
        ++ optionals cfg.chromecast (ranges castPorts);
    };
  };
}
