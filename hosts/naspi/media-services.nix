{
  config,
  pkgs,
  ...
}: let
  # Arr services configuration script
  arr-setup-script = pkgs.writeShellApplication {
    name = "arr-setup";
    runtimeInputs = with pkgs; [curl jq gnugrep coreutils];
    text = builtins.readFile ./arr-setup.sh;
  };
in {
  # Create media group for shared access
  users.groups.media = {
    gid = 985; # Avoid conflict with nscd (995)
  };

  # Add noams user to media group
  users.users.noams.extraGroups = ["media"];

  # Transmission BitTorrent daemon
  services.transmission = {
    enable = true;
    user = "transmission";
    group = "media";
    home = "/var/lib/transmission";
    settings = {
      # Web interface settings
      rpc-enabled = true;
      rpc-bind-address = "0.0.0.0";
      rpc-port = 9091;
      rpc-whitelist-enabled = false;
      # Basic auth for RPC (Flood, Sonarr, Radarr)
      # Password will be automatically hashed by Transmission on first start
      rpc-authentication-required = true;
      rpc-username = "transmission";
      rpc-password = "transmission";

      # Download settings - TRaSH Guides structure
      # On same filesystem as /media/storage for hardlink support
      download-dir = "/media/torrents/complete";
      incomplete-dir-enabled = true;
      incomplete-dir = "/media/torrents/incomplete";
      watch-dir-enabled = true;
      watch-dir = "/media/torrents/watch";

      # Performance settings
      peer-limit-global = 200;
      peer-limit-per-torrent = 50;
      speed-limit-up-enabled = false;
      speed-limit-down-enabled = false;

      # File permissions for hardlinks (must be integer, not string)
      umask = 2; # Creates files as 664 (rw-rw-r--), directories as 775
    };
  };

  # Sonarr - TV show automation
  services.sonarr = {
    enable = true;
    group = "media";
    openFirewall = true;
    settings = {
      update = {
        mechanism = "external"; # Updates managed by NixOS
        automatically = false; # Disable built-in auto-update
      };
    };
  };

  # Radarr - Movie automation
  services.radarr = {
    enable = true;
    group = "media";
    openFirewall = true;
    settings = {
      update = {
        mechanism = "external"; # Updates managed by NixOS
        automatically = false; # Disable built-in auto-update
      };
    };
  };

  # Prowlarr - Indexer manager
  services.prowlarr = {
    enable = true;
    openFirewall = true;
  };

  # Bazarr - Subtitle manager
  services.bazarr = {
    enable = true;
    group = "media";
    listenPort = 6767;
    openFirewall = true;
  };
  # Note: Bazarr requires manual configuration via web UI:
  # 1. Navigate to http://naspi:6767
  # 2. Settings > Languages > Add Hebrew (he) as subtitle language
  # 3. Settings > Sonarr > Add connection (http://localhost:8989)
  # 4. Settings > Radarr > Add connection (http://localhost:7878)
  # 5. Settings > Providers > Add subtitle providers (OpenSubtitles, etc.)

  # Flood - Modern Web UI for Transmission
  services.flood = {
    enable = true;
    host = "0.0.0.0";
    port = 3000;
    openFirewall = true;
  };

  # Create TRaSH Guides compliant directory structure
  # All on rpool/media for hardlink support (same filesystem)
  systemd.tmpfiles.rules = [
    # Torrent directories (download client) - managed by ZFS dataset rpool/media/torrents
    "d /media/torrents 0775 transmission media - -"
    "d /media/torrents/complete 0775 transmission media - -"
    "d /media/torrents/incomplete 0775 transmission media - -"
    "d /media/torrents/watch 0775 transmission media - -"

    # Torrent category subdirectories
    "d /media/torrents/complete/tv 0775 transmission media - -"
    "d /media/torrents/complete/movies 0775 transmission media - -"
    "d /media/torrents/complete/music 0775 transmission media - -"

    # Media library directories (Plex/Jellyfin/Emby) - on rpool/media
    "d /media/storage/tv 0775 root media - -"
    "d /media/storage/movies 0775 root media - -"
    "d /media/storage/music 0775 root media - -"

    # Recyclarr config symlink
    "L+ /var/lib/recyclarr/recyclarr.yml - - - - /etc/recyclarr/recyclarr.yml"
  ];

  # Network configuration for services
  networking.firewall.allowedTCPPorts = [
    9091 # Transmission RPC
    # 3000 - Flood (opened by services.flood.openFirewall)
  ];

  # Additional packages for media management
  environment.systemPackages = with pkgs; [
    transmission-remote-gtk # GUI client
    mediainfo # Media file information
    ffmpeg # Media processing
    unrar # RAR extraction
    p7zip # Archive extraction
    recyclarr # TRaSH Guides sync tool
  ];

  # Recyclarr - TRaSH Guides automation
  services.recyclarr = {
    enable = true;
    group = "media";
    schedule = "daily";

    configuration = {
      radarr.movies-4k = {
        base_url = "http://localhost:7878";
        api_key._secret = "/var/lib/recyclarr/.env-radarr-api-key";

        quality_definition.type = "movie";

        quality_profiles = [
          {
            name = "4K + HD Fallback";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "Remux-2160p";
              until_score = 10000;
            };
            min_format_score = 0;
            quality_sort = "top";
            qualities = [
              # 4K qualities (preferred)
              {name = "Remux-2160p";}
              {
                name = "WEB 2160p";
                qualities = ["WEBDL-2160p" "WEBRip-2160p"];
              }
              {name = "Bluray-2160p";}
              # 1080p qualities (fallback)
              {name = "Remux-1080p";}
              {
                name = "WEB 1080p";
                qualities = ["WEBDL-1080p" "WEBRip-1080p"];
              }
              {name = "Bluray-1080p";}
            ];
          }
        ];

        custom_formats = [
          # TrueHD Atmos (lossless)
          {
            trash_ids = ["1af239278386be2919e1bcee0bde047e"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 9000;
              }
            ];
          }
          # DD+ Atmos (streaming, compatible with Q800D)
          {
            trash_ids = ["417804f7f2c4308c1f4c5d380d4c4475"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 8500;
              }
            ];
          }
          # DTS:X
          {
            trash_ids = ["3cafb66171b47f226146a0770576870f"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 8000;
              }
            ];
          }
          # TrueHD (lossless 5.1/7.1)
          {
            trash_ids = ["496f355514737f7d83bf7aa4d24f8169"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 7000;
              }
            ];
          }
          # DTS-HD MA (lossless 5.1/7.1)
          {
            trash_ids = ["2f22d89048b01681dde8afe203bf2e95"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 6500;
              }
            ];
          }
          # DD+ 5.1 / DTS 5.1 (standard fallback)
          {
            trash_ids = ["185f1dd7264c4562b9022d963ac37424" "1c1a4c5e823891c75bc50380a6866f73"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 500;
              }
            ];
          }
          # HDR Formats
          {
            trash_ids = ["e23edd2482476e595fb990b12e7c609c" "b974a6cd08c1066250f1f177d7aa1225" "dfb86d5941bc9075d6af23b09c2aeecd"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 5000;
              }
            ];
          }
          # Unwanted
          {
            trash_ids = ["ed38b889b31be83fda192888e2286d83" "90a6f9a284dff5103f6346090e6280c8" "b8cd450cbfa689c0259a01d9e29ba3d6"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = -10000;
              }
            ];
          }
        ];
      };

      sonarr.tv-4k = {
        base_url = "http://localhost:8989";
        api_key._secret = "/var/lib/recyclarr/.env-sonarr-api-key";

        quality_definition.type = "series";

        quality_profiles = [
          {
            name = "4K + HD Fallback";
            reset_unmatched_scores.enabled = true;
            upgrade = {
              allowed = true;
              until_quality = "WEB 2160p";
              until_score = 10000;
            };
            min_format_score = 0;
            quality_sort = "top";
            qualities = [
              # 4K qualities (preferred)
              {
                name = "WEB 2160p";
                qualities = ["WEBDL-2160p" "WEBRip-2160p"];
              }
              {name = "Bluray-2160p";}
              # 1080p qualities (fallback)
              {
                name = "WEB 1080p";
                qualities = ["WEBDL-1080p" "WEBRip-1080p"];
              }
              {name = "Bluray-1080p";}
            ];
          }
        ];

        custom_formats = [
          # TrueHD Atmos (lossless)
          {
            trash_ids = ["1af239278386be2919e1bcee0bde047e"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 9000;
              }
            ];
          }
          # DD+ Atmos (streaming, compatible with Q800D)
          {
            trash_ids = ["417804f7f2c4308c1f4c5d380d4c4475"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 8500;
              }
            ];
          }
          # DTS:X
          {
            trash_ids = ["3cafb66171b47f226146a0770576870f"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 8000;
              }
            ];
          }
          # TrueHD (lossless 5.1/7.1)
          {
            trash_ids = ["496f355514737f7d83bf7aa4d24f8169"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 7000;
              }
            ];
          }
          # DTS-HD MA (lossless 5.1/7.1)
          {
            trash_ids = ["2f22d89048b01681dde8afe203bf2e95"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 6500;
              }
            ];
          }
          # DD+ 5.1 / DTS 5.1 (standard fallback)
          {
            trash_ids = ["185f1dd7264c4562b9022d963ac37424" "1c1a4c5e823891c75bc50380a6866f73"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 500;
              }
            ];
          }
          # HDR Formats
          {
            trash_ids = ["e23edd2482476e595fb990b12e7c609c" "b974a6cd08c1066250f1f177d7aa1225" "dfb86d5941bc9075d6af23b09c2aeecd"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = 5000;
              }
            ];
          }
          # Unwanted
          {
            trash_ids = ["ed38b889b31be83fda192888e2286d83" "90a6f9a284dff5103f6346090e6280c8"];
            quality_profiles = [
              {
                name = "4K + HD Fallback";
                score = -10000;
              }
            ];
          }
        ];
      };
    };
  };

  # Ensure services start after filesystem is ready
  systemd.services = {
    transmission.after = ["local-fs.target"];
    sonarr.after = ["local-fs.target"];
    radarr.after = ["local-fs.target"];
    prowlarr.after = ["local-fs.target"];
    bazarr.after = ["local-fs.target"];

    # Arr services initial configuration via API
    arr-setup = {
      description = "Configure Radarr and Sonarr via API";
      after = ["network-online.target" "radarr.service" "sonarr.service" "transmission.service"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${arr-setup-script}/bin/arr-setup";
        RemainAfterExit = true;
        User = "root";
      };
    };

    # Recyclarr should run after arr-setup
    recyclarr.after = ["arr-setup.service"];
  };
  # Note: Network dependencies and restart policies are configured in network-resilience.nix
}
