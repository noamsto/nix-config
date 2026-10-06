# Declarative disk layout for ThinkPad P14s Gen 5
# LUKS full-disk encryption + Btrfs with zstd compression
#
# Wipes the WHOLE disk. Reinstall from another host with `just reinstall-host` (BTRFS-MIGRATION.md).
#
# After first boot, enroll a recovery key, then TPM via `just tpm-enroll`.
{
  disko.devices = {
    disk.main = {
      type = "disk";
      # By serial, not /dev/nvme0n1: a USB stick or second drive can never be the target.
      device = "/dev/disk/by-id/nvme-KXG8AZNV2T04_LA_KIOXIA_34UF703DFTDU";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G"; # lanzaboote keeps a signed UKI per generation
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
              # Consumed by `nixos-anywhere --disk-encryption-keys`; the file
              # only exists in the installer's tmpfs, never on the target.
              passwordFile = "/tmp/disk.key";
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
                    swap.swapfile.size = "16G";
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
