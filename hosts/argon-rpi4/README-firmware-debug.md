# Firmware Debugging Guide for Raspberry Pi 4

## Overview

The `/boot/firmware` partition is critical for Raspberry Pi boot process and gets modified by nixos-raspberrypi during rebuilds. This guide helps you monitor and debug these changes.

## Mount Configuration

The firmware partition is mounted with debugging-friendly permissions:

```nix
mountOptions = [
  "umask=0022"         # More permissive (readable by all users)
  "fmask=0133"         # Files: readable by all, writable by owner
  "dmask=0022"         # Directories: accessible by all
  "iocharset=utf8"     # Better character encoding
  "shortname=mixed"    # Mixed case short names
];
```

## Quick Debug Commands

### Instant Status Check
```bash
firmware-debug          # Run comprehensive debug script
firmware-ls              # List firmware files
firmware-tree            # Show directory structure
firmware-space           # Check disk usage
```

### Key Files to Monitor
```bash
firmware-config          # View config.txt
firmware-cmdline         # View cmdline.txt
cat /boot/firmware/*.txt # All text configuration files
```

### Recent Changes
```bash
firmware-changes         # Files modified in last 24 hours
ls -lat /boot/firmware   # Files by modification time
```

## What nixos-raspberrypi Changes

During `nixos-rebuild switch`, these files typically get updated:

1. **`config.txt`** - Hardware configuration, GPU memory, etc.
2. **`cmdline.txt`** - Kernel command line parameters
3. **Boot files** - Kernel, initrd, device tree files
4. **NixOS-specific files** - Generation-specific boot entries

## Monitoring Changes

### Before Rebuild
```bash
# Capture current state
firmware-debug > /tmp/firmware-before.log

# Or create a snapshot
systemctl start firmware-snapshot
```

### After Rebuild
```bash
# Compare changes
firmware-debug > /tmp/firmware-after.log
diff /tmp/firmware-before.log /tmp/firmware-after.log

# Check what changed recently
find /boot/firmware -type f -newer /tmp/firmware-before.log -exec ls -la {} \;
```

### Real-time Monitoring
```bash
# Watch for file changes during rebuild
inotifywait -m -r /boot/firmware --format '%T %w%f %e' --timefmt '%H:%M:%S'

# Or use this one-liner during rebuild
while true; do ls -lat /boot/firmware | head -5; sleep 2; done
```

## Common Issues and Solutions

### Permission Problems
```bash
# If you can't read files
ls -la /boot/firmware
# Should show readable permissions (r--r--r-- or similar)

# If mount options aren't working, remount
sudo umount /boot/firmware
sudo mount -a
```

### Boot Failures After Rebuild
```bash
# Check boot configuration
firmware-config | grep -E "(kernel|initramfs|device_tree)"

# Verify files exist
ls -la /boot/firmware/*nixos*
ls -la /boot/firmware/kernel*
ls -la /boot/firmware/initrd*
```

### Debugging Boot Process
```bash
# Check serial console output (if connected)
sudo dmesg | grep -i firmware

# Check systemd boot logs
journalctl -b | grep -i firmware
journalctl -b | grep -i "raspberry\|rpi"
```

## Backup and Recovery

### Manual Backup Before Changes
```bash
sudo mkdir -p /var/backups/firmware
sudo cp -r /boot/firmware/* "/var/backups/firmware/backup-$(date +%Y%m%d-%H%M%S)/"
```

### Emergency Recovery
If boot fails after rebuild:

1. **Boot from SD card** with working firmware
2. **Mount the problematic drive**:
   ```bash
   sudo mkdir /mnt/broken
   sudo mount /dev/your-ssd-firmware-partition /mnt/broken
   ```
3. **Restore from backup**:
   ```bash
   sudo cp -r /var/backups/firmware/backup-YYYYMMDD-HHMMSS/* /mnt/broken/
   ```

## Advanced Debugging

### Hex Dump Boot Files
```bash
# Check if files are corrupted
hexdump -C /boot/firmware/config.txt | head
file /boot/firmware/*
```

### Compare with Working Configuration
```bash
# If you have another working Pi
rsync -av other-pi:/boot/firmware/ /tmp/working-firmware/
diff -r /boot/firmware/ /tmp/working-firmware/
```

### Boot Loader Analysis
```bash
# Check EEPROM version
vcgencmd bootloader_version

# Update bootloader if needed (careful!)
# sudo rpi-eeprom-update -a
```

## Logs and Monitoring

All debugging output is logged to:
- `/var/log/firmware-snapshots/` - Automatic state captures
- `/var/backups/firmware/` - Manual backups
- System journal for mount/unmount events

## Integration with NixOS Rebuilds

The configuration includes hooks to automatically:
1. Capture firmware state before rebuilds
2. Log changes after rebuilds
3. Provide easy debugging commands
4. Maintain readable permissions for troubleshooting

This ensures you can always see what nixos-raspberrypi changed and debug boot issues effectively.
