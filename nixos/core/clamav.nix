# ClamAV antivirus with weekly scanning for SOC compliance
# Daemon is disabled — weekly scan uses standalone clamscan which loads
# definitions on-demand, avoiding ~1.5 GB resident memory from clamd.
{pkgs, ...}: {
  services.clamav = {
    daemon.enable = false;

    # Keep virus definitions updated for the weekly scan
    updater = {
      enable = true;
      interval = "daily";
      frequency = 1;
    };
  };

  # Weekly system scan timer + log directory
  systemd = {
    services.clamav-weekly-scan = {
      description = "Weekly ClamAV system scan";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = let
          scanScript = pkgs.writeShellScript "clamav-scan" ''
            # Only scan real attack surface: files arriving from outside the system.
            # Excludes git repos, Go/Nix caches, app data (~260G of noise).
            SCAN_DIRS="/home/noams/Downloads /home/noams/Desktop /home/noams/Documents /tmp /var/tmp /mnt /media"

            LOG_FILE="/var/log/clamav/weekly-scan-$(date +%Y%m%d).log"

            echo "Starting weekly ClamAV scan at $(date)" | tee "$LOG_FILE"

            ${pkgs.clamav}/bin/clamscan \
              --recursive \
              --infected \
              --log="$LOG_FILE" \
              $SCAN_DIRS

            EXIT_CODE=$?

            echo "Scan completed at $(date) with exit code $EXIT_CODE" | tee -a "$LOG_FILE"

            find /var/log/clamav -name "weekly-scan-*.log" -mtime +28 -delete 2>/dev/null || true
          '';
        in "${scanScript}";
        Nice = 19;
        IOSchedulingClass = "idle";
        CPUSchedulingPolicy = "idle";
      };
    };

    timers.clamav-weekly-scan = {
      description = "Weekly ClamAV scan timer";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "Sun 04:00"; # Sunday at 4 AM (after auto-upgrade at 3 AM)
        RandomizedDelaySec = "30min";
        Persistent = true; # Run if missed
      };
    };

    # Ensure log directory exists
    tmpfiles.rules = [
      "d /var/log/clamav 0755 clamav clamav -"
    ];
  };
}
