---
name: secure-boot-tpm
description: Use when configuring Secure Boot / Lanzaboote, enrolling or re-enrolling TPM2 for LUKS auto-unlock, recovering from failed TPM unlock, handling BIOS updates that invalidate PCRs, or adding Secure Boot to a new host. Applies to nix-config hosts that import nixos/core/lanzaboote.nix (currently thinkpad-p14s-g5, thinkpad-p14s-g6).
---

# Secure Boot + TPM2 LUKS Auto-Unlock

## Overview

Hosts that import `nixos/core/lanzaboote.nix` replace systemd-boot with **Lanzaboote** (signed EFI bundles) and use **TPM2** to auto-unlock the LUKS root at boot. Lanzaboote auto-generates and auto-enrolls the Secure Boot keys; TPM enrollment is a **one-time manual step** per machine.

Currently imported by: `thinkpad-p14s-g5`, `thinkpad-p14s-g6`.

## When to use

- Adding Lanzaboote / Secure Boot to a new host
- Enrolling TPM after a fresh install or disk migration
- TPM unlock stopped working (BIOS update, PCR change, firmware reflash)
- Debugging "no key available" / password fallback at boot
- Verifying Secure Boot state

## Quick Reference

| Tool | Purpose |
|---|---|
| `sbctl status` | Verify Secure Boot state + key enrollment |
| `systemd-cryptenroll` | Manage LUKS key slots (TPM, recovery key, password) |
| `tpm2_getcap properties-fixed` | Check TPM2 is detected |
| `/etc/secureboot` | Lanzaboote PKI bundle location (`pkiBundle`) |

Both tools are installed by `nixos/core/lanzaboote.nix` — no extra packages needed on enrolled hosts.

## The shared module

```nix
# nixos/core/lanzaboote.nix (imported per-host)
imports = [inputs.lanzaboote.nixosModules.lanzaboote];

boot = {
  initrd.systemd.enable = true;                # REQUIRED for TPM unlock
  loader.systemd-boot.enable = lib.mkForce false;
  lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
    autoGenerateKeys.enable = true;
    autoEnrollKeys.enable = true;
  };
};
```

Per-host hardware config enables TPM at the initrd:
```nix
# hosts/<host>/hardware-configuration.nix
boot.initrd.luks.devices.root.crypttabExtraOpts = ["tpm2-device=auto"];
```

## Adding to a new host

1. Import the shared module in `hosts/<host>/default.nix`:
   ```nix
   imports = [
     # ...
     ../../nixos/core/lanzaboote.nix
   ];
   ```
2. In hardware-configuration.nix, add `crypttabExtraOpts = ["tpm2-device=auto"];` to the LUKS root device.
3. Rebuild → reboot. First boot auto-generates keys and enrolls into UEFI. On some ThinkPads you must enter BIOS Setup once to accept key enrollment (Secure Boot → Reset to Setup Mode, then reboot).
4. Do the TPM enrollment step below.

## TPM enrollment (one-time, per machine)

**Current recommended invocation** (matches BTRFS-MIGRATION.md in hosts/thinkpad-p14s-g5/):

```fish
# Bind to PCRs 0 (firmware) and 7 (Secure Boot policy)
sudo systemd-cryptenroll /dev/nvme0n1p2 --tpm2-device=auto --tpm2-pcrs=0+7

# ALSO enroll a recovery key — required if PCRs change and you're locked out
sudo systemd-cryptenroll /dev/nvme0n1p2 --recovery-key
# Save the printed recovery key somewhere safe (password manager, offline).
```

Verify slots:
```fish
sudo systemd-cryptenroll /dev/nvme0n1p2
```

You should see: password slot (original), tpm2 slot, and a recovery slot.

**PCR selection rationale:**
- **0** — firmware — catches BIOS tampering
- **7** — Secure Boot state/policy — catches Secure Boot disabled or key changes

Binding more PCRs (e.g. 4, 8, 9) increases the chance that a routine kernel/initrd update invalidates the TPM slot. `0+7` is the standard balance.

## Recovering from failed TPM unlock

**Symptom:** System drops to password prompt at boot instead of auto-unlocking.

**Diagnose:**
```fish
# Was the TPM detected?
sudo tpm2_getcap properties-fixed

# Are slots still present?
sudo systemd-cryptenroll /dev/nvme0n1p2

# Secure Boot still healthy?
sbctl status
```

**Common causes:**

| Cause | Fix |
|---|---|
| BIOS/firmware update changed PCR 0 | Re-enroll: `sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto --tpm2-pcrs=0+7 /dev/nvme0n1p2` |
| Secure Boot disabled/reset (PCR 7 change) | Re-enable SB, boot, re-enroll TPM |
| TPM cleared in BIOS | Re-enroll from scratch |
| "No slot available" when enrolling | First add a recovery key (`--recovery-key`) so the LUKS header has free slots |
| Lanzaboote keys wiped from UEFI | `sbctl enroll-keys` inside a working boot, or re-enroll via BIOS Setup Mode |

Always keep the **recovery key** somewhere offline — it's your only way back in if both the password and TPM slots are unusable.

## Verification after a rebuild

```fish
sbctl status                                   # secure boot enabled + signed
sudo systemd-cryptenroll /dev/nvme0n1p2        # slots present
sudo journalctl -b | grep -iE 'tpm|lanzaboote' # boot-time unlock story
```

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgetting `initrd.systemd.enable = true` | No TPM unlock attempt in initrd | Already set in the shared module — don't override |
| Leaving `boot.loader.systemd-boot.enable = true` | Conflicts with Lanzaboote | Shared module does `lib.mkForce false` — don't re-enable |
| Enrolling TPM without a recovery key | Locked out after BIOS update | Always enroll `--recovery-key` too |
| Hardcoding `/dev/nvme0n1p2` | Wrong partition on other hosts | Verify with `lsblk` / `blkid` first |
| Re-enrolling without `--wipe-slot=tpm2` | Multiple stale TPM slots | Wipe old slot before enrolling new |
| Skipping Setup Mode in BIOS on first install | Secure Boot keys not accepted | Enter BIOS → Secure Boot → Reset to Setup Mode |

## Related

- Rebuild workflow: see `nix-rebuild` skill
- Fan control on same hosts: see `thinkfan-tuning` skill
- Host-specific disko / migration notes: `hosts/thinkpad-p14s-g5/BTRFS-MIGRATION.md`, `hosts/thinkpad-p14s-g6/disko.nix`
