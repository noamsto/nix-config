---
name: nix-rebuild
description: Use when rebuilding NixOS, nix-darwin or Home Manager, running nh, nixos-rebuild, darwin-rebuild, home-manager or nix flake/build/develop/fmt, verifying a flake change with the narrowest check, debugging a failed build, or hitting "path does not exist" errors on untracked files.
---

# Nix Rebuild Workflow

## Overview

This repo is a public library built on **flake-parts**. Its flake has two x86_64 evaluation fixtures, `nixosConfigurations.example` (headless, username `user`) and `example-desktop` (Hyprland laptop, evaluated only, never built), plus `example-rpi4`. The real hosts (NixOS laptops, the nix-darwin Mac) and their Home Manager aliases live in the **private flake**, which imports this repo as its `nix-config` input.

- **In this repo:** verify with `.#nixosConfigurations.example` and `nix flake check`. No `nh`, no `just switch`/`hm`/`build` (those recipes live in the private flake).
- **Real hosts:** build or switch from the private flake, pointing its `nix-config` input at this checkout to test local changes:
  ```fish
  nh os build <private-flake> -- --override-input nix-config git+file:$PWD         # NixOS
  nh darwin build <private-flake> -- --override-input nix-config git+file:$PWD     # macOS
  ```
  Use `switch` instead of `build` to activate. `nh os` is NixOS-only; `nh darwin` is macOS-only.

Home Manager is embedded in every host's system config, so an HM-only activation covers config, services and dotfiles but **not packages**; those live in the system profile. Adding or removing a package needs a full system switch.

**Core principle:** Flakes only see **git-tracked** files. Always `git add` before build.

## The git-add gotcha (load-bearing)

**Symptom:** `error: path '/nix/store/...-source/some/file.nix' does not exist` or "file not found" during evaluation.

**Cause:** You created or edited a file but did not `git add` it. `nix` evaluates the flake from the git index, so untracked changes are invisible.

**Fix:**
```fish
git add <files>          # stage new/modified files
just check-staged        # verify what's staged before building
```

This applies to **every** build path: `nh`, `nix build`, `nix flake check`. With `--override-input nix-config git+file:$PWD`, nix still copies only what git tracks in this checkout.

## Quick Reference

| Task | Command |
|---|---|
| Validate flake | `just check` / `nix flake check` |
| Evaluate the example host | `nix eval --raw .#nixosConfigurations.example.config.system.build.toplevel.drvPath` |
| Build one flake check | `nix build --no-link .#checks.<system>.<name>` |
| Build a real host with local changes | `nh os build <private-flake> -- --override-input nix-config git+file:$PWD` (macOS: `nh darwin build ...`) |
| Format all code | `just fmt` / `nix fmt` |
| Update inputs | `just update` / `nix flake update` |
| Enter devshell | `just dev` / `nix develop` |
| Flake info | `just status` / `just info` |
| Verify staged files | `just check-staged` |
| GC build artifacts | `just clean` / `just clean-all` |

## Which rebuild path?

- **Checking a change in this repo** -> the narrowest check below against `example`; for changes under `home/desktop`, `nixos/desktop`, `nixos/hyprland` or `nixos/laptop`, also eval `example-desktop` (eval only, never build it).
- **Needs a real host** (host-specific wiring, package set, activation) -> private flake with `--override-input nix-config git+file:$PWD`.
- **Any package added or removed**, including from a flake input bump -> full system switch from the private flake; verify the bump with the narrowest check first.
- **User config only** (shell, editor, dotfiles, services) -> the private flake's HM-only path is enough.

**The package caveat is structural, not a bug.** Every host sets `useUserPackages = true`, so `home.packages` is delivered through the system profile (`/etc/profiles/per-user/<user>`). The HM activation script's `installPackages` step is a bare `nixProfileRemove home-manager-path`, so an HM-only switch will report success and install nothing new. If a command is missing after one, run the full switch.

## macOS (nix-darwin) specifics

- **Home Manager is integrated as a nix-darwin module** (`darwinModules.home`, i.e. `darwin/home.nix`, which imports `home-manager.darwinModules.home-manager` and binds `users.${config.username}.imports = [self.homeModules.default]`, i.e. `home/profile.nix`). `nh os` does not apply on the Mac; use `nh darwin`.
- **First switch / bootstrap** (before `darwin-rebuild` is on PATH) runs from the private flake: `nix run nix-darwin -- switch --flake <private-flake>#<host>`. Full bootstrap steps live there.
- **Caches & Nix settings** are managed by **Determinate Nix** via `determinateNix.customSettings` in `darwin/base.nix` (`darwinModules.base`) — *not* `flake.nix:nixConfig`/`lib/caches.nix` (those are the Linux path). Linux-only caches (hyprland, noctalia, vicinae, yazi, etc.) are intentionally omitted on darwin.
- **Cross-platform gating**: shared `home/` modules that pull Linux-only packages must be gated with `lib.optionals pkgs.stdenv.hostPlatform.isLinux [ ... ]` (package lists) or `lib.mkIf pkgs.stdenv.hostPlatform.isLinux { ... }` (config blocks — never condition `imports` on `pkgs`, it causes infinite recursion).

### `nh` can't find `nix` ("No output from nix --version")

**Symptom:** any `nh darwin …` (or `nh os`) invocation aborts immediately with `Failed to get Nix version output` / `No output from nix --version command`.

**Cause:** Determinate Nix's `nix` binary (`/nix/var/nix/profiles/default/bin/nix`) is added to PATH only by macOS `path_helper` (`/etc/paths.d/nix`), which runs for **login** shells. GUI-launched apps (Claude Code from the Dock/Spotlight) inherit PATH from launchd, which never runs `path_helper`, so neither they nor the direnv devshell they spawn see `nix`. The devshell ships `nh` but intentionally **not** `nix` (Determinate owns it — don't shadow it with a nixpkgs `nix`). Your interactive fish terminal is a login shell, so the bug only appears in GUI-launched / non-login contexts.

**Fix:** the repo's `.envrc` adds the profile bin to PATH on darwin (`PATH_add /nix/var/nix/profiles/default/bin` under an `$OSTYPE == darwin*` guard), so any tool run inside the project's direnv env gets `nix`. If you hit this outside the repo, prepend it manually:
```fish
PATH="/nix/var/nix/profiles/default/bin:$PATH" nh darwin build <private-flake>
```
(After editing `.envrc` you must re-run `direnv allow`.)

### Activation needs interactive sudo

`nh darwin switch` builds without sudo, then runs `sudo darwin-rebuild activate`. The activation prompts for a password, so it can't complete from a non-interactive/automated shell — run the switch from an interactive terminal (or, in Claude Code, via the `!` prompt prefix). `nh darwin build` validates the build with no sudo.

## Available configs

- **In this repo:** `nixosConfigurations.example` (headless), `example-desktop` (Hyprland laptop, eval only) and `example-rpi4`.
- **Real hosts and Home Manager aliases:** defined in the private flake. None of the HM aliases are standalone; each is an alias onto its host's embedded HM, so there is one evaluation per host.

## Debugging failed builds

1. **Re-run with trace** — shows the full evaluation stack:
   ```fish
   nix eval --show-trace .#nixosConfigurations.example.config.system.build.toplevel.drvPath
   nh os build <private-flake> -- --override-input nix-config git+file:$PWD --show-trace
   ```
   (The `--` forwards flags to the underlying `nixos-rebuild` / `darwin-rebuild`.)

2. **Validate flake structure** — catches syntax/eval errors without building:
   ```fish
   nix flake check --show-trace
   ```

3. **Check staged files** — many "missing file" errors are an un-`git add`ed file:
   ```fish
   just check-staged
   ```

4. **Better build output** — `nom` (nix-output-monitor) is in the devshell and gives readable tree output:
   ```fish
   nom build .#nixosConfigurations.example.config.system.build.toplevel
   ```

## Devshell (`nix develop` / `just dev`)

Provides: `nh`, `home-manager`, `nom`, `nixos-anywhere`, `just`, `prettier`, `statix`, `shellcheck`, `jq`, `tokei`, plus pre-commit hooks (`treefmt` running alejandra, ruff, statix, deadnix, shellcheck, shfmt and prettier; plus check-json, check-merge-conflicts and betterleaks).

Aliases inside the shell: `nbuild` = `nom build`, `dev-stats` = project stats via tokei+git.

## Binary caches

Pre-configured in `flake.nix:nixConfig` and mirrored in `lib/caches.nix` — **keep them in sync when editing either**. Active substituters: `cache.nixos.org`, `install.determinate.systems`, `vicinae.cachix.org`, `nix-amd-ai.cachix.org`, `wtc.cachix.org`, `noctalia.cachix.org`, `lazytmux.cachix.org`, `dispatcher.cachix.org`, `jovian-nixos.cachix.org`, `noamsto-nix-config.cachix.org`, `nix-cache.stole.ro`, plus the extra substituters `nixpkgs-unfree.cachix.org`, `nix-community.cachix.org`, `yazi.cachix.org`, `nixos-raspberrypi.cachix.org`, `cache.numtide.com`. The FlakeHub signing keys stay trusted because `install.determinate.systems` signs with them; `cache.flakehub.com` itself is not a substituter. CI pushes to both `noamsto-nix-config.cachix.org` and the R2 cache `nix-cache.stole.ro` (`scripts/nix-cache/nix_cache.py`); Cachix goes away once R2 is proven.

No manual config needed; they apply automatically.

## Verifying a change: narrowest check first

Verify with the **narrowest** attr that answers the question. A whole-system build (`.toplevel`) or `just check` (it evaluates the host and runs every check) costs minutes. Use one only as the final gate, or when the change touches system-wide wiring such as module imports, overlays every host consumes, or a bump of a widely consumed input (nixpkgs, home-manager, inputs whose own overlay or module every host imports). An input that supplies a single package is not system-wide: build that package.

| Question | Narrowest check |
|---|---|
| Does a patched/overlaid package build? | `nix build --no-link .#nixosConfigurations.example.pkgs.<pkg>` |
| Did the overlay/patch land? (no build) | `nix eval --json .#nixosConfigurations.example.pkgs.<pkg>.patches` |
| Did a single-package input bump build and do what it was bumped for? | `nix build --no-link --print-out-paths .#nixosConfigurations.example.pkgs.<pkg>` (if not in `pkgs`, for a direct input: `nix build --no-link --print-out-paths --inputs-from . <input>#packages.<system>.<pkg>`; nested inputs resolve via the private flake), then run the motivating behaviour check on the built binary |
| What value does an option end up with? | `nix eval .#nixosConfigurations.example.config.<option.path>` |
| What does a generated HM file contain? | `nix build --no-link --print-out-paths '.#nixosConfigurations.example.config.home-manager.users.user.xdg.configFile."<name>".source'` |
| Does one flake check pass? | `nix build --no-link .#checks.x86_64-linux.<name>` |
| Does the whole example host still evaluate and build? | `nix build --no-link .#nixosConfigurations.example.config.system.build.toplevel` (final gate only) |

`.#nixosConfigurations.example.pkgs` is the host's own package set, with every overlay applied, so a package built there is exactly the one a switch will use. For a check that depends on a real host's settings, use the same attr paths from the private flake with `--override-input nix-config git+file:$PWD`.

Before committing: `git add <files>`, run the narrowest check, then build the real host from the private flake as the final gate.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgetting `git add` on new file | `path '...' does not exist` during eval | `git add <file>; just check-staged` |
| Running `nh os switch .` / `nh home switch .` in this repo | No such host or alias | Real hosts live in the private flake; here use `.#nixosConfigurations.example` |
| Building the private flake without the override | Tests the pinned `nix-config`, not your edits | Add `-- --override-input nix-config git+file:$PWD` |
| Duplicating cache entries | Caches in `flake.nix` drift from `lib/caches.nix` | Edit both; verify identical |
| Running `sudo` on an HM command | HM installs into root's profile | HM never needs sudo |
| `nh os` on the Mac | Wrong platform, nothing resolves | Use `nh darwin` |
| Adding a package, then only an HM-only switch | Switch succeeds, command still missing | Packages come from the system profile — run the full switch |
| Building after `git stash` | Build sees pre-stash state | `git stash pop` or stage explicitly |
| `nix flake update` then forgetting to commit `flake.lock` | Reproducibility drift | Commit `flake.lock` with the input bump |

## When NOT to use this skill

- Editing thinkfan fan curves → use `thinkfan-tuning` skill
- Enrolling TPM / Lanzaboote keys → use `secure-boot-tpm` skill
- Editing secrets -> they live in the private flake; use its tooling
- Purely reading/exploring flake source — no rebuild needed
