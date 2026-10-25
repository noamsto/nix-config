---
name: nix-rebuild
description: Use when rebuilding NixOS, nix-darwin or Home Manager, running nh, nixos-rebuild, darwin-rebuild, home-manager or nix flake/build/develop/fmt, verifying a flake change with the narrowest check, debugging a failed build, or hitting "path does not exist" errors on untracked files.
---

# Nix Rebuild Workflow

## Overview

The nix-config repo uses **flake-parts** and spans two platforms. **Pick the rebuild path by platform first:**

**Linux / NixOS hosts** (`tp-g6`):

- **Full rebuild** (system + user): `nh os switch .` — 2–3 min
- **HM-only rebuild** (user config only): `nh home switch .` — ~30 s

**macOS / nix-darwin host** (`mbp-m4-pro`):

- **Full rebuild** (system + user): `nh darwin switch .` — `nh os switch` is NixOS-only and does **not** work here.
- **HM-only rebuild** (user config only): `nh home switch .` — resolves through the darwin alias (see the macOS section below).

**Both platforms:** Home Manager is embedded in every host's system config, so the HM-only path activates config, services and dotfiles but **not packages** — those live in the system profile. Adding or removing a package needs the full rebuild.

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
| Home Manager rebuild (any host) | `nh home switch .` / `just hm` | `nom build .#<systems>.<host>.config.home-manager.users.noams.home.activationPackage` then run its `activate` |
| HM build only (any host) | `nh home build .` / `just home-build` | same attr path, without running `activate` |
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

The full rebuild is `nh os switch .` on NixOS and `nh darwin switch .` on macOS. The HM-only path is `nh home switch .` (or `just hm`) on both.

- **User config, no new packages** (shell, editor, dotfiles, wallpapers, services) → HM-only path
- **Any package added or removed**, including from a flake input bump → **full rebuild** to switch; verify the bump with the narrowest check below
- **System-level** (services, kernel, drivers, hardware, system packages) → full rebuild
- **Unsure** → the full rebuild does everything, always safe.

User explicitly prefers the HM-only path (CLAUDE.local.md) for config iterations — it skips the system toplevel build and needs no sudo.

**The package caveat is structural, not a bug.** Every host sets `useUserPackages = true`, so `home.packages` is delivered through the system profile (`/etc/profiles/per-user/noams`). The HM activation script's `installPackages` step is a bare `nixProfileRemove home-manager-path`, so an HM-only switch will report success and install nothing new. If a command is missing after one, that's why — run the full rebuild.

## macOS (nix-darwin) specifics

The Mac host `mbp-m4-pro` (`darwinConfigurations.mbp-m4-pro`) works differently from the Linux hosts:

- **Home Manager is integrated as a nix-darwin module** (`home-manager.darwinModules.home-manager`, `users.noams = home/noams.nix`), and `homeConfigurations."noams@mbp-m4-pro"` is an alias onto it rather than a standalone config. So `nh home switch` / `just hm` do work here for an HM-only pass; `nh os switch` is NixOS-only and does not apply. Use `nh darwin switch .` when the system itself changed.
- `nh darwin switch` works without the path arg too — `NH_FLAKE` is set to the repo (see `home/ai/.../default.nix`).
- **First switch / bootstrap** (before `darwin-rebuild` is on PATH): `nix run nix-darwin -- switch --flake ~/nix-config#mbp-m4-pro`. Full bootstrap steps live in `hosts/mbp-m4-pro/README.md`.
- **Caches & Nix settings** are managed by **Determinate Nix** via `determinateNix.customSettings` in the host's `default.nix` — *not* `flake.nix:nixConfig`/`lib/caches.nix` (those are the Linux path). Linux-only caches (hyprland, noctalia, vicinae, yazi, etc.) are intentionally omitted on darwin.
- **Cross-platform gating**: shared `home/` modules that pull Linux-only packages must be gated with `lib.optionals pkgs.stdenv.hostPlatform.isLinux [ ... ]` (package lists) or `lib.mkIf pkgs.stdenv.hostPlatform.isLinux { ... }` (config blocks — never condition `imports` on `pkgs`, it causes infinite recursion).

### `nh` can't find `nix` ("No output from nix --version")

**Symptom:** any `nh darwin …` (or `nh home`/`nh os`) invocation aborts immediately with `Failed to get Nix version output` / `No output from nix --version command`.

**Cause:** Determinate Nix's `nix` binary (`/nix/var/nix/profiles/default/bin/nix`) is added to PATH only by macOS `path_helper` (`/etc/paths.d/nix`), which runs for **login** shells. GUI-launched apps (Claude Code from the Dock/Spotlight) inherit PATH from launchd, which never runs `path_helper`, so neither they nor the direnv devshell they spawn see `nix`. The devshell ships `nh` but intentionally **not** `nix` (Determinate owns it — don't shadow it with a nixpkgs `nix`). Your interactive fish terminal is a login shell, so the bug only appears in GUI-launched / non-login contexts.

**Fix:** the repo's `.envrc` adds the profile bin to PATH on darwin (`PATH_add /nix/var/nix/profiles/default/bin` under an `$OSTYPE == darwin*` guard), so any tool run inside the project's direnv env gets `nix`. If you hit this outside the repo, prepend it manually:
```fish
PATH="/nix/var/nix/profiles/default/bin:$PATH" nh darwin switch .
```
(After editing `.envrc` you must re-run `direnv allow`.)

### Activation needs interactive sudo

`nh darwin switch` builds without sudo, then runs `sudo darwin-rebuild activate`. The activation prompts for a password, so it can't complete from a non-interactive/automated shell — run the switch from an interactive terminal (or, in Claude Code, via the `! nh darwin switch ~/nix-config` prompt-prefix). `nh darwin build .` validates the build with no sudo.

## Available configs

**NixOS hosts:** `tp-g6`, `halo`

**nix-darwin host:** `mbp-m4-pro` (personal, macOS) — rebuild with `nh darwin switch .`

**HM configs:** `noams@tp-g6`, `noams@halo`, `noams@mbp-m4-pro`, plus legacy aliases (`noams`, `noams-hyprland`). `nh home` auto-picks the right one. None of these are standalone — each is an alias onto its host's embedded HM (`flake-modules/home-manager.nix`), so there is exactly one evaluation per host.

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
   nom build .#nixosConfigurations.tp-g6.config.system.build.toplevel
   ```

## Devshell (`nix develop` / `just dev`)

Provides: `agenix`, `nh`, `home-manager`, `nom`, `nixos-anywhere`, `just`, `prettier`, `statix`, `shellcheck`, `jq`, `tokei`, plus pre-commit hooks (alejandra, ruff, shfmt, shellcheck via treefmt).

Aliases inside the shell: `nbuild` = `nom build`, `dev-stats` = project stats via tokei+git.

## Binary caches

Pre-configured in `flake.nix:nixConfig` and mirrored in `lib/caches.nix` — **keep them in sync when editing either**. Active caches: `cache.nixos.org`, `cache.flakehub.com`, `hyprland.cachix.org`, `vicinae.cachix.org`, `claude-code.cachix.org`, `nixpkgs-unfree.cachix.org`, `nix-community.cachix.org`, `yazi.cachix.org`, `numtide.cachix.org`.

No manual config needed; they apply automatically.

## Verifying a change: narrowest check first

Verify with the **narrowest** attr that answers the question. A whole-system build (`nh os build`, `.toplevel`) or `just check` (it evaluates every host and runs every check) costs minutes. Use one only as the final gate before a switch, or when the change touches system-wide wiring such as module imports, overlays every host consumes, or a bump of a widely consumed input (nixpkgs, home-manager, inputs whose own overlay or module every host imports). An input that supplies a single package is not system-wide: build that package.

| Question | Narrowest check |
|---|---|
| Does a patched/overlaid package build? | `nix build --no-link .#nixosConfigurations.<host>.pkgs.<pkg>` |
| Did the overlay/patch land? (no build) | `nix eval --json .#nixosConfigurations.<host>.pkgs.<pkg>.patches` |
| Did a single-package input bump build and do what it was bumped for? | `nix build --no-link --print-out-paths .#nixosConfigurations.<host>.pkgs.<pkg>` (if not in `pkgs`: direct input `.#nixosConfigurations.<host>._module.specialArgs.inputs.<input>.packages.x86_64-linux.<pkg>`; nested input `….specialArgs.inputs.<parent>.inputs.<input>.packages.x86_64-linux.<pkg>`, with `<parent>` from `jq -r '.nodes \| to_entries[] \| select((.value.inputs // {}) \| to_entries \| any(.value == "<input>")) \| .key' flake.lock`), then run the motivating behaviour check on the built binary |
| What value does an option end up with? | `nix eval .#nixosConfigurations.<host>.config.<option.path>` |
| What does a generated HM file contain? | `nix build --no-link --print-out-paths '.#nixosConfigurations.<host>.config.home-manager.users.noams.xdg.configFile."<name>".source'` |
| Does one flake check pass? | `nix build --no-link .#checks.x86_64-linux.<name>` |
| Does the whole host still evaluate and build? | `nh os build .` (final gate only) |

`<host>` is the current machine (`hostname`) unless the change targets another one. `.#nixosConfigurations.<host>.pkgs` is the host's own package set, with every overlay applied, so a package built there is exactly the one the switch will use.

Before committing: `git add <files>`, run the narrowest check, then `nh os switch .` (or `nh home switch .` for HM-only config) as the real activation.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgetting `git add` on new file | `path '...' does not exist` during eval | `git add <file>; just check-staged` |
| Using `home-manager switch` directly with wrong `--flake .#` arg | `error: flake output has no attribute ...` | Use `nh home switch .` — auto-resolves config |
| Duplicating cache entries | Caches in `flake.nix` drift from `lib/caches.nix` | Edit both; verify identical |
| Running `sudo` on HM command | HM installs into root's profile | HM never needs sudo; use `nh home switch .` |
| `nh os switch` on the Mac | Wrong platform, nothing resolves | On `mbp-m4-pro` use `nh darwin switch .`; `nh home switch` works for an HM-only pass |
| Adding a package, then only `nh home switch` | Switch succeeds, command still missing | Packages come from the system profile — run the full rebuild |
| Building after `git stash` | Build sees pre-stash state | `git stash pop` or stage explicitly |
| `nix flake update` then forgetting to commit `flake.lock` | Reproducibility drift | Commit `flake.lock` with the input bump |

## When NOT to use this skill

- Editing thinkfan fan curves → use `thinkfan-tuning` skill
- Enrolling TPM / Lanzaboote keys → use `secure-boot-tpm` skill
- Editing secrets (agenix workflow) → use secret-specific commands (`agenix -e`, `just secret-edit`)
- Purely reading/exploring flake source — no rebuild needed
