{
  pkgs,
  config,
  lib,
  ...
}: {
  # Raspberry Pi 4: 4 cores, 8GB RAM
  nix.settings = {
    max-jobs = 2;
    cores = 2; # 2x2 = 4 threads total
    max-silent-time = 14400;
    timeout = 172800;
  };

  # ZFS-specific boot configuration
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

    # Performance tuning for ZFS
    kernel.sysctl = {
      # VM tuning for ZFS
      "vm.swappiness" = 10;
      "vm.min_free_kbytes" = 65536;

      # Network tuning for NAS workloads
      "net.core.rmem_max" = 134217728;
      "net.core.wmem_max" = 134217728;
      "net.ipv4.tcp_rmem" = "4096 87380 134217728";
      "net.ipv4.tcp_wmem" = "4096 65536 134217728";
    };
  };

  # Network configuration - systemd-networkd with ZFS requirements
  networking = {
    hostName = "naspi";
    hostId = "8425e349"; # Required for ZFS
    useNetworkd = true;
    useDHCP = false;
    enableIPv6 = false; # Disable IPv6 to avoid connectivity issues

    firewall = {
      enable = true;
      allowedTCPPorts = [
        22 # SSH
        80 # HTTP (nginx reverse proxy)
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

  # Configure all interfaces to use DHCP (IPv4 only, IPv6 disabled)
  systemd.network = {
    enable = true;
    networks = {
      # Ethernet interface
      "10-ethernet" = {
        matchConfig.Name = "eth* en*";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = false;
        };
        dhcpV4Config.RouteMetric = 100;
      };
      # WiFi interface (if present)
      "20-wireless" = {
        matchConfig.Name = "wlan*";
        networkConfig = {
          DHCP = "ipv4";
          IPv6AcceptRA = false;
        };
        dhcpV4Config.RouteMetric = 200;
      };
    };

    # Configure systemd-networkd-wait-online properly
    # Use anyInterface so it exits when ANY interface is online (not all)
    wait-online = {
      enable = true;
      anyInterface = true; # Exit when end0 comes up, don't wait for wlan0
      timeout = 30; # Reduce from 120s default
    };
  };

  # Enable iwd for WiFi management (lightweight, no GUI dependencies)
  networking.wireless.iwd.enable = true;

  # SSH with socket activation to avoid race conditions with networkd
  services.openssh = {
    enable = true;
    # Socket activation: sshd starts on-demand instead of running as daemon
    startWhenNeeded = true;
    settings = {
      PermitRootLogin = "yes";
      PasswordAuthentication = true;
    };
  };

  # User configuration
  users.users = {
    # Root user - needed for emergency mode access
    root = {
      initialPassword = "nixos";
    };

    # Normal user
    noams = {
      isNormalUser = true;
      extraGroups = ["wheel" "gpio"];
      # initialPassword removed - using hashedPassword from password-fix.nix
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
      ];
    };
  };

  # Enable sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

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
  };

  # Packages - merge base and ZFS-specific
  environment.systemPackages = with pkgs; [
    # Base packages
    vim
    git
    htop
    nh
    nom

    # ZFS tools
    zfs
    zfstools

    # Disk management
    smartmontools
    hdparm
    sdparm

    # Monitoring
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

  # Ensure proper permissions for storage directories and ZFS key storage
  systemd.tmpfiles.rules = [
    "d /data 0755 root root -"
    "d /media/storage 0755 root root -"
    "d /boot/zfs-keys 0700 root root -"
  ];

  # Configure systemd service dependencies
  systemd.services = {
    # Load ZFS encryption key for /data dataset
    zfs-load-data-key = {
      description = "Load ZFS encryption key for /data dataset";
      after = ["zfs-import-rpool.service"];
      before = ["zfs-mount.service" "data.mount"];
      wantedBy = ["zfs-mount.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        echo "Loading ZFS encryption key for rpool/data..."
        KEYSTATUS=$(${config.boot.zfs.package}/bin/zfs get -H -o value keystatus rpool/data)
        if [ "$KEYSTATUS" = "available" ]; then
          echo "✓ Key already loaded for rpool/data"
          exit 0
        fi
        echo "Key status: $KEYSTATUS - loading key..."
        if [ -f /boot/zfs-keys/rpool ]; then
          ${config.boot.zfs.package}/bin/zfs load-key rpool/data
          echo "✓ Encryption key loaded successfully"
        else
          echo "ERROR: Encryption key not found at /boot/zfs-keys/rpool"
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
        ROOT_DEVICE=$(findmnt -n -o SOURCE /)
        echo "Root filesystem: $ROOT_DEVICE"
        if [[ "$ROOT_DEVICE" =~ "rpool" ]]; then
          echo "✓ Booting from ZFS pool (correct)"
        else
          echo "⚠ WARNING: Not booting from expected ZFS pool!"
        fi
        BOOT_DEVICE=$(findmnt -n -o SOURCE /boot)
        echo "Boot partition: $BOOT_DEVICE"
        if [[ "$BOOT_DEVICE" =~ "BOOT1" ]] || [[ "$BOOT_DEVICE" =~ "ata-PNY" ]]; then
          echo "✓ Booting from SSD (correct)"
        else
          echo "⚠ WARNING: Boot partition might be from SD card!"
        fi
        if systemctl list-unit-files | grep -q "emergency-ssh"; then
          echo "❌ ERROR: emergency-ssh service detected!"
        else
          echo "✓ No conflicting services detected"
        fi
        echo ""
        echo "ZFS Pool Status:"
        ${config.boot.zfs.package}/bin/zpool status rpool | head -n 15
        echo "========================================"
      '';
    };
  };

  # System configuration
  system.nixos.tags = let
    cfg = config.boot.loader.raspberryPi;
  in [
    "raspberry-pi-${cfg.variant}"
    cfg.bootloader
    config.boot.kernelPackages.kernel.version
  ];

  system.stateVersion = "25.05";
  nixpkgs.hostPlatform = "aarch64-linux";
}
