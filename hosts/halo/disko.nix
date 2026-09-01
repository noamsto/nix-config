# Declarative disk layout for the Minisforum MS-S1 MAX (Strix Halo)
# LUKS full-disk encryption + Btrfs
#
# Installed from a live ISO: write the passphrase to /tmp/disk.key, then
#   nix run github:nix-community/disko -- --mode disko --flake <ref>#halo
#
# After first boot, enroll TPM for auto-unlock — see the secure-boot-tpm skill.
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1"; # Confirm with `lsblk` on the target before installing
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            # 2G rather than g6's 512M. A UKI here measures ~86 MB (72 MB
            # initrd + 14 MB kernel), so configurationLimit = 4 costs ~350 MB
            # worst case, when no two retained generations share a kernel.
            # g6 survives on 512M only because identical kernels dedup in
            # EFI/nixos — it sits at 171M for 4 generations today, but that is
            # luck, not headroom, and it already had to drop from 12 to 4
            # (commit 40c4225, issue #185). ESP size cannot be changed later
            # without a reinstall, so buy the headroom once.
            size = "2G";
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
                  # GGUF quants are already compressed; zstd costs decompression
                  # on every read and saves nothing. Separate subvolumes also keep
                  # these out of any snapshot policy.
                  "@models" = {
                    mountpoint = "/var/lib/models";
                    mountOptions = ["noatime"];
                  };
                  "@games" = {
                    mountpoint = "/var/lib/games";
                    mountOptions = ["noatime"];
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
