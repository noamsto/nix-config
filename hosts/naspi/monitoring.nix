{
  config,
  pkgs,
  ...
}: {
  # Prometheus - Metrics collection and storage
  services.prometheus = {
    enable = true;
    port = 9090;

    # Scrape configuration
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString config.services.prometheus.exporters.node.port}"];
          }
        ];
        scrape_interval = "15s";
      }
      {
        job_name = "smartctl";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString config.services.prometheus.exporters.smartctl.port}"];
          }
        ];
        scrape_interval = "60s"; # SMART data doesn't change frequently
      }
      {
        job_name = "zfs";
        static_configs = [
          {
            targets = ["127.0.0.1:${toString config.services.prometheus.exporters.zfs.port}"];
          }
        ];
        scrape_interval = "30s";
      }
    ];

    # Retention settings
    retentionTime = "30d";

    # Global settings
    globalConfig = {
      scrape_interval = "15s";
      evaluation_interval = "15s";
    };
  };

  # Grafana - Visualization and dashboards
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0";
        http_port = 3001;
        domain = "naspi.local";
        # Enable subfolder access via /grafana (accessed via nginx on port 80)
        root_url = "http://naspi.local/grafana/";
        serve_from_sub_path = true;
      };

      # Security settings
      security = {
        admin_user = "admin";
        admin_password = "admin"; # CHANGE THIS after first login!
        allow_embedding = true;
      };

      # Anonymous access disabled for security
      "auth.anonymous" = {
        enabled = false;
      };
    };

    # Provision Prometheus datasource automatically
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:${toString config.services.prometheus.port}";
          isDefault = true;
          jsonData = {
            timeInterval = "15s";
          };
        }
      ];
    };
  };

  # Node Exporter - System metrics (CPU, RAM, disk, network, temperature)
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [
      "systemd" # Systemd units and services
      "processes" # Process statistics
      "thermal_zone" # CPU temperature (Raspberry Pi SoC temp)
    ];
    # Most useful collectors are enabled by default:
    # - cpu, loadavg, meminfo, diskstats, filesystem, netdev, etc.
  };

  # Smartctl Exporter - Disk SMART health monitoring
  services.prometheus.exporters.smartctl = {
    enable = true;
    port = 9633;
    # Auto-discovers all disks by default
    # Will monitor both SSDs on the Raspberry Pi
  };

  # ZFS Exporter - ZFS pool and dataset metrics
  services.prometheus.exporters.zfs = {
    enable = true;
    port = 9134;
    # Monitors:
    # - Pool status and health
    # - Dataset usage and quotas
    # - ARC statistics
    # - Scrub status and errors
  };

  # Open firewall ports for monitoring services
  networking.firewall.allowedTCPPorts = [
    9090 # Prometheus
    3001 # Grafana
    9100 # Node Exporter
    9633 # Smartctl Exporter
    9134 # ZFS Exporter
  ];

  # Ensure Prometheus starts after exporters
  systemd.services.prometheus = {
    after = [
      "prometheus-node-exporter.service"
      "prometheus-smartctl-exporter.service"
      "prometheus-zfs-exporter.service"
    ];
    wants = [
      "prometheus-node-exporter.service"
      "prometheus-smartctl-exporter.service"
      "prometheus-zfs-exporter.service"
    ];
  };

  # Additional monitoring packages
  environment.systemPackages = with pkgs; [
    prometheus # For promtool CLI
    grafana # For grafana-cli
  ];
}
