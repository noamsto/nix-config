{lib, ...}: {
  systemd = {
    # Ensure network is ready before starting network-dependent services
    network.wait-online = {
      enable = true;
      timeout = 30;
      anyInterface = true; # Don't wait for all interfaces, just any working one
    };

    # Fix avahi socket ordering to prevent root-owned directory creation
    sockets.avahi-daemon = {
      after = ["systemd-tmpfiles-setup.service"];
    };

    # Configure restart policies and network dependencies for all services
    services = {
      # Avahi - Critical for .local mDNS resolution
      avahi-daemon = {
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "10s";
          StartLimitIntervalSec = lib.mkForce 0; # Never stop trying
        };
      };

      # Media services - Allow extended recovery from network issues
      transmission = {
        after = ["network-online.target" "local-fs.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 100; # Allow many retries
          StartLimitIntervalSec = 3600; # Reset counter every hour
        };
      };

      sonarr = {
        after = ["network-online.target" "local-fs.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 100;
          StartLimitIntervalSec = 3600;
          UMask = "0002"; # Create directories with 775 permissions
        };
      };

      radarr = {
        after = ["network-online.target" "local-fs.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 100;
          StartLimitIntervalSec = 3600;
          UMask = "0002"; # Create directories with 775 permissions
        };
      };

      prowlarr = {
        after = ["network-online.target" "local-fs.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 100;
          StartLimitIntervalSec = 3600;
        };
      };

      bazarr = {
        after = ["network-online.target" "local-fs.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "30s";
          StartLimitBurst = 100;
          StartLimitIntervalSec = 3600;
        };
      };

      # Monitoring services - Always restart
      # Note: monitoring.nix already configures prometheus -> exporter dependencies
      prometheus = {
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Restart = "always";
          RestartSec = "10s";
          StartLimitIntervalSec = 0;
        };
      };

      grafana = {
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Restart = lib.mkForce "always";
          RestartSec = "10s";
          StartLimitIntervalSec = 0;
        };
      };

      # Prometheus exporters - Always restart
      prometheus-node-exporter = {
        serviceConfig = {
          Restart = "always";
          RestartSec = "10s";
          StartLimitIntervalSec = 0;
        };
      };

      prometheus-smartctl-exporter = {
        serviceConfig = {
          Restart = "always";
          RestartSec = "10s";
          StartLimitIntervalSec = 0;
        };
      };

      prometheus-zfs-exporter = {
        serviceConfig = {
          Restart = "always";
          RestartSec = "10s";
          StartLimitIntervalSec = 0;
        };
      };
    }; # systemd.services
  }; # systemd
}
