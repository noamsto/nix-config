# Secure Boot + TPM LUKS Auto-Unlock Setup Guide

This guide walks through enabling Secure Boot with Lanzaboote and TPM-based LUKS auto-unlock on NixOS.

**Target systems:** thinkpad-p14s, thinkpad-p14s-g5

**Date researched:** 2025-12-21

## Current Setup

| Component       | Status                                                          |
| --------------- | --------------------------------------------------------------- |
| Boot            | systemd-boot (UEFI)                                             |
| Root encryption | LUKS (`/dev/disk/by-uuid/a93bff25-8164-4b2f-ae87-19311112c84c`) |
| Data partition  | Separate encrypted (`/home/noams/Data`)                         |
| TPM2            | Available (ThinkPad P14s has fTPM)                              |
| Secure Boot     | Currently disabled                                              |

---

## Safety Guarantees

### Your data is safe because:

1. **LUKS encryption is independent of bootloader** - Encrypted partitions remain encrypted regardless of boot configuration
2. **Password always works** - TPM is an _additional_ unlock method, not a replacement
3. **NixOS generations** - Can always boot older generations if new config fails
4. **Recovery USB** - Works regardless of Secure Boot state

### Recovery paths:

| Failure                    | Recovery                                           |
| -------------------------- | -------------------------------------------------- |
| Secure Boot blocks boot    | Enter UEFI -> disable Secure Boot -> boot normally |
| TPM won't release key      | Enter LUKS password manually (still works)         |
| Lanzaboote misconfigured   | Boot previous NixOS generation                     |
| Keys not enrolled properly | Re-run enrollment from booted system               |
| Everything broken          | Boot NixOS USB, `nixos-enter`, rebuild             |

---

## Known Security Considerations

### What TPM + Secure Boot protects against:

- Laptop theft (thief can't boot and access data)
- Evil maid attacks (tampering detected, TPM won't unseal)
- Boot chain modifications
- Casual attackers

### What it does NOT protect against:

- Sophisticated attackers with hardware access and time
- Compromised firmware
- TPM bus sniffing (mitigated by fTPM in CPU on ThinkPads)

### CVE-2025-4382

GRUB-based TPM auto-decrypt vulnerability. **Does not affect Lanzaboote** (uses systemd-boot).

---

## Implementation Steps

### Phase 0: Preparation (CRITICAL - Do First)

```bash
# 1. Create a NixOS recovery USB
# Download minimal ISO from nixos.org and flash to USB

# 2. Verify current system boots correctly
bootctl status

# 3. IMPORTANT: Make sure you KNOW your LUKS password!
# This is your fallback - it will always work

# 4. Check TPM is available
cat /sys/class/tpm/tpm0/device/description
# Should show: "TPM 2.0 Device" or similar
```

---

### Phase 1: Add Lanzaboote to Flake

Edit `flake.nix`, add to inputs section:

```nix
# In the inputs = { ... } block, add:
lanzaboote = {
  url = "github:nix-community/lanzaboote/v0.4.1";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

---

### Phase 2: Create Secure Boot Module

Create file `nixos/core/secure-boot.nix`:

```nix
{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  boot = {
    # REQUIRED: systemd in initrd for TPM unlock
    initrd.systemd.enable = true;

    # Disable systemd-boot (lanzaboote replaces it)
    loader.systemd-boot.enable = lib.mkForce false;

    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
    };
  };

  # Tools for managing secure boot
  environment.systemPackages = with pkgs; [
    sbctl        # Secure boot key management
    tpm2-tools   # TPM utilities
  ];
}
```

Then import it in `nixos/default.nix` or your host configuration.

---

### Phase 3: Generate Secure Boot Keys

```bash
# Enter dev shell with sbctl
nix shell nixpkgs#sbctl

# Generate secure boot keys
sudo sbctl create-keys

# Verify keys created
ls -la /etc/secureboot/keys/
# Should see: db/, KEK/, PK/ directories with .key and .pem files
```

---

### Phase 4: Rebuild System

```bash
# Stage all changes
git add .

# Rebuild - installs lanzaboote but Secure Boot isn't enabled in UEFI yet
nh os switch .

# Verify lanzaboote signed the boot files
sudo sbctl verify

# Expected output:
# Signed: /boot/EFI/BOOT/BOOTX64.EFI
# Signed: /boot/EFI/Linux/nixos-generation-*.efi
# Not signed: /boot/EFI/Linux/linux-*.efi  <- THIS IS NORMAL
```

**CHECKPOINT:** System boots normally. Secure Boot not yet enabled. Can revert by removing the module.

---

### Phase 5: Enter UEFI Setup Mode

1. Reboot: `systemctl reboot --firmware-setup` (or F1/F12 on ThinkPad)
2. Navigate to **Security -> Secure Boot**
3. **Clear/Reset Secure Boot keys** (puts firmware in "Setup Mode")
4. Navigate to **Security -> Set Supervisor Password** and set one
5. **Save and exit** (do NOT enable Secure Boot yet)

---

### Phase 6: Enroll Keys

```bash
# Enroll your keys + Microsoft keys
sudo sbctl enroll-keys --microsoft

# The --microsoft flag:
# - Prevents breaking firmware updates via fwupd
# - Required by some hardware
# - Acceptable security tradeoff for most users
```

---

### Phase 7: Enable Secure Boot in UEFI

1. Reboot into UEFI (F1/F12 or `systemctl reboot --firmware-setup`)
2. **Security -> Secure Boot -> Enable**
3. Save and exit
4. System should boot normally

---

### Phase 8: Verify Secure Boot Works

```bash
bootctl status

# Look for these lines:
#   Secure Boot: enabled (user)
#   TPM2 Support: yes
```

**CHECKPOINT:** Secure Boot is working. LUKS password still required. If anything is wrong, disable Secure Boot in UEFI and boot normally.

---

### Phase 9: Add TPM Auto-Unlock (Optional)

Only proceed after Secure Boot is confirmed working.

#### Step 9a: Enroll TPM key

```bash
# Enroll TPM key for root partition
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=0+2+7 \
  /dev/disk/by-uuid/a93bff25-8164-4b2f-ae87-19311112c84c

# Enter your LUKS password when prompted
```

**PCR choices:**

- `0`: Firmware code (detects BIOS updates)
- `2`: Pluggable firmware (detects option ROMs)
- `7`: Secure Boot state (detects key changes)
- NOT including `12` (kernel command line) - avoids breaking on kernel param changes

#### Step 9b: Update NixOS configuration

Edit `hosts/thinkpad-p14s/hardware-configuration.nix`:

```nix
boot.initrd.luks.devices.root = {
  device = "/dev/disk/by-uuid/a93bff25-8164-4b2f-ae87-19311112c84c";
  preLVM = true;
  crypttabExtraOpts = [ "tpm2-device=auto" ];
};
```

#### Step 9c: Rebuild and test

```bash
git add .
nh os switch .
reboot
```

System should now auto-unlock without password prompt!

---

## Recovery Procedures

### If System Won't Boot After Secure Boot Enabled

```bash
# 1. Enter UEFI (F1/F12 during boot)
# 2. Disable Secure Boot
# 3. Boot normally
# 4. Re-verify signatures:
sudo sbctl verify

# 5. Re-enroll keys if needed:
sudo sbctl enroll-keys --microsoft

# 6. Re-enable Secure Boot in UEFI
```

### If TPM Won't Unlock (Password Still Works)

```bash
# 1. Enter your LUKS password at boot prompt (it still works!)

# 2. After booting, re-enroll TPM:
sudo systemd-cryptenroll \
  --wipe-slot=tpm2 \
  --tpm2-device=auto \
  --tpm2-pcrs=0+2+7 \
  /dev/disk/by-uuid/a93bff25-8164-4b2f-ae87-19311112c84c
```

### Nuclear Option: Everything Is Broken

```bash
# 1. Boot from NixOS USB

# 2. Open LUKS:
sudo cryptsetup luksOpen /dev/nvme0n1p2 root
# (adjust partition as needed, enter your password)

# 3. Mount filesystems:
sudo mount /dev/mapper/root /mnt
sudo mount /dev/nvme0n1p1 /mnt/boot

# 4. Enter the system:
sudo nixos-enter

# 5. Disable lanzaboote temporarily by editing config:
#    Set lanzaboote.enable = false
#    Set loader.systemd-boot.enable = true

# 6. Rebuild:
nixos-rebuild switch

# 7. Exit and reboot
exit
reboot

# 8. Disable Secure Boot in UEFI if needed
```

---

## After BIOS/Firmware Updates

BIOS updates may change PCR values, causing TPM to refuse unlock.

```bash
# If TPM unlock fails after BIOS update:
# 1. Enter LUKS password manually
# 2. Re-enroll TPM:
sudo systemd-cryptenroll \
  --wipe-slot=tpm2 \
  --tpm2-device=auto \
  --tpm2-pcrs=0+2+7 \
  /dev/disk/by-uuid/a93bff25-8164-4b2f-ae87-19311112c84c
```

---

## Data Partition

Your `/home/noams/Data` partition is separately encrypted. Options:

1. **Keep manual unlock** - Most secure, enter password once at boot
2. **Key file on encrypted root** - Auto-unlocks after root unlocks (recommended)
3. **TPM unlock** - Same process as root partition

---

## Quick Reference

```bash
# Check Secure Boot status
bootctl status

# Verify signatures
sudo sbctl verify

# Re-enroll TPM (after BIOS update or if broken)
sudo systemd-cryptenroll \
  --wipe-slot=tpm2 \
  --tpm2-device=auto \
  --tpm2-pcrs=0+2+7 \
  /dev/disk/by-uuid/a93bff25-8164-4b2f-ae87-19311112c84c

# List LUKS key slots
sudo cryptsetup luksDump /dev/disk/by-uuid/a93bff25-8164-4b2f-ae87-19311112c84c
```

---

## References

- [Lanzaboote GitHub](https://github.com/nix-community/lanzaboote)
- [Jon Seager's Guide](https://jnsgr.uk/2024/04/nixos-secure-boot-tpm-fde/)
- [Karun's NixOS Guide](https://karun.sndh.dev/posts/nixos-secure-boot-tpm-luks/)
- [Lani Akita's Comprehensive Guide](https://laniakita.com/blog/nixos-fde-tpm-hm-guide)
- [NixOS Wiki - Secure Boot](https://wiki.nixos.org/wiki/Secure_Boot)
