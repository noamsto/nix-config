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

## SSH Troubleshooting

### Socket Activation

SSH uses socket activation (`startWhenNeeded = true`) to avoid race conditions with systemd-networkd during boot.

**How it works:**
- `sshd.socket` listens on port 22
- When connection arrives, systemd starts `sshd@.service` instance
- No race condition with network coming up

**Check status:**
```bash
# Check socket (should be active/listening)
systemctl status sshd.socket

# Check if any SSH connections are active
systemctl status 'sshd@*.service'

# Restart socket if needed
sudo systemctl restart sshd.socket
```

**If SSH is not accessible:**
1. Check socket is listening:
   ```bash
   sudo systemctl status sshd.socket
   sudo ss -tlnp | grep :22
   ```

2. Check firewall:
   ```bash
   sudo nft list ruleset | grep 22
   ```

3. Check network is up:
   ```bash
   ip addr show
   systemctl status systemd-networkd
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

### Media Automation Stack (*arr + Transmission)

**Configuration**: TRaSH Guides compliant setup for hardlinks and atomic moves

#### Directory Structure
```
/data/
├── torrents/
│   ├── complete/
│   │   ├── tv/      # Sonarr downloads
│   │   ├── movies/  # Radarr downloads
│   │   └── music/   # Future: Lidarr
│   ├── incomplete/  # Active downloads
│   └── watch/       # Drop .torrent files here
└── media/
    ├── tv/          # Final TV library (hardlinked from torrents/complete/tv)
    ├── movies/      # Final movie library (hardlinked from torrents/complete/movies)
    └── music/       # Future: Music library
```

#### Services and Ports

- **Flood** (Port 3000): Modern web UI for Transmission
  - URL: `http://naspi.local:3000`
  - No authentication (local network only)

- **Transmission** (Port 9091): BitTorrent client
  - URL: `http://naspi.local:9091`
  - Downloads to: `/data/torrents/complete`

- **Sonarr** (Port 8989): TV show automation
  - URL: `http://naspi.local:8989`
  - Library: `/data/media/tv`
  - Uses category `tv` in Transmission

- **Radarr** (Port 7878): Movie automation
  - URL: `http://naspi.local:7878`
  - Library: `/data/media/movies`
  - Uses category `movies` in Transmission

- **Prowlarr** (Port 9696): Indexer manager
  - URL: `http://naspi.local:9696`
  - Syncs indexers to Sonarr/Radarr automatically

- **Bazarr** (Port 6767): Subtitle automation
  - URL: `http://naspi.local:6767`
  - Connects to Sonarr/Radarr for subtitle management

#### Post-Deploy Setup

**Automatic Configuration** (via systemd services):

The following are configured automatically on first boot:
- ✅ **Root folders**: `/media/storage/movies` (Radarr), `/media/storage/tv` (Sonarr)
- ✅ **Download clients**: Transmission with proper categories (`movies`, `tv`)
- ✅ **Quality profiles**: 4K with Dolby Atmos via Recyclarr (synced from TRaSH Guides)

**Manual Configuration Required**:

After first deployment, complete these steps:

1. **Prowlarr** (http://naspi:9696) → Add torrent indexers → Connect to Sonarr/Radarr
2. **Bazarr** (http://naspi:6767) → Add Hebrew subtitles → Connect to Sonarr/Radarr → Add subtitle providers

See the [Media Services Setup Guide](#media-services-setup) section below for detailed configuration.

### Monitoring Stack (Prometheus + Grafana)

#### Services and Ports

- **Grafana** (Port 3001): Monitoring dashboards
  - URL: `http://naspi.local:3001`
  - Default login: `admin/admin` (**change immediately!**)
  - Pre-configured Prometheus datasource

- **Prometheus** (Port 9090): Metrics collection
  - URL: `http://naspi.local:9090`
  - Retention: 30 days
  - Scrapes every 15 seconds

- **Node Exporter** (Port 9100): System metrics
  - CPU, RAM, disk I/O, network
  - **Raspberry Pi CPU temperature** (thermal_zone collector)
  - Systemd services status

- **Smartctl Exporter** (Port 9633): SSD health monitoring
  - SMART data for both SSDs
  - Temperature, wear leveling, errors
  - Auto-discovers all disks

- **ZFS Exporter** (Port 9134): ZFS pool metrics
  - Pool status and capacity
  - Scrub status and errors
  - ARC statistics
  - Dataset usage

#### Recommended Grafana Dashboards

After first login, import these community dashboards:

1. **Node Exporter Full** (ID: 1860)
   - Comprehensive system overview
   - **Includes RPi CPU temperature graphs**

2. **ZFS** (ID: 15362)
   - Pool health and capacity
   - ARC cache statistics

3. **Smartctl Exporter** (search community)
   - SSD health and SMART attributes

### Network Services

- **SSH**: Port 22 (password + key authentication)
  - **Socket activation enabled** - Starts on-demand, avoids networkd race conditions
  - Service: `sshd.socket` (not `sshd.service`)
- **NFS**: Port 2049 (exports /data and /media/storage)
- **Samba**: Ports 445, 137, 138 (Windows file sharing)
- **Avahi**: mDNS for `naspi.local` hostname

### Hardware Services

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

# Media services
firefox http://naspi.local:3000  # Flood (Transmission UI)
firefox http://naspi.local:8989  # Sonarr
firefox http://naspi.local:7878  # Radarr
firefox http://naspi.local:9696  # Prowlarr
firefox http://naspi.local:6767  # Bazarr

# Monitoring
firefox http://naspi.local:3001  # Grafana
firefox http://naspi.local:9090  # Prometheus
```

## Media Services Setup

### Automatic Configuration (Already Done!)

The following are configured automatically via systemd services on first boot:

✅ **Root Folders**:
- Radarr: `/media/storage/movies`
- Sonarr: `/media/storage/tv`

✅ **Download Clients**:
- Transmission configured in both Radarr and Sonarr
- Proper categories: `movies` (Radarr), `tv` (Sonarr)
- Remove completed downloads enabled

✅ **Quality Profiles** (via Recyclarr):
- **Radarr**: "4K Remux + WEB" profile
  - 2160p (4K) quality
  - Dolby Atmos audio prioritized (8000 points)
  - TrueHD Atmos, DTS-X support
  - HDR, HDR10+, Dolby Vision
- **Sonarr**: "4K WEB" profile
  - 2160p (4K) quality
  - Dolby Atmos audio prioritized (8000 points)
  - HDR formats supported
- Quality profiles sync daily via `recyclarr-sync.timer`

**Verification**:
```bash
# Check automatic configuration status
sudo systemctl status arr-setup.service

# Check recyclarr sync status
sudo systemctl status recyclarr-sync.service

# Manually trigger recyclarr sync
sudo systemctl start recyclarr-sync.service
```

### 1. Prowlarr Configuration (Manual)

Set up indexers in Prowlarr:

1. Navigate to `http://naspi.local:9696`
2. Go to **Settings** → **General** → Copy the API key
3. Go to **Indexers** → Click **+** to add indexers
4. Add your preferred torrent indexers
5. Go to **Settings** → **Apps** → Click **+** to connect Sonarr:
   - **Sync Level**: Full Sync
   - **Prowlarr Server**: `http://127.0.0.1:9696`
   - **Sonarr Server**: `http://127.0.0.1:8989`
   - **API Key**: (get from Sonarr Settings → General)
6. Repeat for Radarr with `http://127.0.0.1:7878`

### 2. Sonarr Verification

Verify automatic configuration:

1. Navigate to `http://naspi.local:8989`
2. Go to **Settings** → **Media Management**:
   - ✅ Root folder should exist: `/media/storage/tv`
3. Go to **Settings** → **Download Clients**:
   - ✅ Transmission should be configured with category `tv`
4. Go to **Settings** → **Quality Profiles**:
   - ✅ "4K WEB" profile should exist with Dolby Atmos custom formats
5. Optional: Enable "Rename Episodes" and "Unmonitor Deleted Episodes"

**Why categories matter**: When Sonarr sends a download to Transmission with category `tv`, Transmission automatically saves it to `/data/torrents/complete/tv`. When the download completes, Sonarr creates a hardlink from `/data/torrents/complete/tv/Show.Name.S01E01.mkv` to `/media/storage/tv/Show Name/Season 01/Show.Name.S01E01.mkv`. This is instant (atomic move on same filesystem) and uses no extra disk space!

### 3. Radarr Verification

Verify automatic configuration:

1. Navigate to `http://naspi.local:7878`
2. Go to **Settings** → **Media Management**:
   - ✅ Root folder should exist: `/media/storage/movies`
3. Go to **Settings** → **Download Clients**:
   - ✅ Transmission should be configured with category `movies`
4. Go to **Settings** → **Quality Profiles**:
   - ✅ "4K Remux + WEB" profile should exist with Dolby Atmos custom formats
5. Optional: Enable "Rename Movies" and "Unmonitor Deleted Movies"

### 4. Bazarr Configuration (Manual - Hebrew Subtitles)

Configure Bazarr for Hebrew subtitles:

1. Navigate to `http://naspi.local:6767`
2. Go to **Settings** → **Languages**:
   - **Languages Filter**: Add **Hebrew** (`he`)
   - **Default Enabled**: Check Hebrew
   - Click **Save**
3. Go to **Settings** → **Sonarr**:
   - **Address**: `127.0.0.1`
   - **Port**: `8989`
   - **API Key**: (get from Sonarr Settings → General)
   - Click **Test** → **Save**
4. Go to **Settings** → **Radarr**:
   - **Address**: `127.0.0.1`
   - **Port**: `7878`
   - **API Key**: (get from Radarr Settings → General)
   - Click **Test** → **Save**
5. Go to **Settings** → **Providers** → Add subtitle providers:
   - **OpenSubtitles** (requires account)
   - **Subscene**
   - Other Hebrew subtitle sources
6. Go to **Settings** → **Subtitles**:
   - **Subtitle Languages**: Verify Hebrew is selected
   - **Upgrade Previously Downloaded Subtitles**: Enable for quality improvements

### 5. Recyclarr Management

Recyclarr automatically syncs TRaSH Guides quality profiles daily. Manual operations:

```bash
# Check recyclarr configuration
cat /etc/recyclarr/recyclarr.yml

# View recyclarr logs
sudo journalctl -u recyclarr-sync.service

# Manually sync quality profiles
sudo systemctl start recyclarr-sync.service

# Check next scheduled sync
systemctl status recyclarr-sync.timer
```

**What Recyclarr configures**:
- Quality definitions (file size ranges)
- Quality profiles (4K with Dolby Atmos prioritization)
- Custom formats (audio/video quality scoring)
- Does NOT configure: root folders, download clients, indexers (these are handled by arr-setup.service)

### Verifying Hardlinks

After your first download completes, verify hardlinks are working:

```bash
# SSH into naspi
ssh noams@naspi.local

# Find a completed download and its library copy
ls -li /data/torrents/complete/tv/
ls -li /data/media/tv/

# Compare inode numbers (first column)
# If they match, hardlinks are working correctly!
# The file exists in two locations but uses disk space only once
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
├── media-services.nix     # *arr stack + Transmission (TRaSH Guides compliant)
├── monitoring.nix         # Prometheus + Grafana + exporters
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
