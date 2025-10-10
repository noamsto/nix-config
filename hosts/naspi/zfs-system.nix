{
  pkgs,
  config,
  lib,
  ...
}: {
  # Import base system configuration
  imports = [
    ./system.nix
  ];

  # ZFS-specific system configuration
  boot = {
    # ZFS support
    supportedFilesystems = ["zfs"];
    zfs = {
      # CRITICAL: Must be true for ZFS root filesystem!
      # This ensures the ZFS pool containing root is imported during initrd (stage 1)
      # Without this, boot will fail with emergency mode
      forceImportRoot = true;
      forceImportAll = false;
      # Use key files for automatic unlock - no password prompts
      requestEncryptionCredentials = false;
      # Enable devNodes for proper key file handling
      devNodes = "/dev/disk/by-id";
    };

    # Kernel modules for ZFS
    initrd = {
      supportedFilesystems = ["zfs"];
      # Include necessary kernel modules for USB SSDs
      kernelModules = [
        "usb_storage"
        "uas" # USB Attached SCSI for better SSD performance
        "sd_mod"
      ];
      availableKernelModules = [
        "xhci_pci"
        "usbhid"
        "usb_storage"
        "nvme"
      ];
    };

    # Kernel parameters optimized for ZFS on RPi4
    kernelParams = [
      "zfs.zfs_arc_max=2147483648" # Limit ARC to 2GB (25% of 8GB RAM)
      "zfs.zfs_arc_min=134217728" # Minimum ARC 128MB
      "zfs.zfs_compressed_arc_enabled=1" # Enable compressed ARC
      "zfs.zfs_prefetch_disable=0" # Enable prefetch for better performance
      "zfs.zfs_txg_timeout=5" # Faster transaction groups for responsiveness
    ];

    # Kernel provided by raspberry-pi-4.base module (optimized for RPi4 hardware)
  };

  # Network configuration for ZFS
  networking = {
    hostName = "naspi";
    hostId = "8425e349"; # Required for ZFS, generate with: head -c 8 /etc/machine-id

    # Enable additional network features for NAS functionality
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22 # SSH
        80 # HTTP (for web interfaces)
        443 # HTTPS
        445 # SMB
        2049 # NFS
        8080 # Alternative HTTP
        9090 # Cockpit (optional)
      ];
      allowedUDPPorts = [
        137 # NetBIOS Name Service
        138 # NetBIOS Datagram Service
        2049 # NFS
      ];
    };
  };

  # ZFS-specific services
  services = {
    # SSH with socket activation to avoid race conditions with networkd
    openssh = {
      enable = true;
      # Socket activation: sshd starts on-demand instead of running as daemon
      # This avoids race conditions with systemd-networkd during boot
      startWhenNeeded = true;
      settings = {
        PermitRootLogin = "yes";
        PasswordAuthentication = true;
      };
    };
    # ZFS maintenance
    zfs = {
      autoScrub = {
        enable = true;
        interval = "weekly";
        pools = ["rpool"];
      };
      autoSnapshot = {
        enable = true;
        frequent = 4; # Keep 4 15-minute snapshots
        hourly = 24; # Keep 24 hourly snapshots
        daily = 7; # Keep 7 daily snapshots
        weekly = 4; # Keep 4 weekly snapshots
        monthly = 12; # Keep 12 monthly snapshots
      };
      trim = {
        enable = true;
        interval = "weekly";
      };
    };

    # NFS server for network storage
    nfs.server = {
      enable = true;
      exports = ''
        /data         192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
        /media/storage 192.168.1.0/24(rw,sync,no_subtree_check,no_root_squash)
      '';
    };

    # Samba for Windows compatibility
    samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          security = "user";
        };
        data = {
          path = "/data";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "create mask" = "0644";
          "directory mask" = "0755";
          comment = "NAS Data Storage";
        };
        media = {
          path = "/media/storage";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "yes";
          "create mask" = "0644";
          "directory mask" = "0755";
          comment = "Media Storage";
        };
      };
    };

    # Web Services Discovery for Windows Network
    samba-wsdd = {
      enable = true;
      openFirewall = true;
    };

    # Enable SMART monitoring for SSDs
    smartd = {
      enable = true;
      autodetect = true;
      notifications = {
        test = true;
        wall.enable = true;
      };
    };

    # Optional: Cockpit for web-based management
    # cockpit = {
    #   enable = true;
    #   port = 9090;
    # };
  };

  # Additional packages for ZFS management
  environment.systemPackages = with pkgs; [
    # ZFS tools
    zfs
    zfstools

    # Disk management
    smartmontools
    hdparm
    sdparm

    # Monitoring
    htop
    iotop
    nmon

    # Network tools
    nfs-utils
    samba

    # Backup tools
    sanoid # ZFS snapshot management (includes syncoid for replication)
    restic # Backup program
    rclone # Cloud storage sync
  ];

  # System monitoring and alerts
  services.prometheus = {
    enable = true;
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "filesystem"
          "loadavg"
          "meminfo"
          "netdev"
          "stat"
          "time"
          "diskstats"
          "zfs"
        ];
      };
      zfs = {
        enable = true;
      };
    };
  };

  # Ensure proper permissions for storage directories and ZFS key storage
  systemd.tmpfiles.rules = [
    "d /data 0755 root root -"
    "d /media/storage 0755 root root -"
    "d /boot/zfs-keys 0700 root root -"
  ];

  # Configure systemd service dependencies
  systemd.services = {
    # Load ZFS encryption key for /data dataset
    # This service triggers /boot automount and loads the encryption key
    # ZFS/systemd will handle mounting after key is available
    zfs-load-data-key = {
      description = "Load ZFS encryption key for /data dataset";

      # Ordering: after pool import, before ZFS attempts to mount
      after = ["zfs-import-rpool.service"];
      before = ["zfs-mount.service" "data.mount"];

      # Start with ZFS mount service
      wantedBy = ["zfs-mount.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -euo pipefail

        echo "Loading ZFS encryption key for rpool/data..."

        # Check if key is already loaded
        KEYSTATUS=$(${config.boot.zfs.package}/bin/zfs get -H -o value keystatus rpool/data)
        if [ "$KEYSTATUS" = "available" ]; then
          echo "✓ Key already loaded for rpool/data"
          exit 0
        fi

        echo "Key status: $KEYSTATUS - loading key..."

        # Load encryption key from file
        # Note: Accessing /boot/zfs-keys/rpool will trigger /boot automount
        if [ -f /boot/zfs-keys/rpool ]; then
          ${config.boot.zfs.package}/bin/zfs load-key rpool/data
          echo "✓ Encryption key loaded successfully"
        else
          echo "ERROR: Encryption key not found at /boot/zfs-keys/rpool"
          echo "This should have been created during installation by disko postMountHook"
          exit 1
        fi
      '';
    };

    # Boot source verification and diagnostics
    naspi-boot-verify = {
      description = "NasPi Boot Source Verification";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [pkgs.util-linux];
      script = ''
        echo "========================================"
        echo "NasPi Boot Verification"
        echo "========================================"

        # Check if we're booting from the correct device
        ROOT_DEVICE=$(findmnt -n -o SOURCE /)
        echo "Root filesystem: $ROOT_DEVICE"

        if [[ "$ROOT_DEVICE" =~ "rpool" ]]; then
          echo "✓ Booting from ZFS pool (correct)"
        else
          echo "⚠ WARNING: Not booting from expected ZFS pool!"
          echo "  Expected: rpool/root"
          echo "  Actual: $ROOT_DEVICE"
        fi

        # Check boot partition
        BOOT_DEVICE=$(findmnt -n -o SOURCE /boot)
        echo "Boot partition: $BOOT_DEVICE"

        if [[ "$BOOT_DEVICE" =~ "BOOT1" ]] || [[ "$BOOT_DEVICE" =~ "ata-PNY" ]]; then
          echo "✓ Booting from SSD (correct)"
        else
          echo "⚠ WARNING: Boot partition might be from SD card!"
          echo "  Remove SD card from slot if present"
        fi

        # Check for emergency-ssh service (indicates wrong config)
        if systemctl list-unit-files | grep -q "emergency-ssh"; then
          echo ""
          echo "❌ ERROR: emergency-ssh service detected!"
          echo "   This indicates the system was deployed with wrong configuration"
          echo "   Expected: naspi (ZFS RAID1 configuration)"
          echo "   Detected: Old/different configuration"
          echo ""
          echo "   Fix: Redeploy with correct configuration:"
          echo "   ./scripts/naspi-deploy.sh naspi.local install"
          echo ""
        else
          echo "✓ No conflicting services detected"
        fi

        # Check ZFS pool status
        echo ""
        echo "ZFS Pool Status:"
        ${config.boot.zfs.package}/bin/zpool status rpool | head -n 15

        echo ""
        echo "Boot verification complete"
        echo "========================================"
      '';
    };
  };

  # Configure systemd-networkd-wait-online properly
  # Use anyInterface so it exits when ANY interface is online (not all)
  # This prevents timeout waiting for unconfigured wlan0
  systemd.network.wait-online = {
    enable = true;
    anyInterface = true; # Exit when end0 comes up, don't wait for wlan0
    timeout = 30; # Reduce from 120s default
  };

  # Performance tuning for ZFS
  boot.kernel.sysctl = {
    # VM tuning for ZFS
    "vm.swappiness" = 10;
    "vm.min_free_kbytes" = 65536;

    # Network tuning for NAS workloads
    "net.core.rmem_max" = 134217728;
    "net.core.wmem_max" = 134217728;
    "net.ipv4.tcp_rmem" = "4096 87380 134217728";
    "net.ipv4.tcp_wmem" = "4096 65536 134217728";
  };
}
