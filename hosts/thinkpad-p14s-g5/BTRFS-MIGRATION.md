# Btrfs on LUKS Migration Plan for thinkpad-p14s-g5

## Overview

Migrate from ext4 on LUKS to Btrfs on LUKS via fresh install, preserving:
- Secure Boot with Lanzaboote
- TPM2 auto-unlock
- All user data and configurations

## Current State

| Component | Current |
|-----------|---------|
| Root FS | ext4 on LUKS |
| Boot | vfat (EFI) |
| Encryption | LUKS + TPM2 auto-unlock |
| Data partition | Separate ext4 at /home/noams/Data |
| Snapshots | None |

## Target State

| Component | Target |
|-----------|--------|
| Root FS | Btrfs on LUKS with subvolumes |
| Boot | vfat (EFI) - unchanged |
| Encryption | LUKS + TPM2 auto-unlock - preserved |
| Data | Merged into @home subvolume |
| Snapshots | btrbk (optional, config ready) |

## Subvolume Layout

```
@           → /           (root, zstd:3)
@home       → /home       (user data, zstd:3)
@nix        → /nix        (store, zstd:1 for speed)
@var        → /var        (logs/state, zstd:3)
@snapshots  → /.snapshots (snapshot storage, zstd:3)
```

No swap subvolume - 54GB RAM makes it unnecessary.

---

## Pre-Migration Tasks (Before Touching Disk)

### 1. Backup Data

```bash
# To NAS (naspi)
rsync -avP --delete /home/noams/ noams@naspi.local:/backup/thinkpad-p14s-g5/home/

# To external USB (belt + suspenders)
rsync -avP --delete /home/noams/ /run/media/noams/BACKUP/home/

# Export critical items explicitly
cp -r ~/.gnupg /run/media/noams/BACKUP/gnupg-backup/
cp -r ~/.ssh /run/media/noams/BACKUP/ssh-backup/
```

### 2. Document Current UUIDs (for reference)

```bash
lsblk -f > ~/current-disk-layout.txt
sudo blkid >> ~/current-disk-layout.txt
```

### 3. Verify NixOS Config is Committed

```bash
cd ~/nix-config
git status  # Should be clean
git push    # Ensure remote has latest
```

---

## Implementation Steps

### Step 1: Create disko Configuration

**File: `hosts/thinkpad-p14s-g5/disko.nix`**

```nix
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1";  # Adjust to actual device
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              extraOpenArgs = [];
              settings = {
                allowDiscards = true;  # TRIM support
              };
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd:1" "noatime" "ssd" "space_cache=v2"];
                  };
                  "@var" = {
                    mountpoint = "/var";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
                  };
                  "@snapshots" = {
                    mountpoint = "/.snapshots";
                    mountOptions = ["compress=zstd:3" "noatime" "ssd" "space_cache=v2"];
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
```

### Step 2: Create btrfs Maintenance Module

**File: `hosts/thinkpad-p14s-g5/btrfs-config.nix`**

```nix
{ pkgs, ... }:
{
  # Btrfs utilities
  environment.systemPackages = with pkgs; [
    btrfs-progs
    compsize     # Check compression ratios
  ];

  # Monthly scrub for data integrity
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = ["/"];
  };

  # Kernel parameters for btrfs root
  boot.kernelParams = [
    "rootflags=compress=zstd:3,noatime,ssd"
  ];

  # Memory tuning for 54GB RAM
  boot.kernel.sysctl = {
    "vm.dirty_ratio" = 15;
    "vm.dirty_background_ratio" = 5;
    "vm.min_free_kbytes" = 262144;  # 256MB reserved
  };
}
```

### Step 3: Optional btrbk Snapshot Configuration

**File: `hosts/thinkpad-p14s-g5/btrbk.nix`** (can enable later)

```nix
{ ... }:
{
  services.btrbk.instances.laptop = {
    onCalendar = "hourly";
    settings = {
      timestamp_format = "long-iso";
      preserve_day_of_week = "monday";
      preserve_hour_of_day = "6";

      snapshot_preserve_min = "1d";
      snapshot_preserve = "7d 4w 3m";

      volume."/" = {
        target = "/.snapshots";
        subvolume = {
          "@" = {};
          "@home" = {};
        };
      };
    };
  };
}
```

### Step 4: Update Host Configuration

**File: `hosts/thinkpad-p14s-g5/default.nix`** - Add imports:

```nix
imports = [
  # ... existing imports ...
  ./disko.nix
  ./btrfs-config.nix
  # ./btrbk.nix  # Uncomment when ready for snapshots
];
```

**Modify: `hosts/thinkpad-p14s-g5/hardware-configuration.nix`**
- **Remove**: `fileSystems.*` and `swapDevices` (disko handles these)
- **Keep**: All hardware-specific config:
  - `boot.initrd.availableKernelModules`
  - `boot.kernelModules` (kvm-amd, amdgpu)
  - `boot.kernelParams` (amdgpu.dcdebugmask, systemd.gpt_auto)
  - `boot.extraModprobeConfig` (thinkpad_acpi)
  - `services.thinkfan` (full config)
  - `hardware.graphics` (AMD GPU, VAAPI)
  - `environment.variables` (VDPAU, LIBVA drivers)
  - `hardware.cpu.amd.updateMicrocode`

### Step 5: Update flake.nix

Add disko module to thinkpad-p14s-g5 in `flake-modules/nixos-systems.nix`:

```nix
thinkpad-p14s-g5 = nixpkgs.lib.nixosSystem {
  # ...
  modules = [
    inputs.disko.nixosModules.disko  # Add this
    ../hosts/thinkpad-p14s-g5
    # ...
  ];
};
```

---

## Installation Day Procedure

### Phase 1: Boot Installer

1. Build NixOS installer with your config baked in (optional, speeds up install):
   ```bash
   # From working system before migration
   nix build .#nixosConfigurations.thinkpad-p14s-g5.config.system.build.toplevel
   ```

2. Boot from NixOS minimal installer USB

3. Connect to network (WiFi or ethernet)

### Phase 2: Partition and Install

```bash
# Clone your config
git clone https://github.com/YOUR_USER/nix-config
cd nix-config

# Run disko to partition and format
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko ./hosts/thinkpad-p14s-g5/disko.nix

# Install NixOS
sudo nixos-install --flake .#thinkpad-p14s-g5 --no-root-passwd

# Reboot
sudo reboot
```

### Phase 3: Post-Install Setup

1. **Re-enroll TPM key** (Secure Boot + TPM unlock):
   ```bash
   # After first boot, enroll TPM key for auto-unlock
   # Note: /dev/nvme0n1p2 is the new LUKS partition (different UUID than before)
   sudo systemd-cryptenroll /dev/nvme0n1p2 --tpm2-device=auto --tpm2-pcrs=0+7

   # If you get "No slot available", first set a recovery password:
   sudo systemd-cryptenroll /dev/nvme0n1p2 --recovery-key
   # Save the recovery key somewhere safe!
   ```

2. **Verify Secure Boot**:
   ```bash
   sbctl status
   # Should show secure boot enabled
   ```

3. **Restore home data**:
   ```bash
   # From NAS
   rsync -avP noams@naspi.local:/backup/thinkpad-p14s-g5/home/ /home/noams/

   # Or from USB
   rsync -avP /run/media/noams/BACKUP/home/ /home/noams/
   ```

4. **Verify btrfs setup**:
   ```bash
   sudo btrfs subvolume list /
   sudo btrfs filesystem df /
   compsize /  # Check compression ratio
   ```

---

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `hosts/thinkpad-p14s-g5/disko.nix` | Create | Disk partitioning with btrfs subvolumes |
| `hosts/thinkpad-p14s-g5/btrfs-config.nix` | Create | Btrfs maintenance, utilities, kernel params |
| `hosts/thinkpad-p14s-g5/btrbk.nix` | Create (optional) | Snapshot automation |
| `hosts/thinkpad-p14s-g5/default.nix` | Modify | Add disko/btrfs imports |
| `hosts/thinkpad-p14s-g5/hardware-configuration.nix` | Modify | Remove filesystem mounts (disko handles) |
| `flake-modules/nixos-systems.nix` | Modify | Add disko module import |

---

## Rollback Strategy

If migration fails:
1. Boot from installer USB
2. Mount backup drive
3. Reinstall with original ext4 config (still in git history)
4. Restore from backup

Data is safe on both NAS and external USB throughout.

---

## Timeline Estimate

| Phase | Duration |
|-------|----------|
| Pre-migration backup | 30-60 min (depends on data size) |
| Create NixOS config changes | 30 min |
| Test build (dry run) | 10 min |
| Boot installer + disko + install | 20-30 min |
| Restore data | 30-60 min |
| TPM enrollment + verification | 15 min |
| **Total** | **2-3 hours** |

---

## Success Criteria

- [ ] System boots with Secure Boot enabled
- [ ] TPM auto-unlock works (no password prompt)
- [ ] All subvolumes mounted correctly (`btrfs subvolume list /`)
- [ ] Compression active (`compsize /` shows ratio)
- [ ] User data restored and accessible
- [ ] Monthly scrub service enabled (`systemctl status btrfs-scrub@-.timer`)
