{
  config,
  lib,
  pkgs,
  ...
}: let
  # Reusable partition templates to reduce duplication
  firmwarePartition = {
    priority = 1;
    size = "512M";
    type = "0700"; # Microsoft basic data
    content = {
      type = "filesystem";
      format = "vfat";
      mountOptions = [
        "noatime"
        "umask=0077"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

  bootPartition = {
    size = "1G";
    type = "EF00"; # EFI System Partition
    content = {
      type = "filesystem";
      format = "vfat";
      mountOptions = [
        "noatime"
        "umask=0077"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };
in {
  # ZFS services
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "weekly";
    };
    autoSnapshot = {
      enable = true;
      frequent = 4; # Keep 4 15-minute snapshots
      hourly = 24;
      daily = 7;
      weekly = 4;
      monthly = 12;
    };
    trim.enable = true; # Enable TRIM for SSDs
  };

  disko.devices = {
    disk = {
      # First SSD (2TB)
      ssd1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-PNY_2TB_SATA_SSD_PND09252386160202099";
        content = {
          type = "gpt";
          partitions = {
            # Firmware partition for Raspberry Pi
            firmware =
              firmwarePartition
              // {
                label = "FIRMWARE1";
                content =
                  firmwarePartition.content
                  // {
                    mountpoint = "/boot/firmware";
                  };
              };

            # Boot partition for Linux kernel
            boot =
              bootPartition
              // {
                label = "BOOT1";
                content =
                  bootPartition.content
                  // {
                    mountpoint = "/boot";
                  };
              };

            # ZFS partition (remaining space)
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };

      # Second SSD (2TB)
      ssd2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-PNY_2TB_SATA_SSD_PND09252386160202096";
        content = {
          type = "gpt";
          partitions = {
            # Backup firmware partition (for redundancy)
            firmware-backup =
              firmwarePartition
              // {
                label = "FIRMWARE2";
                content =
                  firmwarePartition.content
                  // {
                    mountpoint = "/boot/firmware-backup";
                  };
              };

            # Backup boot partition
            boot-backup =
              bootPartition
              // {
                label = "BOOT2";
                content =
                  bootPartition.content
                  // {
                    mountpoint = "/boot/boot-backup";
                  };
              };

            # ZFS partition (remaining space)
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
    };

    zpool = {
      rpool = {
        type = "zpool";
        mode = "mirror"; # RAID1 for redundancy

        # Root pool options optimized for ARM64 and SSDs
        options = {
          ashift = "12"; # 4K sectors for SSDs
          autotrim = "on"; # Enable automatic TRIM
          compatibility = "openzfs-2.2-linux"; # Latest stable feature set
        };

        # Root filesystem options
        rootFsOptions = {
          acltype = "posixacl";
          atime = "off"; # Reduce writes
          canmount = "off";
          compression = "zstd"; # Better compression than lz4
          dnodesize = "auto";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
          "com.sun:auto-snapshot" = "false";
        };

        # Mount options for all datasets
        mountOptions = [
          "zfsutil"
          "noatime"
        ];

        # Create initial snapshot for rollback capability
        postCreateHook = ''
          zfs list -t snapshot -H -o name | grep -E '^rpool@blank$' || zfs snapshot rpool@blank
        '';

        # Dataset layout
        datasets = {
          # Root filesystem
          "root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options = {
              canmount = "noauto";
              mountpoint = "legacy";
              "com.sun:auto-snapshot" = "false";
            };
            postCreateHook = ''
              zfs set mountpoint=legacy rpool/root
            '';
          };

          # Home directories
          "home" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options = {
              canmount = "on";
              compression = "zstd-3"; # Higher compression for user data
              "com.sun:auto-snapshot" = "true";
            };
          };

          # Nix store
          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              canmount = "on";
              compression = "zstd-fast"; # Fast compression for frequent access
              atime = "off";
              "com.sun:auto-snapshot" = "false"; # No snapshots for nix store
            };
          };

          # Variable data
          "var" = {
            type = "zfs_fs";
            mountpoint = "/var";
            options = {
              canmount = "on";
              compression = "zstd";
              "com.sun:auto-snapshot" = "true";
            };
          };

          # Logs (separate for different retention)
          "var/log" = {
            type = "zfs_fs";
            mountpoint = "/var/log";
            options = {
              canmount = "on";
              compression = "zstd-5"; # High compression for logs
              "com.sun:auto-snapshot" = "true";
            };
          };

          # Docker volumes (if needed)
          "docker" = {
            type = "zfs_fs";
            mountpoint = "/var/lib/docker";
            options = {
              canmount = "on";
              compression = "zstd";
              "com.sun:auto-snapshot" = "true";
            };
          };

          # Data storage (for NAS functionality)
          "data" = {
            type = "zfs_fs";
            mountpoint = "/data";
            options = {
              canmount = "on";
              compression = "zstd-3";
              "com.sun:auto-snapshot" = "true";
              # ZFS native encryption with key file provided by nixos-anywhere
              encryption = "aes-256-gcm";
              keyformat = "raw";
              keylocation = "file:///tmp/zfs-rpool-key"; # nixos-anywhere puts it here
            };
            postCreateHook = ''
              # Create permanent key storage location
              mkdir -p /mnt/boot/zfs-keys
              chmod 700 /mnt/boot/zfs-keys

              # Copy the key to permanent location
              if [ -f /tmp/zfs-rpool-key ]; then
                cp /tmp/zfs-rpool-key /mnt/boot/zfs-keys/rpool
                chmod 600 /mnt/boot/zfs-keys/rpool

                # Update keylocation to permanent path for future boots
                zfs set keylocation=file:///boot/zfs-keys/rpool rpool/data
                echo "🔑 ZFS encryption key installed and keylocation updated"
              else
                echo "⚠️  Warning: No ZFS key found at /tmp/zfs-rpool-key"
                echo "    Dataset creation may fail without encryption key"
              fi
            '';
          };

          # Media storage (if needed, with different settings)
          "media" = {
            type = "zfs_fs";
            mountpoint = "/media/storage";
            options = {
              canmount = "on";
              compression = "off"; # No compression for media files
              recordsize = "1M"; # Large record size for media files
              "com.sun:auto-snapshot" = "true";
            };
          };

          # Reserved space for snapshots
          "reserved" = {
            type = "zfs_fs";
            options = {
              canmount = "off";
              reservation = "100G"; # Reserve 100GB for snapshots
              "com.sun:auto-snapshot" = "false";
            };
          };
        };
      };
    };
  };

  # Swap configuration (optional, on ZFS zvol)
  swapDevices = [
    {
      device = "/dev/zvol/rpool/swap";
      priority = 5;
    }
  ];

  # Create swap zvol after pool creation
  boot.kernelParams = ["zfs.zfs_arc_max=2147483648"]; # Limit ARC to 2GB on 8GB system

  systemd.services.zfs-create-swap = {
    description = "Create ZFS swap volume";
    after = ["zfs-import-rpool.service"];
    before = ["swap-dev-zvol-rpool-swap.swap"];
    wantedBy = ["swap-dev-zvol-rpool-swap.swap"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if ! ${config.boot.zfs.package}/bin/zfs list rpool/swap >/dev/null 2>&1; then
        ${config.boot.zfs.package}/bin/zfs create \
          -V 4G \
          -b 4096 \
          -o compression=off \
          -o sync=always \
          -o primarycache=metadata \
          -o secondarycache=none \
          -o logbias=throughput \
          -o com.sun:auto-snapshot=false \
          rpool/swap

        ${lib.getExe' pkgs.util-linux "mkswap"} /dev/zvol/rpool/swap
      fi
    '';
  };
}
