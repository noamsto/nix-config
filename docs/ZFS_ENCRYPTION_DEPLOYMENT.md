# ZFS Encryption with nixos-anywhere Integration

This document describes the integrated approach to deploying NixOS with ZFS encryption using nixos-anywhere and disko.

## Overview

The system automatically:

1. **Generates** a 256-bit encryption key locally
2. **Deploys** the key securely via nixos-anywhere's `--extra-files`
3. **Configures** ZFS datasets with native encryption
4. **Sets up** automatic unlock using key files
5. **Cleans up** temporary key files for security

## Architecture

### Components

- **`scripts/generate-zfs-key.sh`** - Generates encryption keys locally
- **`hosts/naspi/disko-zfs.nix`** - Disko configuration with ZFS encryption
- **`scripts/naspi-deploy.sh`** - Enhanced deployment script with key handling
- **`hosts/naspi/zfs-system.nix`** - ZFS system configuration for automatic unlock

### Security Model

```
┌─────────────────────────────────────────────────────────────┐
│ Deployment Process                                          │
├─────────────────────────────────────────────────────────────┤
│ 1. Generate key locally (/tmp/zfs-rpool-key)                │
│ 2. Deploy via nixos-anywhere --extra-files                  │
│ 3. Disko postCreateHook installs key to /boot/zfs-keys/     │
│ 4. ZFS datasets configured with file:// keylocation         │
│ 5. Local key file cleaned up                                │
└─────────────────────────────────────────────────────────────┘
```

## Usage

### Fresh Installation with ZFS Encryption

```bash
# Deploy with automatic ZFS encryption setup
./scripts/naspi-deploy.sh naspi.local install
```

This will:

- Generate a random 256-bit encryption key
- Deploy NixOS with ZFS RAID1 mirror
- Configure encrypted `/data` dataset
- Set up automatic unlock
- Clean up temporary files

### What Gets Encrypted

The configuration encrypts the **`/data`** dataset only:

- **Encrypted**: `/data` (your NAS storage)
- **Unencrypted**: `/`, `/home`, `/nix`, `/var` (for boot and system performance)

This provides:

- ✅ **Data protection** for your important files
- ✅ **Fast boot** (no encryption overhead for system datasets)
- ✅ **Automatic unlock** (no password prompts)

### Extending Encryption

To encrypt additional datasets, modify `hosts/naspi/disko-zfs.nix`:

```nix
# Example: Encrypt home directories too
"home" = {
  type = "zfs_fs";
  mountpoint = "/home";
  options = {
    canmount = "on";
    compression = "zstd-3";
    "com.sun:auto-snapshot" = "true";
    # Add encryption
    encryption = "aes-256-gcm";
    keyformat = "raw";
    keylocation = "file:///boot/zfs-keys/rpool";
  };
};
```

## Key Management

### Key Storage Location

- **Production**: `/boot/zfs-keys/rpool` (600 permissions, root-only)
- **Deployment**: `/tmp/zfs-rpool-key` (temporary, auto-cleaned)

### Key Security

- Keys stored on unencrypted boot partition
- Physical access to system = access to encrypted data
- Suitable for home NAS, not high-security environments

### Key Backup

The system automatically creates systemd tmpfiles rules to ensure proper key directory structure. For manual backup:

```bash
# Backup key (run on target system)
sudo cp /boot/zfs-keys/rpool /root/zfs-key-backup-$(date +%Y%m%d).key
```

## Troubleshooting

### Key File Not Found

If deployment shows "Warning: No ZFS key found":

1. Ensure `generate-zfs-key.sh` ran successfully
2. Check `/tmp/zfs-rpool-key` exists before nixos-anywhere
3. Verify `--extra-files` parameter in deployment script

### ZFS Won't Auto-unlock

Check the ZFS system configuration:

```bash
# On target system
sudo zfs get keylocation rpool/data
sudo zfs get keystatus rpool/data
```

Should show:

- `keylocation: file:///boot/zfs-keys/rpool`
- `keystatus: available`

### Manual Key Recovery

If you need to manually set up keys:

```bash
# Generate new key
sudo dd if=/dev/urandom of=/boot/zfs-keys/rpool bs=32 count=1
sudo chmod 600 /boot/zfs-keys/rpool

# Update ZFS to use it
sudo zfs change-key -o keyformat=raw -o keylocation=file:///boot/zfs-keys/rpool rpool/data
```

## Comparison with Alternatives

| Approach             | Security  | Convenience | Complexity |
| -------------------- | --------- | ----------- | ---------- |
| **Key Files (This)** | Medium    | High        | Low        |
| Manual Password      | High      | Low         | Low        |
| TPM (N/A on RPi4)    | Very High | High        | Medium     |
| Network Keys         | High      | Medium      | High       |
| USB Keys             | High      | Medium      | Medium     |

## Files Modified

- `hosts/naspi/disko-zfs.nix` - Added ZFS encryption and postCreateHook
- `scripts/naspi-deploy.sh` - Integrated key generation and deployment
- `scripts/generate-zfs-key.sh` - New key generation utility
- `hosts/naspi/zfs-system.nix` - Configured for automatic unlock

## Next Steps

After successful deployment:

1. **Test reboot** to verify automatic unlock
2. **Backup key file** to secure location
3. **Configure NAS services** (Samba, NFS already configured)
4. **Set up monitoring** (Prometheus exporters included)

The system provides a good balance of security and convenience for home NAS use.
