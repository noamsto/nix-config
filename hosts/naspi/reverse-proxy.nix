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
          return = "200 'NasPi Services: /radarr /sonarr /prowlarr /bazarr /flood /transmission /grafana /paperless'";
          extraConfig = ''
            add_header Content-Type text/plain;
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

        # Flood - Torrent Web UI
        "/flood" = {
          proxyPass = "http://127.0.0.1:3000";
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
          proxyPass = "http://127.0.0.1:3001/";
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
            proxy_redirect off;
          '';
        };

        # Paperless-ngx - Document Management
        "/paperless" = {
          proxyPass = "http://127.0.0.1:28981";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_redirect off;
            proxy_http_version 1.1;
            proxy_buffering off;
            client_max_body_size 100M;
          '';
        };
      };
    };
  };

  # Open HTTP port for reverse proxy
  networking.firewall.allowedTCPPorts = [80];
}
