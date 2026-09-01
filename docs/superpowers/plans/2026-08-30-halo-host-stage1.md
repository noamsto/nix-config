# Halo Host — Stage 1 (bootable base) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Get the Minisforum MS-S1 MAX (Strix Halo) booting NixOS from this flake as host `halo` — encrypted disk, Secure Boot, TPM2 auto-unlock, SSH and Tailscale reachable — and then measure the two hardware unknowns that Stage 2 depends on.

**Architecture:** A new host directory `hosts/halo/` registered in `lib/host-configs.nix`, `flake-modules/nixos-systems.nix`, and `flake-modules/home-manager.nix`, following the `thinkpad-p14s-g6` pattern. Disk layout is declarative via disko. Installation is driven remotely from the laptop with `just bootstrap-host`, which wraps `nixos-anywhere`: it seeds the pre-generated agenix host key via `--extra-files` so secrets decrypt during activation, supplies the LUKS passphrase via `--disk-encryption-keys`, and writes the real hardware config back into the repo.

**Tech Stack:** NixOS (nixos-unstable), flake-parts, disko, lanzaboote, agenix, nixos-hardware.

**Spec:** `docs/superpowers/specs/2026-08-29-halo-host-design.md`

**Explicitly out of scope for Stage 1** (these are Stage 2, and depend on Task 8/9 findings): Steam, greetd, gamescope, gamemode, llama.cpp / llama-server, Sunshine, podman containers.

---

## Context an engineer needs before starting

**Read the spec first.** This plan implements only its "Topology", "Storage", "Boot", and host-registration sections, plus the two validation experiments from "Memory split" and "Known risk".

**Three repo conventions that will bite you:**

1. **Pre-commit hooks reformat files, so the first `git commit` fails.** `alejandra`, `deadnix`, `statix`, and `prettier` run as hooks. On any commit touching `.nix`, alejandra rewrites the file and the hook exits non-zero with "files were modified by this hook". This is expected: `git add` the reformatted files and re-run the *same* commit. It passes the second time. Do not change the commit message.

2. **Nix only sees git-tracked files.** A new file that hasn't been `git add`ed does not exist as far as flake evaluation is concerned — you'll get "path does not exist" or "file not found". `git add` new files *before* running any `nix eval` or `nix build`. See the `nix-rebuild` skill.

3. **Work happens in the worktree** at `~/Data/git/.worktrees/noams/nix-config/feat-175-halo-host`, on branch `feat/175-halo-host`. All paths below are relative to it.

**Two spec corrections already folded into this plan:**

- `machine.type` is `"desktop"`, not `"server"`. `nixos/core/pc.nix:9` gates pipewire (with `alsa.support32Bit`, which Steam needs) and bluetooth (wireless controller) behind `isPC`, which is false for `"server"`.
- SSH and Tailscale need no host-level configuration — `services.openssh.enable` is set in `nixos/core/networking.nix:115` and `nixos/services/tailscale.nix` is imported via `nixos/default.nix`.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/host-configs.nix` | *Modify.* Add the `halo` entry — the shared source of truth read by both NixOS and standalone Home Manager. |
| `flake-modules/nixos-systems.nix` | *Modify.* Register `nixosConfigurations.halo`. |
| `flake-modules/home-manager.nix` | *Modify.* Register `homeConfigurations."noams@halo"` (entries are explicit here, not auto-detected). |
| `hosts/halo/disko.nix` | *Create.* Declarative disk layout: GPT, 2 GB ESP, LUKS, btrfs subvolumes. |
| `hosts/halo/hardware-configuration.nix` | *Create.* Kernel modules and microcode. Hand-written minimally so the config evaluates before the machine exists; regenerated during install. |
| `hosts/halo/default.nix` | *Create.* Host entry point: imports, options, kernel parameters, nix build settings. |
| `hosts/halo/host_secrets.nix` | *Create.* agenix identity path override (`lib.mkForce`) plus halo's own secrets. Required: see Task 4. |

---

## Task 1: Register the host in shared config

**Files:**
- Modify: `lib/host-configs.nix:34` (after the `thinkpad-p14s-g6` block)
- Modify: `flake-modules/home-manager.nix:22`

- [ ] **Step 1: Verify the host does not yet evaluate**

```bash
cd ~/Data/git/.worktrees/noams/nix-config/feat-175-halo-host
nix eval .#nixosConfigurations.halo.config.networking.hostName
```

Expected: FAIL — `error: attribute 'halo' missing`.

- [ ] **Step 2: Add the `halo` entry to `lib/host-configs.nix`**

Insert after the closing `};` of the `thinkpad-p14s-g6` block, before `mbp-m4-pro`:

```nix
  halo = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noamstolero@gmail.com";
    hostname = "halo";
    desktop.mode = "none";
    # "desktop" not "server": nixos/core/pc.nix gates pipewire (alsa.support32Bit,
    # needed by Steam) and bluetooth (controller) behind machine.isPC.
    machine.type = "desktop";
    profile = "personal";
  };
```

Note there is no `laptop-scale` and no `machine.serverMode` — every home module that reads them uses an `or` default (`home/desktop/hyprland/xresources.nix:8`, `home/terminal/default.nix:87`), and `mbp-m4-pro` already omits them.

- [ ] **Step 3: Add the Home Manager configuration**

In `flake-modules/home-manager.nix`, after the `"noams@thinkpad-p14s-g6"` line:

```nix
    "noams@halo" = mkHomeConfig hostConfigs.halo;
```

- [ ] **Step 4: Verify the shared entry evaluates**

```bash
nix eval .#homeConfigurations.\"noams@halo\".activationPackage.drvPath
```

Expected: PASS — prints a `/nix/store/...drv` path.

- [ ] **Step 5: Commit**

```bash
git add lib/host-configs.nix flake-modules/home-manager.nix
git commit -m "feat(halo): register host in shared config"
```

Remember: this will fail the first time if alejandra reformats. `git add` and re-run the identical command.

---

## Task 2: Declarative disk layout

**Files:**
- Create: `hosts/halo/disko.nix`

Modelled on `hosts/thinkpad-p14s-g6/disko.nix` with the three deltas from the spec: a 2 GB ESP, uncompressed `@models` and `@games`, and a `passwordFile` so `nixos-anywhere` can install non-interactively.

- [ ] **Step 1: Create `hosts/halo/disko.nix`**

```nix
# Declarative disk layout for the Minisforum MS-S1 MAX (Strix Halo)
# LUKS full-disk encryption + Btrfs
#
# Usage with nixos-anywhere (see docs/superpowers/plans/2026-08-30-halo-host-stage1.md):
#   nixos-anywhere --flake .#halo --disk-encryption-keys /tmp/disk.key ./disk.key \
#     --extra-files ./extra-files root@<ip>
#
# After first boot, enroll TPM for auto-unlock — see the secure-boot-tpm skill.
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1"; # Confirm with `lsblk` on the target before installing
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            # 2G, not g6's 512M: lanzaboote signs every generation into the
            # ESP, g6 currently sits at 97% of 512M (~45 MB/generation at
            # configurationLimit 12), and halo's initrd is larger still because
            # hardware.amdgpu.initrd.enable puts gfx1151 firmware in it.
            # ESP size cannot be changed later without a reinstall.
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["fmask=0022" "dmask=0022"];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              # Consumed by `nixos-anywhere --disk-encryption-keys`; the file
              # only exists in the installer's tmpfs, never on the target.
              passwordFile = "/tmp/disk.key";
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@log" = {
                    mountpoint = "/var/log";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  # GGUF quants are already compressed; zstd costs decompression
                  # on every read and saves nothing. Separate subvolumes also keep
                  # these out of any snapshot policy.
                  "@models" = {
                    mountpoint = "/var/lib/models";
                    mountOptions = ["noatime"];
                  };
                  "@games" = {
                    mountpoint = "/var/lib/games";
                    mountOptions = ["noatime"];
                  };
                  "@swap" = {
                    mountpoint = "/swap";
                    mountOptions = ["noatime"];
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
```

- [ ] **Step 2: Commit**

```bash
git add hosts/halo/disko.nix
git commit -m "feat(halo): add disko disk layout"
```

---

## Task 3: Hardware configuration and host entry point

**Files:**
- Create: `hosts/halo/hardware-configuration.nix`
- Create: `hosts/halo/host_secrets.nix`
- Create: `hosts/halo/default.nix`
- Modify: `flake-modules/nixos-systems.nix:17`

- [ ] **Step 1: Create `hosts/halo/hardware-configuration.nix`**

Minimal by design — disko owns `fileSystems`, and this gets regenerated during install (Task 6).

```nix
# Regenerated during install via `nixos-anywhere --generate-hardware-config`.
# Kept minimal by hand so the flake evaluates before the machine exists.
# Filesystems are owned by disko.nix, not this file.
{modulesPath, ...}: {
  # Sets hardware.enableRedistributableFirmware. Without it there is no
  # linux-firmware, so amdgpu never initialises (no iGPU, no display beyond
  # simpledrm) and WiFi/BT are dead.
  imports = [(modulesPath + "/installer/scan/not-detected.nix")];

  boot = {
    initrd.availableKernelModules = [
      "nvme"
      "xhci_pci"
      "ahci"
      "usbhid"
      "usb_storage"
      "sd_mod"
      "thunderbolt"
    ];
    kernelModules = ["kvm-amd"];
  };

  hardware.cpu.amd.updateMicrocode = true;
  nixpkgs.hostPlatform = "x86_64-linux";
}
```

- [ ] **Step 2: Create `hosts/halo/host_secrets.nix`**

This file is **not optional**. `secrets/default.nix:19-22` picks `age.identityPaths` based on `machine.type`, and for anything other than `"server"` it points at `/home/noams/.ssh/id_ed25519` — a user key that does not exist during early boot. `users.users.noams.hashedPasswordFile` (`nixos/core/users.nix:11`) depends on that secret decrypting, so getting this wrong means no local login.

```nix
{lib, ...}: {
  # secrets/default.nix points non-server hosts at a user key that does not
  # exist at activation time. age.identityPaths is a list option, so setting it
  # here would concatenate rather than replace — mkForce makes the host key the
  # only identity, so a later user key can never break password decryption.
  age.identityPaths = lib.mkForce ["/etc/ssh/ssh_host_ed25519_key"];
}
```

Task 4 Step 3b extends this file with halo's own secrets, after the rekey.

- [ ] **Step 3: Create `hosts/halo/default.nix`**

```nix
{
  pkgs,
  inputs,
  ...
}: let
  hostConfig = (import ../../lib/host-configs.nix).halo;
  inherit (import ../../lib/host-configs.nix) sshPublicKeys;
in {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./host_secrets.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    inputs.disko.nixosModules.disko
    # common-cpu-amd-pstate imports common-cpu-amd itself; don't list both.
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-pc
    inputs.nixos-hardware.nixosModules.common-pc-ssd
    ../../nixos/core/lanzaboote.nix
  ];

  inherit (hostConfig) hostname email profile;
  desktop.mode = hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

  # Strix Halo (gfx1151) support is still landing upstream; track the newest
  # kernel rather than the LTS default.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Unified memory: the GPU draws from the GTT window rather than a fixed BIOS
  # VRAM carve-out. Set the BIOS UMA to its minimum to match.
  # These values are a STARTING POINT, validated in Task 8 — do not treat them
  # as measured. gttsize is in MiB; ttm.pages_limit is in 4 KiB pages.
  boot.kernelParams = [
    "amdgpu.gttsize=98304" # 96 GiB
    "ttm.pages_limit=25165824" # 96 GiB / 4 KiB
  ];

  users.users.noams.openssh.authorizedKeys.keys = [
    sshPublicKeys.noams
  ];

  # Ryzen AI Max+ 395: 16 cores / 32 threads.
  nix.settings = {
    max-jobs = 8;
    cores = 4;
    max-silent-time = 14400;
    timeout = 172800;
  };
}
```

Note: no `nixos-hardware` module exists for the MS-S1 — the `minisforum/` directory only covers the UM series and V3 — so the generic `common-*` modules are used instead.

- [ ] **Step 4: Register the system in `flake-modules/nixos-systems.nix`**

Add after the `thinkpad-p14s-g6` line:

```nix
      halo = mkSystem ../hosts/halo;
```

- [ ] **Step 5: Stage the new files so Nix can see them**

```bash
git add hosts/halo flake-modules/nixos-systems.nix
```

This is required before evaluation — untracked files are invisible to the flake.

- [ ] **Step 6: Verify the configuration evaluates**

```bash
nix eval .#nixosConfigurations.halo.config.networking.hostName
```

Expected: PASS — prints `"halo"`.

- [ ] **Step 7: Verify it builds**

```bash
nix build .#nixosConfigurations.halo.config.system.build.toplevel --no-link
```

Expected: PASS. This is the real test — it type-checks every module against `machine.type = "desktop"` and `desktop.mode = "none"`.

If it fails on an assertion from a module that assumes a laptop, fix it by gating that module on `config.machine.isLaptop` rather than by changing `halo`'s options.

- [ ] **Step 8: Verify the disko script generates**

```bash
nix build .#nixosConfigurations.halo.config.system.build.diskoScript --no-link
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add hosts/halo flake-modules/nixos-systems.nix
git commit -m "feat(halo): add host configuration"
```

---

## Task 4: Pre-seed the agenix host key

**Why this task exists:** `secrets/default.nix` decrypts `noams_password.age`, and `nixos/core/users.nix:11` uses it as `hashedPasswordFile`. agenix decrypts with the host's SSH key, which does not exist until the machine is installed — and the secret cannot be encrypted to a recipient that does not exist yet. Generating the key up front breaks the cycle.

`just bootstrap-host` hands this key to `nixos-anywhere --extra-files`, which places it in `/etc/ssh/` of the new system before activation runs.

**Files:** none in this repo — the private `mysecrets` repo and a local scratch directory.

- [ ] **Step 1: Generate the host key on your laptop**

```bash
mkdir -p /tmp/halo-bootstrap
ssh-keygen -t ed25519 -N "" -C "root@halo" -f /tmp/halo-bootstrap/ssh_host_ed25519_key
```

- [ ] **Step 2: Print the public key**

```bash
cat /tmp/halo-bootstrap/ssh_host_ed25519_key.pub
```

- [ ] **Step 3: Add it as a recipient in the `mysecrets` repo**

Add the public key from Step 2 to that repo's `secrets.nix` recipient list, following the pattern already there for the ThinkPads. `halo` needs three secrets, not just one:

| Secret | Why | Modelled on |
|---|---|---|
| `noams_password` | `users.users.noams.hashedPasswordFile` — without it there is no local login | all hosts |
| a nix access tokens secret | ~40 GitHub flake inputs against an unauthenticated 60 req/hr limit. This is the failure that commit `794f996` fixed on the Mac | `hosts/thinkpad-p14s-g6/host_secrets.nix:12-16` |
| `noams_flakehub` | `home/noams.nix:61` symlinks `~/.config/flakehub/auth` to it on every Linux host. Without it the symlink dangles and `cache.flakehub.com` goes unauthenticated — so the box that most needs the binary cache builds from source | `hosts/thinkpad-p14s-g5/host_secrets.nix:23` |

- [ ] **Step 4: Rekey**

In the `mysecrets` repo:

```bash
agenix -r
```

Commit and push there.

- [ ] **Step 5: Add the two extra secrets to `hosts/halo/host_secrets.nix`**

Only now — referencing a secret file that does not exist yet breaks evaluation. Keep the existing `age.identityPaths` line:

```nix
{
  lib,
  inputs,
  config,
  ...
}: {
  # secrets/default.nix points non-server hosts at a user key that does not
  # exist at activation time. identityPaths is a list, so a plain assignment
  # would append to that key rather than replace it.
  age.identityPaths = lib.mkForce ["/etc/ssh/ssh_host_ed25519_key"];

  age.secrets = {
    nixAccessTokens = {
      file = "${inputs.mysecrets}/halo-nix-access-tokens.age";
      mode = "0440";
      group = "wheel";
    };
    noams_flakehub = {
      file = "${inputs.mysecrets}/noams_flakehub.age";
      owner = config.username;
      mode = "0400";
    };
  };
}
```

Use the filenames you actually created.

- [ ] **Step 6: Update the lock, verify, push**

```bash
nix flake update mysecrets
git add flake.lock hosts/halo/host_secrets.nix
nix build .#nixosConfigurations.halo.config.system.build.toplevel --no-link
git commit -m "feat(halo): wire up host secrets"
git push
```

The push matters: the install pulls this branch from GitHub.

- [ ] **Step 7: Leave the key where it is**

No USB stick is needed. `just bootstrap-host` passes
`/tmp/halo-bootstrap/ssh_host_ed25519_key` to `nixos-anywhere --extra-files`,
which copies it over SSH into `/etc/ssh/` of the new system before activation —
so it is in place when agenix first needs it.

**Treat `/tmp/halo-bootstrap` as sensitive** until the install is done: that
private key is what decrypts your secrets. Task 6 Step 12 destroys it.

---

## Task 5: Prepare the LUKS passphrase

- [ ] **Step 1: Choose it and store it FIRST**

Generate a strong passphrase and save it in your password manager **before** using it anywhere. This is the recovery passphrase the spec requires alongside the TPM token — if TPM unlock breaks after a BIOS update, this is the only way in.

- [ ] **Step 2: Know how you will type it**

`hosts/halo/disko.nix` sets `passwordFile = "/tmp/disk.key"`. You compose that
file **on your laptop** (Task 6 Step 4) and `nixos-anywhere
--disk-encryption-keys` copies it into the installer before disko runs.

This is why the nixos-anywhere path is worth the rework: composing the
passphrase on your own keyboard removes the live ISO's US layout from the
equation entirely. Under the old manual procedure you typed it into a US-layout
console, and any character that moves between layouts gave you a disk encrypted
with something other than what you meant — discovered later, at a recovery
prompt, with no way in.

You will still type it by hand at every boot until TPM auto-unlock lands
(Task 7), and at every recovery afterwards. Choose accordingly.

---

## Task 6: Install with nixos-anywhere

**Files:**
- Modify: `hosts/halo/hardware-configuration.nix` (written by nixos-anywhere during the install)

This uses `just bootstrap-host`, which wraps `nixos-anywhere` with the three
flags that cover what used to be manual:

| What it does | Flag |
|---|---|
| Places the pre-seeded `/etc/ssh/ssh_host_ed25519_key` before activation | `--extra-files` |
| Puts the LUKS passphrase at `/tmp/disk.key` before disko runs | `--disk-encryption-keys` |
| Writes the real hardware config back into the repo | `--generate-hardware-config` |

**Why this beats doing it by hand:** the passphrase is composed on your laptop,
on a keyboard whose layout you trust, instead of being typed at a US-layout live
ISO. That single change removes the most dangerous failure in the old procedure —
a disk encrypted with a passphrase containing characters you did not intend, discovered
at a recovery prompt.

The only steps still needing the TV and a keyboard are reading the installer's
address (Step 2) and typing the passphrase at the first boot (Step 7).

- [ ] **Step 1: Disable Secure Boot, then boot the installer ISO on halo**

**Secure Boot must be OFF for this step.** NixOS ISOs carry no Microsoft-signed
shim, and Ventoy needs either Secure Boot disabled or its key enrolled through
MokManager. With it on, the stick simply will not boot.

Note there are three distinct firmware states across this install, and
"disabled" is not the same as "setup mode":

| Stage | Secure Boot state | Why |
|---|---|---|
| This step — install | **Disabled** | The ISO is unsigned |
| Task 7 Step 2 | **Setup mode** (factory keys cleared) | lanzaboote's `autoEnrollKeys` can only enroll into an empty key store |
| Task 7 Step 3 onward | **Enabled** | Normal operation |

TPM enrollment comes *after* Secure Boot is enabled, never before: PCR 7
measures Secure Boot state, so a slot enrolled while it is off is invalidated
the moment you turn it on.

Then use the ISO from `just iso` (on the Ventoy stick). It auto-joins home wifi
and runs sshd with your key already authorized, so no `nmcli` is needed.

- [ ] **Step 2: Get the installer's address**

The console prints it once the network is up. If it does not (see the caveat in
that ISO's PR), on halo's console run:

```bash
ip -4 a
```

- [ ] **Step 3: Confirm the disk device — from your laptop**

```bash
ssh root@<ip> lsblk -o NAME,SIZE,MODEL,SERIAL
```

Expected: the internal NVMe is `nvme0n1`. **If it is anything else, stop** —
update `device` in `hosts/halo/disko.nix` and commit, because the next steps will
happily destroy the wrong disk. Confirm the size and model match the box's
internal drive and not the USB stick.

- [ ] **Step 4: Write the LUKS passphrase to a local file**

On your laptop, not on the installer:

```bash
printf '%s' 'YOUR-PASSPHRASE-HERE' > /tmp/halo-bootstrap/luks.key
chmod 600 /tmp/halo-bootstrap/luks.key
```

Use `printf`, not `echo` — a trailing newline becomes part of the passphrase.
Verify exactly what landed:

```bash
cat -A /tmp/halo-bootstrap/luks.key
```

Expected: your passphrase with **no** trailing `$`.

This must already be in your password manager (Task 5). It is the only way in if
TPM unlock breaks after a BIOS update.

- [ ] **Step 5: Install**

From the repo checkout on your laptop:

```bash
just bootstrap-host halo <ip> /tmp/halo-bootstrap/ssh_host_ed25519_key /tmp/halo-bootstrap/luks.key
```

This destroys everything on the target disk, creates the GPT/ESP/LUKS/btrfs
layout, installs, places the host key, and reboots.

The recipe refuses to start if the host has no `disko.nix`, or if either file
argument is missing — so a typo fails in a second rather than midway through
partitioning.

- [ ] **Step 6: Note what the hardware config did *not* affect**

`--generate-hardware-config` writes `hosts/halo/hardware-configuration.nix`
during the run, but the system being installed was already evaluated from the
committed file. So the generated file applies from the **next** rebuild, not this
install. That is fine — the committed file already imports `not-detected.nix`,
which is what amdgpu and the radios need.

Check what changed:

```bash
git diff hosts/halo/hardware-configuration.nix
```

- [ ] **Step 7: First boot**

At the LUKS prompt on the TV, enter the Task 5 passphrase — TPM auto-unlock does
not exist yet (Task 7). This is the last step needing the keyboard.

- [ ] **Step 8: Verify over SSH**

```bash
ssh noams@<ip> 'hostnamectl; sudo ls -l /run/agenix/; lsblk -f'
```

Expected: hostname `halo`, `noams_password` present in `/run/agenix/`, and the
btrfs subvolumes `@`, `@home`, `@nix`, `@log`, `@models`, `@games`, `@swap`
mounted with `/boot` vfat and root on `/dev/mapper/cryptroot`.

**If `/run/agenix/` is empty**, the host key is wrong or the rekey did not
include it. That is a Task 4 problem, not a reinstall — check that
`noams_password.age` has halo among its recipients:

```bash
grep -a -c '^-> ssh-ed25519' /path/to/nix-secrets/noams_password.age
```

- [ ] **Step 9: Join Tailscale**

```bash
ssh noams@<ip> 'sudo tailscale up'
```

Follow the URL. After this the address stops mattering.

- [ ] **Step 10: Commit the generated hardware configuration**

```bash
git add hosts/halo/hardware-configuration.nix
nix build .#nixosConfigurations.halo.config.system.build.toplevel --no-link
git commit -m "feat(halo): add generated hardware configuration"
git push
```

Do not hand-edit the config on the machine itself — it would be overwritten on
the first rebuild and the repo would silently disagree with the running system.

- [ ] **Step 11: Verify a rebuild works end to end**

Deploy from your laptop, not on halo:

```bash
nixos-rebuild switch --flake .#halo \
  --target-host noams@<ip> --elevate sudo --ask-elevate-password
```

Expected: succeeds with nothing to activate. This proves the committed config
matches the running machine.

Two reasons this does not run on halo itself:

- **halo cannot fetch `mysecrets`.** That input is `git+ssh://` against a
  private repo, and halo has no SSH key authorised for it. Building on the
  laptop keeps the secret fetch where the credentials are.
- **A `github:` ref cannot express this branch.** `feat/175-halo-host` contains
  a slash, which `github:owner/repo/ref` URL-encodes to `feat%2F...` and the
  GitHub API returns 404. A full commit SHA works if you ever need that form;
  a branch name with a slash does not.

- [ ] **Step 12: Destroy the bootstrap key material**

```bash
gtrash put /tmp/halo-bootstrap
```

The private host key decrypts your secrets and the LUKS file is your recovery
passphrase. `/tmp` clears on reboot anyway, but do not leave them lying around in
the meantime.

---


## Task 7: Secure Boot and TPM2 auto-unlock

**Files:** none — on-host configuration.

Follow the `secure-boot-tpm` skill, which covers this flow for g5 and g6. Summarised here so the ordering is explicit:

- [ ] **Step 1: Confirm lanzaboote generated keys**

On `halo`:

```bash
sudo sbctl status
```

Expected: keys exist under `/etc/secureboot`. `nixos/core/lanzaboote.nix:17-18` sets `autoGenerateKeys` and `autoEnrollKeys`.

- [ ] **Step 2: Put the firmware into Secure Boot setup mode**

Reboot into the MS-S1 BIOS, clear the existing Secure Boot keys (enter setup mode), save, and boot back into NixOS.

- [ ] **Step 3: Verify Secure Boot is active**

```bash
bootctl status | grep -i secure
```

Expected: `Secure Boot: enabled`.

- [ ] **Step 4: Enroll the TPM**

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/disk/by-partlabel/disk-main-root
```

You will be prompted for the passphrase from Task 5.

`--tpm2-pcrs=7` binds Secure Boot state only, deliberately diverging from the
`secure-boot-tpm` skill's `0+7`. PCR 0 measures firmware, so binding it means
every BIOS update breaks auto-unlock — plausible on a Minisforum box. The
tradeoff is accepted: firmware tampering is not caught.

- [ ] **Step 4b: Enroll a recovery key — do not skip this**

```bash
sudo systemd-cryptenroll --recovery-key /dev/disk/by-partlabel/disk-main-root
```

Save the printed key in your password manager, offline.

The `secure-boot-tpm` skill lists "enrolling TPM without a recovery key" as the
mistake that locks you out after a BIOS update, and g6 has already needed a LUKS
passphrase reset once. The Task 5 passphrase is one way back in; this is the
second, independent of it.

Confirm all three slots exist before rebooting:

```bash
sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root
```

Expected: a password slot, a tpm2 slot, and a recovery slot.

- [ ] **Step 5: Verify auto-unlock**

```bash
sudo reboot
```

Expected: the machine boots to a login prompt with no passphrase entry.

- [ ] **Step 6: Verify the recovery passphrase still works**

This matters more than it looks — it is the fallback when a BIOS update invalidates PCR 7:

```bash
sudo cryptsetup open --test-passphrase /dev/disk/by-partlabel/disk-main-root
```

Expected: accepts the Task 5 passphrase and exits 0.

---

## Task 8: Measure the GTT / unified-memory split

`hosts/halo/default.nix` sets `ttm.pages_limit` via `boot.extraModprobeConfig`. `nix-amd-ai` (a flake input this repo already uses) has measured values for exactly this hardware, so this task is a confirmation run against a known-good reference rather than an open-ended exploration.

**Files:**
- Modify: `hosts/halo/default.nix` (`boot.extraModprobeConfig`, if the measurement disagrees)

- [ ] **Step 1: Set the BIOS UMA to minimum**

Reboot into BIOS, set the UMA frame buffer / dedicated VRAM to its smallest value (typically 512 MB), save and boot.

- [ ] **Step 2: Check the exact expected GTT total**

`nix-amd-ai`'s README ("GPU memory headroom") reports this measured on a 128 GB
Halo (ROG Flow Z13, Ryzen AI MAX+ 395, kernel 7.1.0) running the same
`ttm.pages_limit=25165824` this host sets:

```bash
cat /sys/class/drm/card*/device/mem_info_gtt_total
```

Expected: `103079215104` — exactly 96 GiB (`25165824 x 4096`). The arithmetic is
exact, so anything else means the modprobe option did not apply.

- [ ] **Step 3: Confirm the option reached the module**

```bash
cat /sys/module/ttm/parameters/pages_limit
cat /sys/module/ttm/parameters/page_pool_size
cat /proc/cmdline
```

Expected: both parameters read `25165824`, and `/proc/cmdline` contains NO
`amdgpu.gttsize` (ROCm#5595 warns against setting it alongside `pages_limit`).

- [ ] **Step 4: Confirm ROCm identifies the GPU correctly**

```bash
nix shell nixpkgs#rocmPackages.rocminfo -c rocminfo | grep -iE "gfx|Marketing"
cat /sys/class/drm/card*/device/mem_info_vram_total
```

Expected: `gfx1151`. If it reports **`gfx1100`**, the kernel is misidentifying
the GPU — `nix-amd-ai` issue #61 saw this on 6.19.x. Their measurement was taken
on 7.1.0 and this host runs `linuxPackages_latest`, so it should be fine; if it
is not, pin the kernel before trusting any benchmark.

- [ ] **Step 5: Settle `page_pool_size`**

This is an open question in `nix-amd-ai` (#42): whether `page_pool_size` does
anything beyond `pages_limit`. Drop it from `boot.extraModprobeConfig`, rebuild,
reboot, and re-read `mem_info_gtt_total`. If unchanged, it is decorative —
record that finding, since it answers an open question in that repo.

- [ ] **Step 6: Adjust if the numbers disagree**

If `mem_info_gtt_total` is not exactly `103079215104`, change the value in
`hosts/halo/default.nix`, `sudo nixos-rebuild switch --flake .#halo`, reboot,
and repeat Steps 2-4.

Do **not** set `amd_iommu=off` while debugging — it kills the NPU, and
`nix-amd-ai` reports an 80 GiB model loading fine without it.

- [ ] **Step 7: Commit the validated values**

```bash
git add hosts/halo/default.nix
git commit -m "fix(halo): set GTT sizing to measured values"
```

Update the comment above `boot.kernelParams` to say the values are measured, and record the `dmesg` figures in the commit body.

---

## Task 9: Characterise HDMI connector behaviour

Stage 2's always-on Steam session depends on the display connector existing while the TV is off. This task establishes whether it does, before anything is built on the assumption.

**Files:**
- Modify: `hosts/halo/default.nix` (only if a `video=` parameter proves necessary)

- [ ] **Step 1: Identify the connector with the TV on**

With the TV powered on and showing the box's input:

```bash
for c in /sys/class/drm/card*-HDMI*; do echo "$c: $(cat $c/status)"; done
```

Record the connector name (e.g. `card1-HDMI-A-1`) and its status.

- [ ] **Step 2: Record status with the TV on another input**

Switch the TV to a different input, wait ten seconds, then re-run the command from Step 1 over SSH.

Record whether status changed from `connected` to `disconnected`.

- [ ] **Step 3: Record status with the TV powered off**

Power the TV off, wait ten seconds, re-run the Step 1 command over SSH.

Record the status.

- [ ] **Step 4: Interpret**

- If status stays `connected` in Steps 2 and 3, no `video=` parameter is needed and Stage 2 can rely on the connector always being present. Note this and skip to Step 6.
- If status becomes `disconnected`, the connector-forcing parameter is required. Continue to Step 5.

- [ ] **Step 5: Force the connector and re-test**

Add to `boot.kernelParams` in `hosts/halo/default.nix`, substituting the connector name from Step 1 and the TV's native resolution:

```nix
    "video=HDMI-A-1:1920x1080@60e"
```

Then:

```bash
sudo nixos-rebuild switch --flake .#halo
sudo reboot
```

Re-run Steps 2 and 3. Record whether the connector now stays enabled with the TV off.

If it still drops, the TV is not presenting a readable EDID while off, and a stored EDID via `drm.edid_firmware` will be needed — record that finding for Stage 2 rather than solving it here.

- [ ] **Step 6: Commit any change**

```bash
git add hosts/halo/default.nix
git commit -m "fix(halo): force HDMI connector enable"
```

Skip this step if Step 4 determined no change was needed.

---

## Task 10: Record findings and open the PR

**Files:**
- Modify: `docs/superpowers/specs/2026-08-29-halo-host-design.md`

- [ ] **Step 1: Replace the spec's open items with measurements**

In the "Open items for install time" section, replace items 1, 2, and 4 with what Tasks 6, 8, and 9 actually found: the real NVMe device path, the measured GTT figures and whether `amdgpu.gttsize` was honoured, and the TV's HPD behaviour with the connector-forcing outcome.

Leave item 3 (the Vulkan vs. ROCm benchmark) — it belongs to Stage 2.

- [ ] **Step 2: Correct the two spec errors this plan already fixed**

- In "Host options and repo integration", change `machine.type = "server"` to `"desktop"` and add the reason: `nixos/core/pc.nix:9` gates pipewire and bluetooth behind `isPC`.
- In "Other services", note that SSH and Tailscale are inherited from `nixos/core/networking.nix` and `nixos/services/tailscale.nix`, requiring no host-level configuration.

- [ ] **Step 3: Note the Stage 2 finding about `hardware.amd-npu`**

Add to the spec's "LLM stack" section: `hosts/thinkpad-p14s-g6/default.nix:36-44` already uses a `hardware.amd-npu` module from the `nix-amd-ai` input, with `enableROCm` and `enableVulkan` options. Stage 2 should evaluate whether it covers gfx1151 (Halo) as well as it covers the g6's gfx1150, rather than building a separate llama.cpp unit by default. Note also that this input builds from source and is slow — the reason g6 rebuilds take so long.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-08-29-halo-host-design.md
git commit -m "docs(halo): record stage 1 hardware findings"
```

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin feat/175-halo-host
gh pr create --assignee @me \
  --title "feat(halo): add AMD Strix Halo host (stage 1: bootable base)" \
  --body "Closes #175 partially — stage 1 only.

Adds the \`halo\` host: disko LUKS+btrfs layout, lanzaboote Secure Boot with TPM2 auto-unlock, and registration in host-configs, nixos-systems, and home-manager.

Steam, llama.cpp, Sunshine, and podman services are stage 2, deliberately deferred until the GTT and HDMI behaviour were measured on real hardware. Findings are recorded in the spec.

https://claude.ai/code/session_01LgpTdN4wSFEPauPZmaPknc"
```

---

## Notes carried forward to Stage 2

- `/var/lib/models` and `/var/lib/games` are created by disko as `root:root 0755`. Nothing in Stage 1 writes to them, so this does not affect the install. Stage 2 should give them ownership via `systemd.tmpfiles.rules`, not a manual `chown`.
- `programs.steam` now sits behind `desktop.isEnabled` in `nixos/desktop/default.nix`, and `halo` is `desktop.mode = "none"`. Stage 2 must enable Steam in `hosts/halo/default.nix` directly rather than inheriting it — which is arguably more honest anyway, since halo's Steam is gamescope-on-DRM, not the desktop-session Steam that block was written for.
- `system.stateVersion` is `"23.05"` repo-wide (`nixos/core/default.nix`), inherited by this brand-new 2026 install. Irrelevant to Stage 1; worth remembering when Stage 2 adds stateful services.
- `machine.type = "desktop"` also brings in `printing`, `airconnect`, `coolercontrol`, solaar, geoclue2, and avahi from `nixos/core/pc.nix`, alongside the pipewire and bluetooth that motivated the choice. Fine for now; that module is the seam if halo ever needs a narrower `isPC`.

## Definition of done

- `nix build .#nixosConfigurations.halo.config.system.build.toplevel` succeeds.
- `halo` boots unattended to a login prompt — no passphrase entry — with Secure Boot enabled.
- `ssh noams@halo` works over Tailscale from a ThinkPad.
- `sudo ls /run/agenix/` shows `noams_password`, and local login works.
- The measured GTT size is recorded in the spec and reflected in `hosts/halo/default.nix`.
- The TV's HPD behaviour is recorded in the spec, with the connector-forcing parameter applied if the measurement called for it.
