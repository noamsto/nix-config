---
name: nix-rebuild
description: Use when rebuilding NixOS or Home Manager, running any `nh`, `nixos-rebuild`, `home-manager`, `nix flake`, `nix build`, `nix develop`, `nix fmt` command, testing a flake change, debugging a failed build, or hitting "file not found" / "path does not exist" errors on untracked files. Applies to the nix-config repo workflow (flake-parts, hybrid Home Manager, justfile wrappers).
---

# Nix Rebuild Workflow

## Overview

The nix-config repo uses **flake-parts** with two parallel rebuild paths:

- **Full rebuild** (system + user): `nh os switch .` — 2–3 min
- **HM-only rebuild** (user config only): `nh home switch .` — ~30 s

Most commands have three forms: `nh` wrapper → `just` recipe → raw `nix`/`nixos-rebuild`. Prefer `nh` for rebuilds; use `just` for common chores; drop to raw `nix` only when the wrappers don't fit.

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
| Full system rebuild | `nh os switch .` | `sudo nixos-rebuild switch --flake .#<host>` |
| System build only (no activate) | `nh os build .` | `nom build .#nixosConfigurations.<host>.config.system.build.toplevel` |
| Apply at next boot | `nh os boot .` | `sudo nixos-rebuild boot --flake .#<host>` |
| Home Manager rebuild | `nh home switch .` | `home-manager switch --flake .#<config>` |
| HM build only | `nh home build .` | `nom build .#homeConfigurations.<config>.activationPackage` |
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

- **User config only** (shell, editor, dotfiles, wallpapers, user packages) → `nh home switch .`
- **System-level** (services, kernel, drivers, hardware, system packages) → `nh os switch .`
- **Unsure** → `nh os switch .` rebuilds both, always safe.

User explicitly prefers `nh home switch` (CLAUDE.local.md) for HM iterations — it's ~6× faster and doesn't need sudo.

## Available configs

**NixOS hosts:** `thinkpad-p14s-g5` (work), `thinkpad-p14s-g6` (personal)

**Standalone HM configs:** `noams@thinkpad-p14s-g5`, `noams@thinkpad-p14s-g6`, plus legacy aliases (`noams-hyprland`, `noams-hyprland-work`). `nh home` auto-picks the right one.

## Debugging failed builds

1. **Re-run with trace** — shows the full evaluation stack:
   ```fish
   nh os switch . -- --show-trace
   nh home switch . -- --show-trace
   ```
   (The `--` forwards flags to the underlying `nixos-rebuild` / `home-manager`.)

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
| Building after `git stash` | Build sees pre-stash state | `git stash pop` or stage explicitly |
| `nix flake update` then forgetting to commit `flake.lock` | Reproducibility drift | Commit `flake.lock` with the input bump |

## When NOT to use this skill

- Editing thinkfan fan curves → use `thinkfan-tuning` skill
- Enrolling TPM / Lanzaboote keys → use `secure-boot-tpm` skill
- Editing secrets (agenix workflow) → use secret-specific commands (`agenix -e`, `just secret-edit`)
- Purely reading/exploring flake source — no rebuild needed
