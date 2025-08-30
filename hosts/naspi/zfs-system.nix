{
  pkgs,
  config,
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
      forceImportRoot = false;
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
    };

    # Kernel parameters optimized for ZFS on RPi4
    kernelParams = [
      "zfs.zfs_arc_max=2147483648" # Limit ARC to 2GB (25% of 8GB RAM)
      "zfs.zfs_arc_min=134217728" # Minimum ARC 128MB
      "zfs.zfs_compressed_arc_enabled=1" # Enable compressed ARC
      "zfs.zfs_prefetch_disable=0" # Enable prefetch for better performance
      "zfs.zfs_txg_timeout=5" # Faster transaction groups for responsiveness
    ];

    # Use latest kernel for better ZFS support
    kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
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
      securityType = "user";
      openFirewall = true;
      shares = {
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
    sanoid # ZFS snapshot management
    syncoid # ZFS snapshot replication
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
