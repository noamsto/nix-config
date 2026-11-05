{
  config,
  pkgs,
  lib,
  ...
}: {
  networking = {
    firewall = {
      enable = true;
      # br-+ wildcard covers docker0 plus every user-defined/k3d bridge
      # (br-<id>), so containers on custom networks can reach the resolved
      # stub listener on 172.17.0.1 (see services.resolved below).
      trustedInterfaces = ["docker0" "br-+"];

      # Valent/KDE Connect ports for device communication
      allowedTCPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];
      allowedUDPPortRanges = [
        {
          from = 1714;
          to = 1764;
        }
      ];

      allowedTCPPorts = [
        # Spotify track sync with other devices
        57621
      ];
    };

    hostName = config.hostname;
    networkmanager = {
      enable = true; # Easiest to use and most distros use this by default.
      dns = "systemd-resolved";
      wifi.backend = "iwd";
    };

    wireless.iwd = {
      enable = true;
      settings = {
        General = {
          EnableNetworkConfiguration = false; # Let NM handle IP config
          RoamRetryInterval = 15; # Retry roaming every 15s if needed
        };
        Scan = {
          DisablePeriodicScan = false;
          InitialPeriodicScanInterval = 1; # Fast initial scan
          MaximumPeriodicScanInterval = 60; # Slow down after connected
        };
        Rank = {
          BandModifier5Ghz = 2.0; # Prefer 5GHz (you have good signal)
          BandModifier6Ghz = 3.0; # Prefer 6GHz if available
        };
      };
    };
  };

  # Restart IWD after resume to clear stale firmware/crypto state
  # Without this, 4-way handshake fails repeatedly after suspend
  systemd.services.iwd-resume = lib.mkIf config.networking.wireless.iwd.enable {
    description = "Restart IWD after suspend to fix WiFi reconnection";
    after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl restart iwd.service";
    };
    wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
  };

  # Wait for a wlan netdev before starting iwd. Known race: iwd uses
  # DriverQuirks.DefaultInterface (auto-set by the NixOS module when NM+iwd
  # is enabled) and attaches only to interfaces present at startup. If the
  # wifi driver creates wlan0 a moment after iwd starts, iwd logs
  # "No default interface for wiphy 0" and stays idle until manual restart.
  systemd.services.iwd.serviceConfig.ExecStartPre =
    lib.mkIf config.networking.wireless.iwd.enable
    (pkgs.writeShellScript "iwd-wait-for-wlan" ''
      for _ in $(seq 50); do
        for iface in /sys/class/net/wl*; do
          [[ -e "$iface" ]] && exit 0
        done
        sleep 0.1
      done
      exit 0
    '');

  services = {
    # DNS service - disable mDNS to avoid conflict with Avahi
    resolved = {
      enable = true;
      settings.Resolve = {
        LLMNR = false;
        MulticastDNS = false;
        # Answer on the docker0 gateway too, not just 127.0.0.53. Docker hands
        # containers a bridge gateway as their nameserver (loopback stubs aren't
        # reachable from a container netns), so without this k3d/container DNS
        # times out. Paired with the daemon `dns` setting that points every
        # container at 172.17.0.1. Bound with IP_FREEBIND, so it works before
        # docker0 exists. Split-DNS (tailnet ~ts.net, .lan) is preserved since
        # queries still flow through this resolved instance.
        DNSStubListenerExtra = "172.17.0.1";
      };
    };

    # For discovering zero-conf network sharing
    avahi = {
      enable = true;
      nssmdns4 = true;
    };

    openssh = {
      enable = true;
      # Key-only by default: password and keyboard-interactive logins on every
      # interface are a brute-force target, roaming laptops included.
      settings = {
        PasswordAuthentication = lib.mkDefault false;
        KbdInteractiveAuthentication = lib.mkDefault false;
      };
    };

    # Location service
    geoclue2 = {
      enable = true;
      # geoProviderUrl = "https://beacondb.net/v1/geolocate";
      # submissionUrl = "https://beacondb.net/v1/geolocate?key=YOUR_API_KEY";
    };
  };
  location.provider = "geoclue2";
}
