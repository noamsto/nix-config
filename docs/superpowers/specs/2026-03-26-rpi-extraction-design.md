# RPi Configuration Extraction to Standalone Repository

**Date:** 2026-03-26
**Status:** Approved

## Motivation

1. **CI builds on native ARM** — Build RPi aarch64 configurations on GitHub Actions ARM runners instead of cross-compiling on the development laptop.
2. **FlakeHub caching** — Push built closures to FlakeHub cache so deployments to Pis become downloads, not builds.
3. **Separation of concerns** — RPi server configs are naturally isolated from desktop/laptop configs. Extracting them reduces nix-config complexity.
4. **Sharing/reuse** — The RPi repo can be consumed independently without pulling the entire dotfiles repo.

## Decision: Full Monolithic Extraction

All RPi-related configuration, scripts, and metadata move to a new standalone flake repository. No cross-repo flake dependencies. No Home Manager dependency.

### Why not a module library?

A module library can't produce buildable `nixosConfigurations`, so GitHub Actions couldn't build the full system closures. The CI/caching goal requires the new repo to own complete configurations.

### Why not keep nix-config as a flake input?

Creates a fragile cross-repo dependency. The shared surface between RPi configs and nix-config is small (SSH keys, username/email). Duplicating those is cheaper than managing the coupling.

### Why drop Home Manager?

RPi hosts are headless servers. The existing HM config (`hosts/naspi/home.nix`) only provides git, fish, minimal neovim, and basic packages — all achievable via NixOS system-level `programs.*` modules and wrapped packages. Dropping HM removes a flake input and simplifies the repo.

## New Repository

**Name:** `nix-rpi`
**Visibility:** Private (GitHub)
**Owner:** noams

## Flake Architecture

### Inputs

| Input | Purpose |
|---|---|
| `nixpkgs` | Pinned to match nix-config for consistency |
| `nixos-raspberrypi` | RPi hardware support (pinned commit) |
| `determinate` | Determinate Nix module (FlakeHub cache integration, nix settings) |
| `disko` | Declarative disk partitioning |
| `agenix` | Secret management |
| `mysecrets` | Private secrets repo (SSH-accessed) |
| `go-bills` | Financial tracking app (naspi) |
| `flake-parts` | Modular flake structure |
| `treefmt-nix` | Code formatting |

### Outputs

| Output | Description |
|---|---|
| `nixosConfigurations.naspi` | Full NAS configuration (ZFS RAID1) |
| `nixosConfigurations.argon-rpi4` | Argon V2 case RPi configuration (Btrfs) |
| `nixosConfigurations.rpi4-installer` | Minimal SD card installer image |
| `apps.<system>.deploy-naspi` | Deploy config to naspi |
| `apps.<system>.deploy-argon` | Deploy config to argon-rpi4 |
| `apps.<system>.install-naspi` | Fresh install to naspi (destructive) |
| `apps.<system>.install-argon` | Fresh install to argon-rpi4 (destructive) |
| `apps.<system>.build-installer` | Build SD card image |
| `packages.<system>.rpi4-installer` | Installer SD image derivation |
| `rpiHosts` | Deployment metadata (for scripts) |
| `devShells` | Dev shell with deployment tools |

## Directory Layout

```
nix-rpi/
├── flake.nix
├── flake-modules/
│   ├── nixos-systems.nix          # All nixosConfigurations
│   ├── apps.nix                   # Flake apps wrapping deployment scripts
│   └── development.nix            # devShell, treefmt, pre-commit hooks
├── lib/
│   ├── rpi-hosts.nix              # Deployment metadata (source of truth)
│   ├── rpi-common.sh              # Shared bash utilities for scripts
│   └── options.nix                # Simplified server-focused options
├── hosts/
│   ├── naspi/
│   │   ├── default.nix            # Main entry point
│   │   ├── hardware.nix           # RPi4 hardware config
│   │   ├── system.nix             # System-level config (ZFS, boot, kernel)
│   │   ├── disko.nix              # ZFS RAID1 disk layout
│   │   ├── media-services.nix     # Sonarr, Radarr, Transmission, etc.
│   │   ├── reverse-proxy.nix      # Reverse proxy
│   │   ├── monitoring.nix         # System monitoring
│   │   ├── tailscale.nix          # VPN networking
│   │   ├── network-resilience.nix # Network reliability
│   │   ├── go-bills.nix           # Financial tracking
│   │   ├── paperless.nix          # Document management (disabled)
│   │   ├── xscript.nix            # X-C1 expansion board
│   │   ├── arr-setup.sh           # Arr stack init script
│   │   ├── recyclarr.yml          # Arr config template
│   │   ├── pwm-2chan.dts          # Device tree source
│   │   └── README.md              # NasPi documentation
│   ├── argon-rpi4/
│   │   ├── default.nix            # Main entry point
│   │   ├── hardware.nix           # RPi4 + Argon case hardware
│   │   ├── system.nix             # System-level config
│   │   ├── disko.nix              # Btrfs disk layout
│   │   ├── btrfs-config.nix       # Btrfs optimizations
│   │   └── README-*.md            # Documentation
│   └── rpi4-installer/
│       └── default.nix            # Minimal installer config
├── modules/
│   ├── common.nix                 # Base server config (locale, networking, users, SSH, nix settings)
│   ├── packages.nix               # System packages + wrapped tools (neovim, git, fish)
│   └── secrets.nix                # Agenix secret declarations
├── overlays/                      # Package overlays (if any RPi-specific overlays exist)
├── packages/                      # Wrapped neovim with minimal config (pkgs.wrapNeovim with custom init.lua)
├── scripts/
│   ├── rpi                        # Main CLI entry point
│   ├── operations/
│   │   ├── deploy.sh              # Deploy configuration updates
│   │   ├── install.sh             # Fresh installation (nixos-anywhere + disko)
│   │   └── build-image.sh         # Build SD card images
│   └── generate-zfs-key.sh        # ZFS encryption key generation
├── justfile                       # RPi convenience recipes
└── .github/
    └── workflows/
        └── build.yml              # ARM builds + FlakeHub cache
```

## Simplified Options System

Server-only — no desktop/laptop machinery:

```nix
# lib/options.nix
{
  username = mkOption { type = str; };
  user-full-name = mkOption { type = str; };
  email = mkOption { type = str; };
  hostname = mkOption { type = str; };
  profile = mkOption { type = enum ["personal" "work"]; default = "personal"; };
  flakePath = mkOption { type = str; readOnly = true; default = "/home/${config.username}/nix-rpi"; };
}
```

No `desktop.mode`, `machine.type`, or derived booleans — every host is a headless server. These options are only needed for the few modules that reference them (git config uses `user-full-name` and `email`).

Host configs set these directly in their `default.nix` — no shared `host-configs.nix` indirection needed for 2-3 hosts.

### SSH Public Keys

Hardcoded in `modules/common.nix` as a let-binding:

```nix
let
  sshPublicKeys = {
    noams = "ssh-ed25519 AAAA...";  # copied from nix-config's lib/host-configs.nix
  };
in { ... }
```

## Common Server Module

`modules/common.nix` consolidates base server configuration:

- Locale, timezone (Asia/Jerusalem), networking
- SSH server with hardened defaults
- User account (noams) with SSH public keys (hardcoded in this module)
- Nix settings via `determinate.nixosModules.default` (flakes, FlakeHub cache integration)
- Binary caches: nixos-raspberrypi.cachix.org, nix-community, etc.
- Fish shell enabled system-wide
- `programs.git` with basic config at system level (uses `user-full-name` and `email` options)

## Wrapped Tools (No Home Manager)

Instead of Home Manager for tool configuration:

- **Neovim**: Wrapped with minimal config baked into the derivation (replaces `home/nvim/minimal.nix`)
- **Git**: Configured via `programs.git` NixOS module
- **Fish**: Configured via `programs.fish` NixOS module with basic aliases
- **Packages**: Installed via `environment.systemPackages`

## CI/CD: GitHub Actions + FlakeHub

### Workflow: `.github/workflows/build.yml`

**Runner:** `ubuntu-24.04-arm` (native aarch64, GitHub-hosted)

**Trigger:** Push to `main`, PR to `main`

**Matrix:** `[naspi, argon-rpi4, rpi4-installer]`

**Steps per host:**
1. Checkout repo
2. Install Nix (Determinate installer — supports FlakeHub auth)
3. Configure FlakeHub cache (push on `main`, pull-only on PRs)
4. Configure nixos-raspberrypi.cachix.org (pull only)
5. `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`
6. For rpi4-installer: also build SD image

**Cache layering (pull order):**
1. FlakeHub cache — own built closures
2. nixos-raspberrypi.cachix.org — pre-built RPi kernel/firmware
3. nix-community.cachix.org — community packages
4. cache.nixos.org — official NixOS

**Secrets in GitHub Actions:**
- FlakeHub token for cache push
- SSH deploy key for `mysecrets` private repo access

### Deployment Flow (After CI)

1. Edit config in `nix-rpi/`
2. `git push` → CI builds on native ARM, caches to FlakeHub
3. `just deploy-naspi` (or `nix run .#deploy-naspi`)
4. `nixos-rebuild switch` on Pi pulls pre-built closure from FlakeHub — mostly downloads, minimal local compilation

## Cleanup of nix-config

### Files Removed

| Path | Description |
|---|---|
| `hosts/naspi/` | Entire directory (11+ files) |
| `hosts/argon-rpi4/` | Entire directory (7+ files) |
| `hosts/rpi4-installer/` | Entire directory |
| `scripts/rpi/` | CLI + operations |
| `scripts/generate-zfs-key.sh` | ZFS key generation |
| `lib/rpi-hosts.nix` | RPi deployment metadata |
| `lib/rpi-common.sh` | Script library |

### Files Modified

| File | Changes |
|---|---|
| `flake.nix` | Remove `nixos-raspberrypi`, `disko`, `go-bills` inputs (if unused); remove `rpiHosts` output |
| `flake-modules/nixos-systems.nix` | Remove naspi, argon-rpi4, rpi4-installer configurations |
| `flake-modules/home-manager.nix` | Remove `mkArmHomeConfig`, `noams@naspi`, `naspi-raspbian` |
| `lib/host-configs.nix` | Remove naspi and argon-rpi4 entries |
| `secrets/default.nix` | Remove RPi-specific secrets, remove server identity path |
| `justfile` | Remove all RPi recipes (~14) |
| `lib/caches.nix` | Remove `nixos-raspberrypi.cachix.org` if unused |
| `CLAUDE.md` | Remove RPi documentation sections |

### Unchanged

- `options.nix` — desktop/laptop options still used by ThinkPads
- `home/` — no modules referenced RPi-specific code
- `nixos/` — no RPi-specific modules lived here

## Secrets Management

### Secrets in `modules/secrets.nix`

The new repo declares these agenix secrets:

| Secret | Used by | Host |
|---|---|---|
| `noams_password` | User account password hash | All hosts |
| `paperless-naspi-password` | Paperless admin password | naspi |
| `go-bills-gemini-key` | LLM API key for go-bills | naspi |

**Identity path:** `/etc/ssh/ssh_host_ed25519_key` (all hosts are servers).

**Note:** `noams_password` is also used in nix-config for ThinkPad hosts. Both repos will declare it independently — agenix just needs the encrypted file from `mysecrets` and the host's SSH key for decryption. No conflict.

### `mysecrets` repo

The `mysecrets` repo's `secrets.nix` (agenix rules) already lists RPi host public keys for decryption. No changes needed — the same encrypted files work regardless of which repo references them.

### argon-rpi4 and secrets

argon-rpi4 currently does not import agenix secrets. The `modules/secrets.nix` import should be conditional — only naspi imports it, or it uses `mkIf` to only declare secrets when needed.

## Overlays

Check which overlays from `nix-config/overlays/` are used by RPi hosts during implementation. If none are RPi-specific, the `overlays/` directory can be omitted from the new repo. If any are needed, copy them over.

## NixOS Configuration Builders

**Important:** The current configs use custom builders from `nixos-raspberrypi`:
- `nixos-raspberrypi.lib.nixosSystem` for naspi and argon-rpi4
- `nixos-raspberrypi.lib.nixosInstaller` for rpi4-installer

These are NOT the standard `nixpkgs.lib.nixosSystem`. The new `flake-modules/nixos-systems.nix` must use these custom builders with the same `specialArgs` pattern (passing `inputs`, `nixos-raspberrypi`, `self`).

## Media Stack

The existing media services (Sonarr, Radarr, Transmission, Prowlarr, Bazarr, Flood, Recyclarr) move as-is. No migration to nixarr — the current config is well-tuned to the specific setup (ZFS directory structure, Transmission scheduling for Israel timezone, TRaSH profiles for Q800D soundbar, Tailscale-only access model).

## Risk Mitigation

- **Secrets access**: `mysecrets` flake input works identically in the new repo (same SSH key)
- **Build parity**: Pin `nixpkgs` to the same revision as nix-config initially
- **Rollback**: nix-config retains git history; RPi configs can be restored from any commit
- **Testing**: Verify each host builds before removing from nix-config
- **Deployment**: Test `just deploy-naspi` from the new repo before cutting over

## Migration Checklist

Ordered steps to avoid a half-migrated state:

1. **Create `nix-rpi` repo** on GitHub (private)
2. **Set up flake.nix** with all inputs, flake-parts structure
3. **Copy host configs** from nix-config — adjust import paths
4. **Create `modules/common.nix`** — consolidate shared server config (locale, SSH, users, nix settings, fish, git)
5. **Create `modules/packages.nix`** — system packages + wrapped neovim
6. **Create `modules/secrets.nix`** — agenix declarations for RPi secrets
7. **Create `lib/options.nix`** — simplified server options
8. **Copy deployment scripts** — adjust paths for new repo structure
9. **Create `flake-modules/apps.nix`** — expose scripts as flake apps
10. **Create justfile** — RPi-only recipes
11. **Create `flake-modules/development.nix`** — devShell, treefmt
12. **Verify builds** — `nix build .#nixosConfigurations.naspi.config.system.build.toplevel` for each host
13. **Test deployment** — `just deploy-naspi` from new repo to a live Pi
14. **Set up GitHub Actions** — `.github/workflows/build.yml` with ARM runner + FlakeHub
15. **Verify CI** — push to main, confirm ARM build succeeds and caches to FlakeHub
16. **Verify cached deploy** — deploy to Pi, confirm it pulls from FlakeHub cache
17. **Clean up nix-config** — remove all RPi files, inputs, recipes, docs
18. **Verify nix-config** — `nix flake check` passes after cleanup
