# ClamAV antivirus with weekly scanning for SOC compliance
{
  config,
  pkgs,
  lib,
  ...
}: {
  # ClamAV antivirus daemon and database updater
  services.clamav = {
    daemon = {
      enable = true;
      settings = {
        # Performance settings
        MaxThreads = 4;
        MaxDirectoryRecursion = 20;

        # Scan settings
        ScanArchive = true;
        ArchiveBlockEncrypted = false;

        # Alert on large files but don't skip them
        AlertExceedsMax = true;

        # Exclusions - skip immutable/virtual filesystems
        ExcludePath = [
          "^/nix/"
          "^/proc/"
          "^/sys/"
          "^/dev/"
          "^/run/"
        ];

        # Log settings
        LogFile = "/var/log/clamav/clamd.log";
        LogTime = true;
        LogVerbose = false;
      };
    };

    # Keep virus definitions updated
    updater = {
      enable = true;
      interval = "daily"; # Update definitions daily
      frequency = 1;
    };
  };

  # Weekly system scan timer
  systemd.services.clamav-weekly-scan = {
    description = "Weekly ClamAV system scan";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = let
        scanScript = pkgs.writeShellScript "clamav-scan" ''
          # Focus on user-writable locations with external files
          # Skip /nix (immutable), virtual filesystems, and system dirs
          SCAN_DIRS="/home /tmp /var/tmp /mnt /media"

          # Log file
          LOG_FILE="/var/log/clamav/weekly-scan-$(date +%Y%m%d).log"

          echo "Starting weekly ClamAV scan at $(date)" | tee "$LOG_FILE"

          # Run scan with exclusions for Nix-managed and virtual paths
          ${pkgs.clamav}/bin/clamscan \
            --recursive \
            --infected \
            --log="$LOG_FILE" \
            --exclude-dir="^/nix" \
            --exclude-dir="^/proc" \
            --exclude-dir="^/sys" \
            --exclude-dir="^/dev" \
            --exclude-dir="^/run" \
            --exclude-dir="\.nix-profile" \
            --exclude-dir="\.nix-defexpr" \
            --exclude-dir="\.cache/nix" \
            $SCAN_DIRS

          EXIT_CODE=$?

          echo "Scan completed at $(date) with exit code $EXIT_CODE" | tee -a "$LOG_FILE"

          # Keep only last 4 weekly scan logs
          find /var/log/clamav -name "weekly-scan-*.log" -mtime +28 -delete 2>/dev/null || true
        '';
      in "${scanScript}";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.clamav-weekly-scan = {
    description = "Weekly ClamAV scan timer";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "Sun 04:00"; # Sunday at 4 AM (after auto-upgrade at 3 AM)
      RandomizedDelaySec = "30min";
      Persistent = true; # Run if missed
    };
  };

  # Ensure log directory exists
  systemd.tmpfiles.rules = [
    "d /var/log/clamav 0755 clamav clamav -"
  ];
}
