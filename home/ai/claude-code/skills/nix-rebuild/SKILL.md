---
name: nix-rebuild
description: Use when rebuilding NixOS, nix-darwin (macOS), or Home Manager, running any `nh`, `nixos-rebuild`, `darwin-rebuild`, `home-manager`, `nix flake`, `nix build`, `nix develop`, `nix fmt` command, testing a flake change, debugging a failed build, or hitting "file not found" / "path does not exist" errors on untracked files. Applies to the nix-config repo workflow (flake-parts, hybrid Home Manager, justfile wrappers).
---

# Nix Rebuild Workflow

## Overview

The nix-config repo uses **flake-parts** and spans two platforms. **Pick the rebuild path by platform first:**

**Linux / NixOS hosts** (`thinkpad-p14s-g5`, `thinkpad-p14s-g6`):

- **Full rebuild** (system + user): `nh os switch .` — 2–3 min
- **HM-only rebuild** (user config only): `nh home switch .` — ~30 s

**macOS / nix-darwin host** (`mbp-m4-pro`):

- **Only path**: `nh darwin switch .` — rebuilds the darwin system **and** the integrated Home Manager in one go. `nh home switch` and `nh os switch` do **not** work here (see the macOS section below).

Most commands have three forms: `nh` wrapper → `just` recipe → raw `nix`/`nixos-rebuild`/`darwin-rebuild`. Prefer `nh` for rebuilds; use `just` for common chores; drop to raw `nix` only when the wrappers don't fit.

**Core principle:** Flakes only see **git-tracked** files. Always `git add` before build.

## The git-add gotcha (load-bearing)

**Symptom:** `error: path '/nix/store/...-source/some/file.nix' does not exist` or "file not found" during evaluation.

**Cause:** You created or edited a file but did not `git add` it. `nix` evaluates the flake from the git index, so untracked changes are invisible.

**Fix:**
```fish
git add <files>          # stage new/modified files
just check-staged        # verify what's staged before building
```

This applies to **every** build path: `nh os`, `nh home`, `nix build`, `nix flake check`, etc.

## Quick Reference

| Task | Preferred | Raw equivalent |
|---|---|---|
| Full system rebuild (NixOS) | `nh os switch .` | `sudo nixos-rebuild switch --flake .#<host>` |
| System build only (no activate) | `nh os build .` | `nom build .#nixosConfigurations.<host>.config.system.build.toplevel` |
| Apply at next boot (NixOS) | `nh os boot .` | `sudo nixos-rebuild boot --flake .#<host>` |
| **macOS rebuild (nix-darwin)** | `nh darwin switch .` | `darwin-rebuild switch --flake .#mbp-m4-pro` |
| Home Manager rebuild (NixOS hosts) | `nh home switch .` | `home-manager switch --flake .#<config>` |
| HM build only (NixOS hosts) | `nh home build .` | `nom build .#homeConfigurations.<config>.activationPackage` |
| Validate flake | `just check` | `nix flake check` |
| Format all code | `just fmt` | `nix fmt` |
| Update inputs | `just update` | `nix flake update` |
| Enter devshell | `just dev` | `nix develop` |
| Flake info | `just status` / `just info` | `nix flake metadata` / `nix flake show` |
| Verify staged files | `just check-staged` | `git diff --cached --name-only` |
| GC build artifacts | `just clean` | `rm -rf result*; nix-collect-garbage` |
| Deep GC (generations) | `just clean-all` | `sudo nix-collect-garbage -d` |

`nh` auto-detects the hostname and picks the right config. Override with `.#<host>` when building for another machine.

## Which rebuild path?

**On macOS (`mbp-m4-pro`)** → always `nh darwin switch .`. There is no separate HM-only path (see below).

**On NixOS hosts:**

- **User config only** (shell, editor, dotfiles, wallpapers, user packages) → `nh home switch .`
- **System-level** (services, kernel, drivers, hardware, system packages) → `nh os switch .`
- **Unsure** → `nh os switch .` rebuilds both, always safe.

User explicitly prefers `nh home switch` (CLAUDE.local.md) for HM iterations on Linux — it's ~6× faster and doesn't need sudo.

## macOS (nix-darwin) specifics

The Mac host `mbp-m4-pro` (`darwinConfigurations.mbp-m4-pro`) works differently from the Linux hosts:

- **Home Manager is integrated as a nix-darwin module** (`home-manager.darwinModules.home-manager`, `users.noams = home/noams.nix`) — it is **not** a standalone `homeConfigurations` entry. So `nh home switch` has no config to resolve here and **fails**; `nh os switch` is NixOS-only and also doesn't apply. Always use `nh darwin switch .`, which rebuilds the system + HM together.
- `nh darwin switch` works without the path arg too — `NH_FLAKE` is set to the repo (see `home/ai/.../default.nix`).
- **First switch / bootstrap** (before `darwin-rebuild` is on PATH): `nix run nix-darwin -- switch --flake ~/nix-config#mbp-m4-pro`. Full bootstrap steps live in `hosts/mbp-m4-pro/README.md`.
- **Caches & Nix settings** are managed by **Determinate Nix** via `determinateNix.customSettings` in the host's `default.nix` — *not* `flake.nix:nixConfig`/`lib/caches.nix` (those are the Linux path). Linux-only caches (hyprland, noctalia, vicinae, yazi, etc.) are intentionally omitted on darwin.
- **Cross-platform gating**: shared `home/` modules that pull Linux-only packages must be gated with `lib.optionals pkgs.stdenv.hostPlatform.isLinux [ ... ]` (package lists) or `lib.mkIf pkgs.stdenv.hostPlatform.isLinux { ... }` (config blocks — never condition `imports` on `pkgs`, it causes infinite recursion).

## Available configs

**NixOS hosts:** `thinkpad-p14s-g5` (work), `thinkpad-p14s-g6` (personal)

**nix-darwin host:** `mbp-m4-pro` (personal, macOS) — rebuild with `nh darwin switch .`

**Standalone HM configs (Linux only):** `noams@thinkpad-p14s-g5`, `noams@thinkpad-p14s-g6`, plus legacy aliases (`noams-hyprland`, `noams-hyprland-work`). `nh home` auto-picks the right one. There is **no** standalone HM config for the Mac — its HM is part of the darwin system.

## Debugging failed builds

1. **Re-run with trace** — shows the full evaluation stack:
   ```fish
   nh os switch . -- --show-trace
   nh home switch . -- --show-trace
   nh darwin switch . -- --show-trace   # macOS
   ```
   (The `--` forwards flags to the underlying `nixos-rebuild` / `home-manager` / `darwin-rebuild`.)

2. **Validate flake structure** — catches syntax/eval errors without building:
   ```fish
   nix flake check --show-trace
   ```

3. **Check staged files** — many "missing file" errors are an un-`git add`ed file:
   ```fish
   just check-staged
   ```

4. **Build without switching** — lets you inspect `result/` before activating:
   ```fish
   nh os build .
   nh home build .
   ```

5. **Better build output** — `nom` (nix-output-monitor) is already in the devshell and gives readable tree output:
   ```fish
   nom build .#nixosConfigurations.thinkpad-p14s-g5.config.system.build.toplevel
   ```

## Devshell (`nix develop` / `just dev`)

Provides: `agenix`, `nh`, `home-manager`, `nom`, `nixos-anywhere`, `just`, `prettier`, `statix`, `shellcheck`, `jq`, `tokei`, plus pre-commit hooks (alejandra, ruff, shfmt, shellcheck via treefmt).

Aliases inside the shell: `nbuild` = `nom build`, `dev-stats` = project stats via tokei+git.

## Binary caches

Pre-configured in `flake.nix:nixConfig` and mirrored in `lib/caches.nix` — **keep them in sync when editing either**. Active caches: `cache.nixos.org`, `cache.flakehub.com`, `hyprland.cachix.org`, `vicinae.cachix.org`, `claude-code.cachix.org`, `nixpkgs-unfree.cachix.org`, `nix-community.cachix.org`, `yazi.cachix.org`, `numtide.cachix.org`.

No manual config needed; they apply automatically.

## Testing workflow before commit

```fish
git add <files>                 # 1. stage (flakes only see tracked files)
just check-staged               # 2. confirm what's included
nh os build .                   # 3. build without activating (or `nh home build .`)
nh os switch .                  # 4. activate if build succeeded
```

For flake input bumps:
```fish
nix flake update                # or: just update
just check                      # validate
nh os build .                   # test build
```

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgetting `git add` on new file | `path '...' does not exist` during eval | `git add <file>; just check-staged` |
| Using `home-manager switch` directly with wrong `--flake .#` arg | `error: flake output has no attribute ...` | Use `nh home switch .` — auto-resolves config |
| Duplicating cache entries | Caches in `flake.nix` drift from `lib/caches.nix` | Edit both; verify identical |
| Running `sudo` on HM command | HM installs into root's profile | HM never needs sudo; use `nh home switch .` |
| `nh home switch` / `nh os switch` on the Mac | No config resolves / wrong platform | On `mbp-m4-pro` use `nh darwin switch .` — HM is a darwin module, not standalone |
| Building after `git stash` | Build sees pre-stash state | `git stash pop` or stage explicitly |
| `nix flake update` then forgetting to commit `flake.lock` | Reproducibility drift | Commit `flake.lock` with the input bump |

## When NOT to use this skill

- Editing thinkfan fan curves → use `thinkfan-tuning` skill
- Enrolling TPM / Lanzaboote keys → use `secure-boot-tpm` skill
- Editing secrets (agenix workflow) → use secret-specific commands (`agenix -e`, `just secret-edit`)
- Purely reading/exploring flake source — no rebuild needed
