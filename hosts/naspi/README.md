# NasPi - Raspberry Pi 4 NAS with ZFS RAID1

This directory contains the NixOS configuration for a Raspberry Pi 4 Network Attached Storage (NAS) system with ZFS RAID1 mirroring across two 2TB SSDs.

## Hardware Configuration

- **Device**: Raspberry Pi 4 Model B (8GB RAM)
- **Storage**: Dual 2TB PNY SATA SSDs (via USB 3.0)
  - Primary: `ata-PNY_2TB_SATA_SSD_PND09252386160202099`
  - Secondary: `ata-PNY_2TB_SATA_SSD_PND09252386160202096`
- **Expansion Board**: Geekworm X-C1 with PWM fan control
- **Network**: Gigabit Ethernet + WiFi (bcm43455)

## Boot Configuration

### IMPORTANT: SD Card Interference

**This system boots from USB SSD, NOT SD card.** If you encounter boot issues:

1. **Remove any SD card from the Raspberry Pi slot**
2. The SD card can interfere with boot process, causing:
   - "Card did not respond to voltage select! : -110" errors
   - Timeouts waiting for cmd & data inhibit
   - Boot delays and failures
   - Conflicting systemd services from old installations

### Boot Process

1. **EEPROM** tries boot devices in order (should be USB > SD > restart)
2. **USB SSD** boots from `/dev/disk/by-partlabel/BOOT1` (EFI)
3. **ZFS pool** `rpool` mounts as root filesystem
4. **Boot verification** runs automatically to check boot source

### Updating EEPROM Boot Order

To ensure USB boots before SD card:

```bash
# 1. Boot into Raspberry Pi OS (temporary, from SD card if needed)
# 2. Update EEPROM configuration:
sudo rpi-eeprom-config --edit

# 3. Set this boot order:
BOOT_ORDER=0xf46

# Boot order codes:
#   f = SD card
#   4 = USB
#   6 = NVMe
#   1 = Network boot

# 0xf46 means: SD > USB > NVMe (with SD fallback for recovery)
# 0x4f6 means: USB > SD > NVMe (USB priority, recommended)

# 4. Save and reboot
sudo reboot
```

### Checking Current Boot Order

```bash
# View current EEPROM configuration
vcgencmd bootloader_config

# Check boot order
vcgencmd bootloader_config | grep BOOT_ORDER
```

## Filesystem Layout

```
/dev/sda (SSD1)              /dev/sdb (SSD2)
├── FIRMWARE1 (512M, vfat)   ├── FIRMWARE2 (512M, vfat)
│   └── /boot/firmware       │   └── /boot/firmware-backup
├── BOOT1 (1G, vfat)         ├── BOOT2 (1G, vfat)
│   └── /boot                │   └── /boot/boot-backup
└── rpool (ZFS mirror) ←─────┴── rpool (ZFS mirror)
    ├── root (/)
    ├── home (/home)
    ├── nix (/nix)
    ├── var (/var)
    ├── var/log (/var/log)
    ├── docker (/var/lib/docker)
    ├── data (/data) [encrypted]
    ├── media (/media/storage)
    ├── swap (4GB zvol)
    └── reserved (100GB)
```

## Deployment

### Fresh Installation

```bash
# From development machine:
cd /path/to/nix-config

# Build and deploy (will repartition!)
./scripts/naspi-deploy.sh naspi.local install
```

### Updating Existing System

```bash
# From development machine:
./scripts/naspi-deploy.sh naspi.local switch

# Or from the Pi itself:
sudo nixos-rebuild switch --flake .#naspi
```

## Boot Troubleshooting

### Symptoms of SD Card Interference

If you see these errors during boot:

```
Card did not respond to voltage select! : -110
Timeout waiting for cmd & data inhibit
mmc1 busy timeout increasing to: 3200 ms
[FAILED] Failed to start Emergency SSH for debugging
```

**Solution**: Remove the SD card from the Raspberry Pi.

### Verifying Boot Source

After boot, check the boot verification service output:

```bash
# View boot verification log
sudo journalctl -u naspi-boot-verify.service

# Expected output:
# ✓ Booting from ZFS pool (correct)
# ✓ Booting from SSD (correct)
# ✓ No conflicting services detected
```

### Emergency SSH Service Error

If you see `emergency-ssh.service` failing:

**Cause**: The system has leftover configuration from a previous deployment (possibly argon-rpi4 or rpi4-installer config).

**Solution**:
1. Redeploy with correct configuration: `./scripts/naspi-deploy.sh naspi.local install`
2. Or remove SD card (if old config is on SD card)

### Missing Encryption Key File

If you boot into emergency mode and `/boot/zfs-keys/rpool` doesn't exist:

**Cause**: Bug in disko configuration - `postCreateHook` runs before `/mnt/boot` is mounted, so key copying fails.

**Fixed In**: This has been fixed by changing to `postMountHook` which runs after all filesystems are mounted.

**Temporary Recovery** (if on old config):
```bash
# Destroy encrypted dataset
zfs destroy rpool/data

# Recreate without encryption temporarily
zfs create rpool/data
zfs set mountpoint=/data rpool/data
zfs set compression=zstd-3 rpool/data

# Exit emergency mode
systemctl default

# Then redeploy with fixed configuration:
# ./scripts/naspi-deploy.sh naspi.local install
```

### Boot from SD Card Recovery

If you need to boot from SD card for recovery:

1. Flash the `rpi4-installer` image to SD card:
   ```bash
   nix build .#rpi4-installer
   sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress
   ```

2. Boot from SD card
3. Update EEPROM boot order
4. Redeploy to SSD: `./scripts/naspi-deploy.sh naspi.local install`

### Emergency Mode

If the system drops to emergency mode with "Cannot open access to console, the root account is locked":

**Common Causes:**
1. **ZFS root not importing** - Most common issue
2. **Root filesystem mount failure**
3. **Critical systemd services failing**

**Symptoms:**
```
You are in emergency mode
Cannot open access to console
the root account is locked
Press Enter to continue
```

**Diagnosis Steps:**

1. **Check if SD card is inserted** - Remove it if present (see above)

2. **Access emergency console** - Use root password: `nixos`
   - If keyboard doesn't work, SSH might still be available:
     ```bash
     ssh root@naspi.local
     # password: nixos
     ```

3. **Check ZFS pool status** (once in emergency shell):
   ```bash
   # List available pools
   zpool import

   # Check if rpool is imported
   zpool status rpool

   # If not imported, try manual import
   zpool import -f rpool

   # Check root dataset
   zfs list rpool/root
   ```

4. **Check systemd failures**:
   ```bash
   # View failed services
   systemctl --failed

   # Check specific service
   journalctl -u systemd-fsck@dev-disk-by\\x2dlabel-BOOT1.service
   ```

5. **Check boot verification log**:
   ```bash
   journalctl -u naspi-boot-verify.service
   ```

**Fix: ZFS Root Import Issue**

The most common cause is `boot.zfs.forceImportRoot = false` in configuration. This has been fixed in the current config (set to `true`), but if you see this error:

1. Boot into recovery SD card
2. Mount the boot partition:
   ```bash
   mkdir /mnt/boot
   mount /dev/disk/by-label/BOOT1 /mnt/boot
   ```
3. Verify ZFS import settings in system configuration
4. Redeploy: `./scripts/naspi-deploy.sh naspi.local install`

**Security Note:**

The default root password is `nixos` for emergency access. **CHANGE THIS IMMEDIATELY** after first successful boot:

```bash
sudo passwd root
```

For production systems, consider:
- Using SSH key-only authentication
- Disabling root SSH login
- Setting strong passwords for all accounts

## ZFS Management

### Checking Pool Status

```bash
# Pool health
sudo zpool status rpool

# Pool I/O statistics
sudo zpool iostat rpool 1

# Dataset usage
sudo zfs list
```

### Snapshots

Automatic snapshots are configured:
- **Frequent**: 4 snapshots (15-minute intervals)
- **Hourly**: 24 snapshots
- **Daily**: 7 snapshots
- **Weekly**: 4 snapshots
- **Monthly**: 12 snapshots

```bash
# List snapshots
sudo zfs list -t snapshot

# Restore from snapshot
sudo zfs rollback rpool/home@auto-2024-01-15-12:00
```

### Scrubbing

Automatic weekly scrubs are configured. Manual scrub:

```bash
# Start scrub
sudo zpool scrub rpool

# Check progress
sudo zpool status rpool
```

### ZFS Encryption

The `/data` dataset uses ZFS native encryption (AES-256-GCM) with a key file stored at `/boot/zfs-keys/rpool`.

#### Encryption Status

Check if the encryption key is loaded:

```bash
# Check key status for /data dataset
sudo zfs get keystatus rpool/data
# Output: available (key loaded) or unavailable (key not loaded)

# Check encryption properties
sudo zfs get encryption,keylocation,keyformat rpool/data
```

#### Key Loading

The encryption key is automatically loaded during boot by the `zfs-load-data-key.service` systemd service.

**How it works:**
1. Pool imports (`zfs-import-rpool.service`)
2. Key loading service runs (`zfs-load-data-key.service`)
3. Service accesses `/boot/zfs-keys/rpool` → triggers `/boot` automount
4. Service loads key: `zfs load-key rpool/data`
5. ZFS mount service runs with key available
6. `/data` mounts successfully

**Why a service is needed:** ZFS does not automatically load encryption keys from files - you must explicitly run `zfs load-key` before mounting encrypted datasets. The systemd service handles this automatically during boot.

To manually load the key:

```bash
# Load key manually
sudo zfs load-key rpool/data

# Load key from specific file
sudo zfs load-key -L file:///boot/zfs-keys/rpool rpool/data
```

#### Troubleshooting Encryption Issues

**Problem**: `/data` fails to mount with "encryption key not loaded"

**Common Causes:**
1. `/boot` partition not mounted
2. Encryption key file missing or corrupted
3. Incorrect key file permissions

**Diagnosis:**

```bash
# 1. Check key loading service status
sudo systemctl status zfs-load-data-key.service

# 2. View service logs
sudo journalctl -u zfs-load-data-key.service

# 3. Check if /boot is mounted (automount might not have triggered)
mount | grep /boot

# 4. Verify key file exists and has correct permissions
ls -l /boot/zfs-keys/rpool
# Should show: -rw------- 1 root root (600 permissions)

# 3. Check ZFS key status
sudo zfs get keystatus rpool/data

# 4. Check ZFS mount service
sudo systemctl status zfs-mount.service

# 5. Check if ZFS can read the key file
sudo zfs load-key -n rpool/data
# This does a dry-run (doesn't actually load the key)
```

**Manual Recovery:**

```bash
# 1. Ensure /boot is accessible
ls /boot/zfs-keys/rpool

# 2. Manually load the key
sudo zfs load-key rpool/data

# 3. Mount the dataset
sudo zfs mount rpool/data

# 4. Verify mount
df -h | grep /data
```

**Key File Backup:**

The encryption key is critical - back it up securely!

```bash
# Copy key to secure location (do this from another machine)
scp root@naspi.local:/boot/zfs-keys/rpool ~/naspi-zfs-key.backup

# Store offline or in a secure password manager
# Never commit the key to git or store in cloud without encryption!
```

#### Known Boot Messages

You may see these messages during boot - they are **harmless**:

```
media-storage.mount: Mount process exited, code=exited, status=2/INVALIDARGUMENT
zfs_mount_at() failed: mountpoint or dataset is busy
[  OK  ] Mounted /media/storage
```

**Explanation**: ZFS auto-mounts datasets with `canmount=on` before systemd tries to mount them. The "busy" error is cosmetic - the mount succeeds anyway.

## Services

### Enabled Services

- **SSH**: Port 22 (password + key authentication)
- **NFS**: Port 2049 (exports /data and /media/storage)
- **Samba**: Ports 445, 137, 138 (Windows file sharing)
- **Avahi**: mDNS for `naspi.local` hostname
- **Prometheus**: Node exporter + ZFS exporter
- **SMART**: SSD health monitoring
- **X-C1 Fan**: PWM-based temperature control
- **X-C1 Power**: Safe shutdown via power button

### Accessing Services

```bash
# SSH
ssh noams@naspi.local

# NFS mount (from Linux client)
sudo mount -t nfs naspi.local:/data /mnt/naspi

# Samba (from Windows)
\\naspi.local\data
```

## Hardware Management

### Fan Control

The Geekworm X-C1 PWM fan is automatically controlled based on CPU temperature:

```bash
# Check fan service
sudo systemctl status x-c1-fan.service

# View fan script logs
sudo journalctl -u x-c1-fan.service
```

### Power Button

The X-C1 power button triggers safe shutdown:

```bash
# Check power management service
sudo systemctl status x-c1-pwr.service
```

### SSD Health

```bash
# Check SMART status
sudo smartctl -a /dev/sda
sudo smartctl -a /dev/sdb

# View SMART monitoring log
sudo journalctl -u smartd.service
```

## Performance Tuning

### ZFS ARC Settings

- **Maximum ARC**: 2GB (25% of 8GB RAM)
- **Minimum ARC**: 128MB
- **Compressed ARC**: Enabled
- **Prefetch**: Enabled

### Network Settings

Optimized for NAS workloads:
- `net.core.rmem_max`: 128MB
- `net.core.wmem_max`: 128MB
- TCP buffer sizes increased

### Memory Settings

- `vm.swappiness`: 10 (prefer RAM over swap)
- `vm.min_free_kbytes`: 64MB

## File Structure

```
hosts/naspi/
├── README.md              # This file
├── configtxt.nix          # Raspberry Pi config.txt (boot, overlays)
├── default-zfs.nix        # Main ZFS configuration entry point
├── disko-zfs.nix          # Disk partitioning and ZFS pool setup
├── hardware.nix           # Hardware-specific imports
├── system.nix             # Base system configuration
├── zfs-system.nix         # ZFS services and optimization
└── xscript.nix            # Geekworm X-C1 fan and power management
```

## Common Commands

```bash
# Full system rebuild
sudo nixos-rebuild switch --flake .#naspi

# Update flake inputs
nix flake update

# Check ZFS health
sudo zpool status rpool && sudo zfs list

# View boot logs
sudo journalctl -b

# Check boot verification
sudo journalctl -u naspi-boot-verify.service

# Monitor system resources
htop
btop

# Check network connectivity
ping google.com
ip addr show
```

## Backup Strategy

1. **ZFS Snapshots**: Automatic (configured)
2. **ZFS Replication**: Use `syncoid` to replicate to another ZFS system
3. **Cloud Backup**: Use `restic` or `rclone` for offsite backup

```bash
# Replicate to remote ZFS system
syncoid rpool/data user@remote:/backup/naspi/data

# Backup to cloud with restic
restic backup /data --repo s3:s3.amazonaws.com/my-backup
```

## Security

**Current Security Status:**
- Root login via SSH is **enabled** with password authentication
- Default root password: `nixos` (for emergency mode access)
- Default user password: `nixos`
- Firewall is enabled with specific port allowances
- ZFS `/data` dataset is encrypted (AES-256-GCM)
- Encryption key stored in `/boot/zfs-keys/rpool`

**⚠️ IMPORTANT: Change Default Passwords!**

After first successful boot:

```bash
# Change root password
sudo passwd root

# Change user password
passwd
```

### Hardening for Production

1. **Disable Root SSH Login**

   Edit `zfs-system.nix`:
   ```nix
   services.openssh.settings.PermitRootLogin = "no";
   ```

2. **Disable Password Authentication (use keys only)**

   Edit `zfs-system.nix`:
   ```nix
   services.openssh.settings.PasswordAuthentication = false;
   ```

3. **Remove initialPassword (after setting permanent passwords)**

   Edit `system.nix`:
   ```nix
   users.users.root = {
     # Remove initialPassword line
     # Password will be managed via passwd command
   };
   users.users.noams = {
     # Remove initialPassword line
   };
   ```

4. **Rebuild and reboot**:
   ```bash
   sudo nixos-rebuild switch
   sudo reboot
   ```

### SSH Key Management

The noams user already has SSH key authentication enabled. To add more keys:

```bash
# Edit the configuration
vim hosts/naspi/system.nix

# Add to openssh.authorizedKeys.keys array
openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAA... user1@host"
  "ssh-ed25519 AAAA... user2@host"
];

# Rebuild
sudo nixos-rebuild switch
```

## References

- [NixOS ZFS Documentation](https://nixos.wiki/wiki/ZFS)
- [OpenZFS Documentation](https://openzfs.github.io/openzfs-docs/)
- [Raspberry Pi Boot Configuration](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-4-boot-eeprom)
- [Geekworm X-C1 Documentation](https://wiki.geekworm.com/X-C1)
- [Disko Documentation](https://github.com/nix-community/disko)
