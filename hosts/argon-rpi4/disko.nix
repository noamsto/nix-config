_: {
  # https://nixos.wiki/wiki/Btrfs#Scrubbing
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = ["/"];
  };

  disko.devices = {
    disk = {
      external-ssd = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Netac_SSD_512GB_AA000000000000000075";
        content = {
          type = "gpt";
          partitions = {
            FIRMWARE = {
              label = "FIRMWARE";
              priority = 1;
              size = "1G";
              type = "0700"; # Microsoft basic data
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/firmware"; # RPi firmware
                mountOptions = [
                  "noatime"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=1min"
                  "umask=0077" # Root-only access
                ];
              };
            };

            ESP = {
              label = "ESP";
              size = "1G";
              type = "EF00"; # EFI System Partition
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot"; # Linux kernel and extlinux
                mountOptions = [
                  "noatime"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=1min"
                  "umask=0077" # Root-only access
                ];
              };
            };

            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [
                  "-f" # Force overwrite
                  "--csum"
                  "xxhash" # Faster checksums for ARM
                  "--features"
                  "^raid56" # Disable raid56 for single disk
                ];
                subvolumes = {
                  # Root subvolume
                  "@" = {
                    mountpoint = "/";
                    mountOptions = [
                      "compress=zstd:3" # Good compression/speed balance
                      "noatime" # Reduce writes
                      "ssd" # SSD optimizations
                      "space_cache=v2" # Better space cache
                      "commit=120" # Longer commit intervals
                    ];
                  };
                  # Home directory
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = [
                      "compress=zstd:3"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "commit=120"
                    ];
                  };
                  # Nix store (different compression for better performance)
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = [
                      "compress=zstd:1" # Faster compression for frequent access
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "commit=120"
                    ];
                  };
                  # Variable data (logs, etc.)
                  "@var" = {
                    mountpoint = "/var";
                    mountOptions = [
                      "compress=zstd:3"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                      "commit=120"
                    ];
                  };
                  # Snapshots storage
                  "@snapshots" = {
                    mountpoint = "/.snapshots";
                    mountOptions = [
                      "compress=zstd:3"
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                    ];
                  };
                  # Swap subvolume (for swapfile if needed)
                  "@swap" = {
                    mountpoint = "/swap";
                    mountOptions = [
                      "noatime"
                      "ssd"
                      "space_cache=v2"
                    ];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
