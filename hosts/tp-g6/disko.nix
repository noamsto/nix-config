# Declarative disk layout for ThinkPad P14s Gen 6
# LUKS full-disk encryption + Btrfs with zstd compression
#
# Usage with nixos-anywhere:
#   nixos-anywhere --flake .#tp-g6 --disk main /dev/nvme0n1 root@<ip>
#
# After first boot, enroll TPM for auto-unlock:
#   sudo systemd-cryptenroll --tpm2-device=auto /dev/disk/by-partlabel/disk-main-root
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1"; # Update if device path differs
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["fmask=0022" "dmask=0022"];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              # After first boot + TPM enrollment, uncomment:
              # extraOpenArgs = ["--token-only"];
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@log" = {
                    mountpoint = "/var/log";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@swap" = {
                    mountpoint = "/swap";
                    mountOptions = ["noatime"];
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
