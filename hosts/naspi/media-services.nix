{
  config,
  pkgs,
  ...
}: {
  # Create media group for shared access
  users.groups.media = {
    gid = 995;
  };

  # Add noams user to media group
  users.users.noams.extraGroups = ["media"];

  # Transmission BitTorrent daemon with Flood UI
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
      rpc-authentication-required = false;

      # Download settings - TRaSH Guides structure
      download-dir = "/data/torrents/complete";
      incomplete-dir-enabled = true;
      incomplete-dir = "/data/torrents/incomplete";
      watch-dir-enabled = true;
      watch-dir = "/data/torrents/watch";

      # Performance settings
      peer-limit-global = 200;
      peer-limit-per-torrent = 50;
      speed-limit-up-enabled = false;
      speed-limit-down-enabled = false;

      # File permissions for hardlinks
      umask = "002"; # 664 for files, 775 for directories
    };
  };

  # Flood - Modern web UI for Transmission
  services.flood = {
    enable = true;
    host = "0.0.0.0";
    port = 3000;
    openFirewall = true;
    extraArgs = [
      "--auth=none"
      "--trurl=http://localhost:9091/transmission/rpc"
    ];
  };

  # Sonarr - TV show automation
  services.sonarr = {
    enable = true;
    group = "media";
    openFirewall = true;
  };

  # Radarr - Movie automation
  services.radarr = {
    enable = true;
    group = "media";
    openFirewall = true;
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

  # Create TRaSH Guides compliant directory structure
  # This follows the recommended structure for hardlinks and atomic moves
  systemd.tmpfiles.rules = [
    # Main data directory
    "d /data 0775 root media - -"

    # Torrent directories (download client)
    "d /data/torrents 0775 transmission media - -"
    "d /data/torrents/complete 0775 transmission media - -"
    "d /data/torrents/incomplete 0775 transmission media - -"
    "d /data/torrents/watch 0775 transmission media - -"

    # Torrent category subdirectories
    "d /data/torrents/complete/tv 0775 transmission media - -"
    "d /data/torrents/complete/movies 0775 transmission media - -"
    "d /data/torrents/complete/music 0775 transmission media - -"

    # Media library directories (Plex/Jellyfin/Emby)
    "d /data/media 0775 root media - -"
    "d /data/media/tv 0775 root media - -"
    "d /data/media/movies 0775 root media - -"
    "d /data/media/music 0775 root media - -"
  ];

  # Network configuration for services
  networking.firewall.allowedTCPPorts = [
    3000 # Flood
    6767 # Bazarr
    7878 # Radarr
    8989 # Sonarr
    9091 # Transmission
    9696 # Prowlarr
  ];

  # Additional packages for media management
  environment.systemPackages = with pkgs; [
    transmission-remote-gtk # GUI client
    mediainfo # Media file information
    ffmpeg # Media processing
    unrar # RAR extraction
    p7zip # Archive extraction
  ];

  # Ensure services start after filesystem is ready
  systemd.services = {
    transmission.after = ["local-fs.target"];
    sonarr.after = ["local-fs.target"];
    radarr.after = ["local-fs.target"];
    prowlarr.after = ["local-fs.target"];
    bazarr.after = ["local-fs.target"];
    flood.after = ["transmission.service"];
  };
}
