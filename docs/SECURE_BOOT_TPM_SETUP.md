# Secure Boot + TPM LUKS Auto-Unlock Setup Guide

Enable Secure Boot with Lanzaboote and TPM-based LUKS auto-unlock on NixOS.

## Overview

| Feature | Implementation |
|---------|----------------|
| Secure Boot | Lanzaboote v1.0.0 (signs unified kernel images) |
| Key Generation | Automatic (`autoGenerateKeys`) |
| Key Enrollment | Automatic (`autoEnrollKeys`) |
| LUKS Unlock | TPM2 with PCR binding (0+2+7) |
| Fallback | Password always works |

## What This Protects Against

- Laptop theft (thief can't boot and access data)
- Evil maid attacks (tampering detected, TPM won't unseal)
- Boot chain modifications
- Casual attackers

**Does NOT protect against:** Sophisticated hardware attacks, compromised firmware, or TPM bus sniffing (mitigated by fTPM in CPU on ThinkPads).

---

## NixOS Configuration

### 1. Add Lanzaboote to flake.nix

```nix
# In inputs = { ... }
lanzaboote = {
  url = "github:nix-community/lanzaboote/v1.0.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 2. Host Configuration

Add to your host's `default.nix` (e.g., `hosts/thinkpad-p14s-g5/default.nix`):

```nix
{
  lib,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
    # ... other imports
  ];

  # Secure Boot with Lanzaboote
  boot = {
    loader.systemd-boot.enable = lib.mkForce false; # Lanzaboote replaces systemd-boot
    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
      autoGenerateKeys.enable = true; # Keys created on first rebuild
      autoEnrollKeys.enable = true;   # Keys enrolled automatically when UEFI is in Setup Mode
    };
  };

  environment.systemPackages = with pkgs; [
    sbctl      # Secure boot key management
    tpm2-tools # TPM utilities
  ];
}
```

### 3. Hardware Configuration (TPM Unlock)

Add to your `hardware-configuration.nix`:

```nix
boot.initrd.luks.devices.root = {
  device = "/dev/disk/by-uuid/<YOUR-LUKS-UUID>";
  preLVM = true;
  crypttabExtraOpts = ["tpm2-device=auto"]; # TPM auto-unlock
};
```

---

## Setup Steps (New Machine)

### Step 1: Rebuild System

```bash
git add .
nh os switch .
```

Keys are auto-generated to `/etc/secureboot/keys/`.

### Step 2: Verify Signatures

```bash
sudo sbctl verify
```

All `nixos-generation-*.efi` files should show as signed.

### Step 3: Enter UEFI Setup Mode

1. `systemctl reboot --firmware-setup` (or F1 on ThinkPad)
2. **Security → Secure Boot → Clear/Reset keys** (puts firmware in "Setup Mode")
3. Save and exit (do NOT enable Secure Boot yet)

### Step 4: Auto-Enroll Keys

```bash
reboot
```

With `autoEnrollKeys.enable = true`, systemd-boot automatically enrolls keys when UEFI is in Setup Mode.

### Step 5: Enable Secure Boot

1. Reboot into UEFI (F1)
2. **Security → Secure Boot → Enable**
3. Save and exit

### Step 6: Verify Secure Boot

```bash
bootctl status | grep -i secure
# Should show: Secure Boot: enabled (user)
```

### Step 7: Enroll TPM

```bash
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=0+2+7 \
  /dev/disk/by-uuid/<YOUR-LUKS-UUID>
```

Enter your LUKS password when prompted.

**PCR choices:**
- `0`: Firmware code (detects BIOS updates)
- `2`: Pluggable firmware (detects option ROMs)
- `7`: Secure Boot state (detects key changes)

### Step 8: Final Rebuild and Test

```bash
nh os switch .
reboot
```

System should auto-unlock without password prompt.

---

## Recovery Procedures

### Password Always Works

TPM is an *additional* unlock method. Your LUKS password always works as fallback.

### If System Won't Boot After Secure Boot

1. Enter UEFI (F1)
2. Disable Secure Boot
3. Boot normally
4. Debug with `sudo sbctl verify`
5. Re-enable when fixed

### If TPM Won't Unlock

```bash
# Enter LUKS password at boot prompt (it still works!)
# After booting, re-enroll TPM:
sudo systemd-cryptenroll \
  --wipe-slot=tpm2 \
  --tpm2-device=auto \
  --tpm2-pcrs=0+2+7 \
  /dev/disk/by-uuid/<YOUR-LUKS-UUID>
```

### After BIOS/Firmware Updates

BIOS updates may change PCR values. Re-enroll TPM if unlock fails:

```bash
# Enter password at boot, then:
sudo systemd-cryptenroll \
  --wipe-slot=tpm2 \
  --tpm2-device=auto \
  --tpm2-pcrs=0+2+7 \
  /dev/disk/by-uuid/<YOUR-LUKS-UUID>
```

### Nuclear Option

```bash
# Boot from NixOS USB
sudo cryptsetup luksOpen /dev/nvme0n1p2 root
sudo mount /dev/mapper/root /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot
sudo nixos-enter

# Disable lanzaboote in config, rebuild
# Or boot previous generation from boot menu
```

---

## Quick Reference

```bash
# Check Secure Boot status
bootctl status

# Verify signatures
sudo sbctl verify

# List LUKS key slots
sudo cryptsetup luksDump /dev/disk/by-uuid/<YOUR-LUKS-UUID>

# Re-enroll TPM
sudo systemd-cryptenroll \
  --wipe-slot=tpm2 \
  --tpm2-device=auto \
  --tpm2-pcrs=0+2+7 \
  /dev/disk/by-uuid/<YOUR-LUKS-UUID>
```

---

## Current Hosts

| Host | LUKS UUID | Status |
|------|-----------|--------|
| thinkpad-p14s-g5 | `8d260438-dcbf-414e-9f49-03b9c86cc8b9` | Configured |

---

## References

- [Lanzaboote v1.0.0 Changelog](https://github.com/nix-community/lanzaboote/blob/v1.0.0/CHANGELOG.md)
- [Lanzaboote GitHub](https://github.com/nix-community/lanzaboote)
- [NixOS Wiki - Secure Boot](https://wiki.nixos.org/wiki/Secure_Boot)
