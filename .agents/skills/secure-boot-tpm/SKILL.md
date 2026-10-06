---
name: secure-boot-tpm
description: Use when configuring Secure Boot / Lanzaboote, enrolling or re-enrolling TPM2 for LUKS auto-unlock, recovering from failed TPM unlock, handling BIOS updates that invalidate PCRs, or adding Secure Boot to a new host. Applies to nix-config hosts that import nixos/core/lanzaboote.nix (currently tp-g5, tp-g6, halo).
---

# Secure Boot + TPM2 LUKS Auto-Unlock

## Overview

Hosts that import `nixos/core/lanzaboote.nix` replace systemd-boot with **Lanzaboote** (signed EFI bundles) and use **TPM2** to auto-unlock the LUKS root at boot. Lanzaboote auto-generates and auto-enrolls the Secure Boot keys; TPM enrollment is a **one-time manual step** per machine.

Currently imported by: `tp-g5`, `tp-g6`, `halo`.

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

## TPM enrollment: `just tpm-enroll`

Use `just tpm-enroll` for every enrollment: the first one on a new host, and every re-enroll after unlock breaks. It finds the LUKS device backing `/`, which is `/dev/disk/by-partlabel/disk-main-root` on every disko host (g5, g6, halo). It refuses to run if the volume has no password or recovery slot. It enrolls PCR 7 and wipes the old TPM slot only after the new one succeeds, then reseals `keyring-seal`'s credential if that one stopped unsealing too.

A recovery key has no recipe because the printed key must go to a password manager by hand:
```fish
sudo systemd-cryptenroll <dev> --recovery-key
```

Inspect slots with `sudo systemd-cryptenroll <dev>`. The expected set is the original password, a recovery key, and one tpm2 slot.

**Why PCR 7 only.** PCR 7 records Secure Boot state, the db/KEK/dbx contents, and the certificate that verified each boot image. With our own Lanzaboote key enrolled, a boot through anything else (a Microsoft-signed shim, Windows' bootmgr, Secure Boot off) produces a different PCR 7, and the TPM refuses to unseal. PCR 0 hashes the firmware code, so it changes on every BIOS update. What it adds on top is detection of a physical SPI reflash, and a well-built implant can forge the firmware's own measurement anyway. `keyring-seal` binds PCR 7 as well, so both TPM secrets break and recover together.

PCR 7 still changes when a firmware update rewrites db or dbx, when Secure Boot is reset, or when the fTPM is cleared (AMD BIOS updates sometimes do this). All three end at the password prompt, and `just tpm-enroll` fixes all three.

Binding boot-component PCRs (4, 8, 9, 11) breaks unlock on every kernel or initrd update. Leave them out.

## Recovering from failed TPM unlock

**Symptom:** boot stops at the LUKS password prompt instead of auto-unlocking.

Type the password, then run `just tpm-enroll`. Check `sbctl status` first: if Secure Boot came back disabled or in Setup Mode, fix that before enrolling, or the new slot binds to the broken state.

| Cause | Fix |
|---|---|
| Firmware update rewrote db/dbx, or cleared the fTPM | `just tpm-enroll` |
| Secure Boot disabled/reset | Re-enable it in BIOS, boot, `just tpm-enroll` |
| Lanzaboote keys wiped from UEFI | `sbctl enroll-keys` from a working boot (or BIOS Setup Mode), then `just tpm-enroll` |
| "No slot available" when enrolling | Wipe a stale slot; LUKS2 holds 32 |
| TPM not detected | `sudo tpm2_getcap properties-fixed`; fTPM may be disabled in BIOS |

Keep the **recovery key** offline. It is the way back in if both the password and TPM slots are unusable.

## Verification after a rebuild

```fish
sbctl status                                   # secure boot enabled + signed
sudo systemd-cryptenroll <dev>                 # slots present (dev: see just tpm-enroll)
sudo journalctl -b | grep -iE 'tpm|lanzaboote' # boot-time unlock story
```

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgetting `initrd.systemd.enable = true` | No TPM unlock attempt in initrd | Already set in the shared module — don't override |
| Leaving `boot.loader.systemd-boot.enable = true` | Conflicts with Lanzaboote | Shared module does `lib.mkForce false` — don't re-enable |
| Enrolling TPM without a recovery key | Locked out after BIOS update | Always enroll `--recovery-key` too |
| Hand-typing `systemd-cryptenroll` with a guessed device | Wrong partition, or a stale path from a pre-disko layout | `just tpm-enroll` detects it |
| Skipping Setup Mode in BIOS on first install | Secure Boot keys not accepted | Enter BIOS → Secure Boot → Reset to Setup Mode |

## Related

- Rebuild workflow: see `nix-rebuild` skill
- Fan control on same hosts: see `thinkfan-tuning` skill
- Host-specific disko / migration notes: `hosts/tp-g5/BTRFS-MIGRATION.md`, `hosts/tp-g6/disko.nix`
