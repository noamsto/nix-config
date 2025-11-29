# Archived Scripts

This directory contains scripts that are no longer actively used but are preserved for reference.

## Why Archive?

These scripts have been superseded by newer, more maintainable approaches:
- The unified Raspberry Pi CLI (`scripts/rpi/rpi`) replaces multiple deployment scripts
- Post-setup tasks are now handled by NixOS configuration or systemd services
- Metadata-driven approach eliminates hardcoded values

## Archived Scripts

### Deployment Scripts (Superseded by `scripts/rpi/rpi`)

- **`build-rpi4-installer.sh`** (2024-09-15)
  - Old approach to building installer images
  - **Use instead:** `./scripts/rpi/rpi rpi4-installer build` or `just rpi-build-installer`

- **`naspi-deploy.sh`** (2024-11-14)
  - Old monolithic deployment script with hardcoded logic
  - **Use instead:**
    - Deploy: `./scripts/rpi/rpi naspi deploy` or `just naspi-deploy`
    - Install: `./scripts/rpi/rpi naspi install` or `just naspi-install`

### Post-Setup Scripts (Superseded by NixOS Configuration)

- **`setup-temp-dataset.sh`** (2024-11-24)
  - Manual script to create ZFS temporary dataset
  - **Use instead:** Declare datasets in `hosts/naspi/disko-zfs.nix` or handle via systemd service

- **`naspi-setup-zfs.sh`** (2024-11-14)
  - Manual ZFS pool initialization script
  - **Use instead:** Automated by disko during installation (`./scripts/rpi/rpi naspi install`)

- **`setup-zfs-keyfiles.sh`** (2024-08-30)
  - Manual ZFS encryption key setup
  - **Use instead:** Automated during installation, keys managed by agenix

## Still Active

- **`generate-zfs-key.sh`** - Used by install.sh for ZFS encryption key generation (still needed)

## Migration Guide

If you're looking for old functionality:

| Old Command | New Command |
|-------------|-------------|
| `./scripts/build-rpi4-installer.sh` | `./scripts/rpi/rpi rpi4-installer build` |
| `./scripts/naspi-deploy.sh naspi.local switch` | `./scripts/rpi/rpi naspi deploy` |
| `./scripts/naspi-deploy.sh rpi4-installer install` | `./scripts/rpi/rpi naspi install` |
| `./scripts/setup-temp-dataset.sh` | Declare in disko config or systemd |
| `./scripts/naspi-setup-zfs.sh` | Handled by disko during install |
| `./scripts/setup-zfs-keyfiles.sh` | Handled by agenix and install process |

## Restoration

If you need to restore an archived script (for reference or emergency use):

```bash
cp scripts/archive/<script-name> scripts/
chmod +x scripts/<script-name>
```

Note: Archived scripts may not work with current system configuration without modifications.
