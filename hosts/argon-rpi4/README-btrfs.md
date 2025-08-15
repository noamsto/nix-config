# Btrfs Management Guide for Raspberry Pi 4

## Quick Commands

### Snapshots
```bash
# Create manual snapshot
sudo btrfs subvolume snapshot / /.snapshots/root-$(date +%Y%m%d-%H%M%S)
sudo btrfs subvolume snapshot /home /.snapshots/home-$(date +%Y%m%d-%H%M%S)

# List snapshots
sudo btrfs subvolume list /.snapshots

# Delete snapshot
sudo btrfs subvolume delete /.snapshots/root-20231201-120000
```

### Before NixOS Rebuild
```bash
# Create pre-update snapshot
sudo btrfs subvolume snapshot / /.snapshots/pre-nixos-$(date +%Y%m%d-%H%M%S)

# If rebuild fails, rollback:
# 1. Boot from snapshot in GRUB (if configured)
# 2. Or manually restore:
sudo mount -o subvol=@ /dev/disk/by-label/nixos /mnt
sudo mv /mnt /mnt.broken
sudo btrfs subvolume snapshot /.snapshots/pre-nixos-YYYYMMDD-HHMMSS /mnt
```

### System Maintenance
```bash
# Check filesystem
sudo btrfs filesystem show
sudo btrfs filesystem usage /

# Check compression ratios
sudo compsize /
sudo compsize /home
sudo compsize /nix

# Manual scrub (check for errors)
sudo btrfs scrub start /
sudo btrfs scrub status /

# Balance filesystem (defrag)
sudo btrfs balance start -dusage=50 /
```

### Space Management
```bash
# Show space usage by subvolume
sudo btrfs filesystem du -s /@*

# Show compression stats
sudo btrfs filesystem usage /

# Find large files
sudo du -h / | grep -E '^[0-9.]+G'
```

## Mount Options Explained

- `compress=zstd:3` - Compression level 3 (good balance)
- `compress=zstd:1` - Faster compression for /nix (frequent access)
- `noatime` - Don't update access times (reduces writes)
- `ssd` - SSD optimizations
- `space_cache=v2` - Better free space tracking
- `commit=120` - Commit transactions every 2 minutes (reduces writes)

## Subvolume Layout

- `@` - Root filesystem (/)
- `@home` - User data (/home)
- `@nix` - Nix store (/nix) - optimized for frequent access
- `@var` - Variable data (/var) - logs, caches
- `@snapshots` - Snapshot storage (/.snapshots)
- `@swap` - Swap file location (/swap)

## Performance Tips

1. **Compression**: Saves 20-40% space and reduces SSD wear
2. **Snapshots**: Take before major changes, clean up old ones
3. **Scrub**: Run weekly to catch silent corruption
4. **Balance**: Run monthly if filesystem gets fragmented
5. **Monitor**: Check `compsize` output to see compression effectiveness

## Troubleshooting

### Out of Space
```bash
# Check actual usage vs allocated
sudo btrfs filesystem usage /

# Balance to free up space
sudo btrfs balance start -dusage=10 /
```

### Performance Issues
```bash
# Check for fragmentation
sudo btrfs filesystem defragment -r -v /

# Check if compression is working
sudo compsize /
```

### Recovery
If system won't boot, boot from installer and:
```bash
sudo mount -o subvol=@snapshots /dev/your-device /mnt
# List available snapshots
sudo btrfs subvolume list /mnt
# Mount and chroot to good snapshot
```
