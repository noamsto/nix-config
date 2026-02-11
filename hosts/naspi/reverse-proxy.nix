{config, ...}: {
  # Nginx reverse proxy for subfolder access to services
  services.nginx = {
    enable = true;

    recommendedProxySettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    virtualHosts."naspi" = {
      serverAliases = ["naspi.local" "localhost"];

      locations = {
        # Root redirect to a simple status page
        "/" = {
          extraConfig = ''
            return 200 'NasPi Services: /radarr /sonarr /prowlarr /bazarr /flood /transmission /grafana /bills';
            add_header Content-Type text/plain;
          '';
        };

        # Go Bills - Shared Bills Management
        # No trailing slash on proxyPass = path is preserved (app handles /bills/*)
        "/bills" = {
          proxyPass = "http://127.0.0.1:8082";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
            # OCR bill extraction via Gemini can take up to 5 minutes
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
          '';
        };

        # Radarr - Movies
        "/radarr" = {
          proxyPass = "http://127.0.0.1:7878";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
          '';
        };

        # Sonarr - TV Shows
        "/sonarr" = {
          proxyPass = "http://127.0.0.1:8989";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
          '';
        };

        # Prowlarr - Indexer Manager
        "/prowlarr" = {
          proxyPass = "http://127.0.0.1:9696";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
          '';
        };

        # Bazarr - Subtitles
        "/bazarr" = {
          proxyPass = "http://127.0.0.1:6767";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
          '';
        };

        # Flood - Torrent Web UI (using baseuri /flood)
        "/flood/" = {
          proxyPass = "http://127.0.0.1:3000";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
            # Required for Flood event-streams
            chunked_transfer_encoding off;
            proxy_buffering off;
            proxy_cache off;
          '';
        };

        # Transmission - BitTorrent Client
        "/transmission" = {
          proxyPass = "http://127.0.0.1:9091";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_redirect off;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $http_connection;
          '';
        };

        # Grafana - Monitoring Dashboard
        "/grafana/" = {
          proxyPass = "http://127.0.0.1:3001";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };
  };

  # Open HTTP port for reverse proxy
  networking.firewall.allowedTCPPorts = [80];
}
