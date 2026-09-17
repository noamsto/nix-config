{
  lib,
  config,
  inputs,
  pkgs,
  ...
}: let
  inherit (lib) mkEnableOption mkOption mkIf types genAttrs optionalAttrs;
  cfg = config.services.jellyfinHost;
  decl = cfg.declarative;

  # Raw Jellarr API key -> systemd environment file. /run is tmpfs, so the key
  # service rewrites this on every boot before the sync service reads it.
  jellarrEnvFile = "/run/jellarr/env";

  httpPorts = [8096 8920];
  # Clients broadcast on 7359/udp to find the server; 1900/udp is the DLNA/SSDP
  # side. Neither crosses a tailnet, so they only ever open on the LAN.
  discoveryPorts = [1900 7359];
in {
  imports = [inputs.jellarr.nixosModules.default];

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

    declarative = {
      enable = mkEnableOption "declarative Jellyfin configuration via Jellarr";

      apiKeySecret = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to the agenix secret holding the Jellarr API key as its raw
          value. The key is inserted into Jellyfin's database on first sync and
          exported to Jellarr through an environment file.
        '';
      };

      libraries = mkOption {
        type = types.listOf (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Library name as shown in Jellyfin.";
            };
            collectionType = mkOption {
              type = types.enum [
                "movies"
                "tvshows"
                "music"
                "musicvideos"
                "homevideos"
                "boxsets"
                "books"
                "mixed"
              ];
              description = "Jellyfin collection type.";
            };
            path = mkOption {
              type = types.str;
              description = "Absolute path to the library's media folder.";
            };
          };
        });
        default = [];
        description = ''
          Libraries to ensure exist. Jellarr only creates missing ones and never
          removes; a library that already exists is left alone (updates are a
          separate, currently buggy upstream path, so declare existing
          libraries as they are).
        '';
      };

      users = mkOption {
        type = types.listOf (types.submodule {
          options = {
            name = mkOption {
              type = types.str;
              description = "Jellyfin username.";
            };
            passwordSecret = mkOption {
              type = types.path;
              description = ''
                Path to the agenix secret holding the user's password. Jellarr
                only reads it when creating the user; it never resets an
                existing user's password (upstream FR #51).
              '';
            };
            administrator = mkOption {
              type = types.bool;
              default = false;
              description = "Whether the user is an administrator.";
            };
          };
        });
        default = [];
        description = ''
          Users to declare. Existing users only get their policy reconciled;
          the password is consumed at creation time so a from-scratch install
          recreates the account.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !decl.enable || decl.apiKeySecret != null;
        message = "services.jellyfinHost.declarative.apiKeySecret must be set when declarative config is enabled.";
      }
    ];

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

    # Runs under the sync service rather than at boot: it is a no-op once the
    # key row exists, so the timer re-checks daily without touching Jellyfin.
    systemd.services.jellarr-key = mkIf decl.enable {
      description = "Provision the Jellarr API key into Jellyfin and export it";
      path = [pkgs.coreutils pkgs.sqlite pkgs.systemd];
      after = ["jellyfin.service"];
      before = ["jellarr.service"];
      requiredBy = ["jellarr.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        key="$(tr -d '[:space:]' < ${decl.apiKeySecret})"

        install -d -m 0750 -o jellyfin -g jellyfin /run/jellarr
        printf 'JELLARR_API_KEY=%s\n' "$key" > ${jellarrEnvFile}
        chown jellyfin:jellyfin ${jellarrEnvFile}
        chmod 0600 ${jellarrEnvFile}

        db="${config.services.jellyfin.dataDir}/data/jellyfin.db"
        [ -e "$db" ] || exit 0

        if ${pkgs.sqlite}/bin/sqlite3 "$db" \
          "SELECT 1 FROM ApiKeys WHERE Name='jellarr' LIMIT 1;" | grep -q 1; then
          exit 0
        fi

        # Jellyfin reads API keys from memory, so the row only takes effect
        # after a restart. Always bring it back, even if the insert fails.
        trap 'systemctl start jellyfin.service || true' EXIT
        systemctl stop jellyfin.service || true
        ${pkgs.sqlite}/bin/sqlite3 "$db" \
          "INSERT INTO ApiKeys (AccessToken, Name, DateCreated, DateLastActivity) VALUES ('$key', 'jellarr', datetime('now'), datetime('now'));"
      '';
    };

    services.jellarr = mkIf decl.enable {
      enable = true;
      user = "jellyfin";
      group = "jellyfin";
      environmentFile = jellarrEnvFile;

      config =
        {
          version = 1;
          base_url = "http://localhost:8096";

          # jellarr's runtime Zod schema requires `system`, even though the Nix
          # module declares it nullable and omits it when unset. An empty object
          # is a no-op: the diff renders every current field as a removal, and
          # removals are filtered.
          system = {};

          # VCN 4.0 on the 8060S: VAAPI decode plus HEVC Main10/AV1 encode.
          # Jellyfin only hardware-decodes h264 by default, so 4K HEVC was
          # falling back to CPU decode; name every codec the GPU supports and
          # enable 10/12-bit HEVC explicitly (the library is HDR Main 10).
          encoding = {
            enableHardwareEncoding = true;
            hardwareAccelerationType = "vaapi";
            vaapiDevice = "/dev/dri/renderD128";
            hardwareDecodingCodecs = ["h264" "hevc" "mpeg2video" "vc1" "vp8" "vp9" "av1"];
            enableDecodingColorDepth10Hevc = true;
            enableDecodingColorDepth10HevcRext = true;
            enableDecodingColorDepth12HevcRext = true;

            # Without this Jellyfin "tone maps" by relabelling frames as bt709,
            # which leaves HDR looking washed out. VPP is the AMD path.
            enableTonemapping = true;
            enableVppTonemapping = true;
            tonemappingAlgorithm = "bt2390";
          };
        }
        // optionalAttrs (decl.libraries != []) {
          library.virtualFolders =
            map (library: {
              inherit (library) name collectionType;
              libraryOptions.pathInfos = [{inherit (library) path;}];
            })
            decl.libraries;
        }
        // optionalAttrs (decl.users != []) {
          users =
            map (user: {
              inherit (user) name;
              passwordFile = user.passwordSecret;
              policy.isAdministrator = user.administrator;
            })
            decl.users;
        };
    };
  };
}
