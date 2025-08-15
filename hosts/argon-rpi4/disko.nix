{
  disko.devices = {
    disk = {
      external-ssd = {
        type = "disk";
        device = "/dev/disk/by-id/ata-Netac_SSD_512GB_AA000000000000000075";
        content = {
          type = "gpt";
          partitions = {
            firmware = {
              size = "1G"; # Increased for better compatibility
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/firmware";
                mountOptions = [
                  "umask=0022" # More permissive for debugging (readable by all)
                  "fmask=0133" # Files: readable by all, writable by owner
                  "dmask=0022" # Directories: accessible by all
                  "shortname=mixed" # Allow mixed case short names
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
