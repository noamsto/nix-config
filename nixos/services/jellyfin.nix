{
  lib,
  config,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types genAttrs optionalAttrs;
  cfg = config.services.jellyfinHost;

  httpPorts = [8096 8920];
  # Clients broadcast on 7359/udp to find the server; 1900/udp is the DLNA/SSDP
  # side. Neither crosses a tailnet, so they only ever open on the LAN.
  discoveryPorts = [1900 7359];
in {
  options.services.jellyfinHost = {
    enable = mkEnableOption "Jellyfin media server with VAAPI hardware transcoding";

    mediaShare = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "192.168.3.6:/media/storage";
      description = ''
        NFS export mounted read-only as the media library. Read-only keeps the
        exporting host's *arr stack the sole writer, so its hardlinked imports
        stay intact.
      '';
    };

    mediaPath = mkOption {
      type = types.str;
      default = "/mnt/media";
      description = "Mount point for `mediaShare`.";
    };

    lanInterfaces = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["enp97s0"];
      description = ''
        Interfaces to expose Jellyfin's HTTP and discovery ports on. Empty means
        tailnet-only reach, since `tailscale0` is already a trusted interface.
      '';
    };
  };

  config = mkIf cfg.enable {
    services.jellyfin.enable = true;

    # renderD128 is world-readable today, but the render group is the documented
    # way in and survives a udev rule change.
    users.users.jellyfin.extraGroups = ["render" "video"];

    fileSystems = optionalAttrs (cfg.mediaShare != null) {
      ${cfg.mediaPath} = {
        device = cfg.mediaShare;
        fsType = "nfs";
        options = [
          "ro"
          "nfsvers=4.2"
          # Mount on first access rather than at boot: the exporting host is a
          # separate machine, and a hard dependency would stall boot whenever
          # it is down.
          "noauto"
          "x-systemd.automount"
          "x-systemd.idle-timeout=600"
          # soft: an unreachable server should fail the read, not park Jellyfin
          # in uninterruptible sleep the way the default hard mount would.
          "soft"
          "timeo=150"
        ];
      };
    };

    # Deliberately not services.jellyfin.openFirewall — that opens every
    # interface, including whatever untrusted wifi this host is on.
    networking.firewall.interfaces = genAttrs cfg.lanInterfaces (_: {
      allowedTCPPorts = httpPorts;
      allowedUDPPorts = discoveryPorts;
    });
  };
}
