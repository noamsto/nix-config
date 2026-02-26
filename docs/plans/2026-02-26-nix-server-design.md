# Design: factify-inc/nix-server

## Overview

Minimal NixOS flake for a Dell XPS 13 9340 running as a headless dev server in an office, reachable via Tailscale SSH. Purpose: remote tmux + claude-code dev workstation.

## Hardware

- **Machine:** Dell XPS 13 9340 (2024)
- **CPU:** Intel Core Ultra (Meteor Lake)
- **Architecture:** x86_64-linux
- **Storage:** Single NVMe SSD
- **nixos-hardware:** No 9340-specific module exists; use `common-cpu-intel` + `common-pc-laptop`

## Repository

- **Location:** `factify-inc/nix-server`
- **Structure:** Minimal single-host flake (no multi-host abstractions)

```
factify-inc/nix-server/
  flake.nix                    # Flake: nixpkgs, disko, lanzaboote inputs
  configuration.nix            # Main NixOS config
  disko.nix                    # Declarative disk layout
  hardware-configuration.nix   # Placeholder (generated on target)
  .gitignore
```

## Flake Inputs

- `nixpkgs` — nixos-unstable
- `disko` — declarative disk partitioning
- `lanzaboote` — Secure Boot with systemd-boot
- `nixos-hardware` — Intel common modules

## Disk Layout (disko)

Single NVMe, LUKS + btrfs:

```
/dev/nvme0n1
├── ESP (512MB, FAT32) → /boot
└── LUKS partition (rest of disk, TPM2 auto-unlock)
    └── btrfs
        ├── @        → /          (compress=zstd)
        ├── @home    → /home      (compress=zstd)
        └── @nix     → /nix       (compress=zstd, noatime)
```

## Boot

- Lanzaboote for Secure Boot (auto key generation + enrollment)
- LUKS + TPM2 auto-unlock: `crypttabExtraOpts = ["tpm2-device=auto"]`
- systemd-boot as bootloader backend

## Networking

- systemd-networkd for wired ethernet (DHCP)
- Tailscale with `--ssh` and `--accept-routes`
- Firewall: open only for Tailscale
- No WiFi needed (wired office connection)

## User

- **Username:** `platypus`
- **Shell:** fish
- **SSH:** authorized keys for initial access
- **Groups:** wheel, networkmanager

## Services

- **OpenSSH** — for initial setup + Tailscale SSH relay
- **Tailscale** — primary remote access method, `useRoutingFeatures = "client"`
- **nix.gc** — automatic garbage collection (weekly)
- **fstrim** — SSD TRIM timer

## Dev Tools (system packages)

- tmux, git, neovim, fish
- claude-code (via node/npm)
- Build essentials (gcc, gnumake)
- Nix dev tools (nil, alejandra)
- Core CLI: ripgrep, fd, jq, htop, curl, wget

## Power Management

- Disable suspend/sleep (`targets.sleep/suspend/hibernate` masked)
- Lid close action: ignore (server may run lid-closed)
- No screen blanking

## Not Included (YAGNI)

- No Home Manager
- No agenix/secrets management
- No multi-host support
- No desktop environment
- No custom options system
- No WiFi configuration

## Install Workflow

1. Boot NixOS USB installer on the XPS
2. Connect to network, clone the repo
3. Run disko to partition + format
4. `nixos-install --flake .#xps-server`
5. Reboot
6. Enroll TPM for LUKS: `sudo systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p2`
7. Authenticate Tailscale: `sudo tailscale up --ssh --accept-routes`
