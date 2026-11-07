# CLAUDE.md

NixOS and Home Manager configuration for personal laptops, using flake-parts. Desktop modes are Hyprland or none (headless); x86_64-linux and aarch64-linux (a generic Raspberry Pi base, `nixosModules.rpi`, plus the `example-rpi4` host), and aarch64-darwin for the darwin modules. Real Pi hosts live in the private flake.

## Skills

Project skills load on demand from `.agents/skills` (symlinked into `.claude/skills`). Call the matching one before running commands, since the gotchas live only there:

- `nix-rebuild`: verifying a change against the `example` host, running `nix flake`/`build`/`develop`/`fmt`, building real hosts from the private flake against this checkout, or debugging a failed build. Has the narrowest-check ladder and the `git add` gotcha.
- `thinkfan-tuning`: `hardware.thinkpad.thinkfan`, fan curves, sensor paths.
- `secure-boot-tpm`: Lanzaboote, Secure Boot keys, TPM2 LUKS enrollment (hosts importing `nixos/core/lanzaboote.nix`).
- `nix-package-authoring`: new derivations under `packages/`, `nurl`/`nix-init`, `nix-locate`.
- `claude-code-settings`: `home/ai/claude-code` settings, hooks, plugins.
- `nested-wayland`: launching a nested Hyprland, or portals failing after one.

## Large files

`home/terminal/fish/default.nix` (~545 lines), `home/desktop/noctalia/default.nix` (~640) and `home/desktop/hyprland/scripts/sh/theme-toggle.sh` (~1500) are too big to read whole. Search for the option or function first and read only that slice.

## How configuration flows

`options.nix` defines the custom options: `desktop.mode` (none/hyprland), `machine.type` (server/desktop/laptop), `username`, `email`, `hostname`, and `flakePath`. The real hosts and their per-host values live in the private flake, which imports this repo's exports (`nixosModules`, `homeModules`, `darwinModules`, `lib`; see `flake-modules/exports.nix`). `hosts/example` is the in-repo evaluation fixture (headless), and `hosts/example-desktop` its Hyprland-laptop twin (evaluated only, never built, so desktop modules are checked in CI). Host-specific behaviour that shared modules must not infer from the hostname is a `nix-config.*` option in `options.nix` (e.g. `nix-config.ai.localServer.enable`, `nix-config.terminal.remoteHosts`), set by the host; shared modules never compare `hostname` with a literal. Home Manager modules read `osConfig`, so host values are set as options in the host.

Gate features with `lib.optionals` or conditional imports on these options:

- `osConfig.desktop.mode == "hyprland"` for Hyprland modules; desktop packages only when `desktop.mode != "none"`.
- Use the derived booleans instead of raw comparisons: `config.desktop.isEnabled`, `config.desktop.isHyprland`, `config.machine.isLaptop`, `config.machine.isPC`. Write `inherit (config.machine) isLaptop;` in let-bindings.
- Use `config.flakePath` (NixOS) or `config.home.homeDirectory` (HM) instead of hardcoded paths.

Packages: system-wide ones go in `nixos/packages.nix`, user ones in `home/packages.nix` with desktop conditionals. NixOS modules go under `nixos/`, nix-darwin modules under `darwin/`, Home Manager modules under `home/`, each with a `default.nix` using `imports = [...]`. Binary caches are in `lib/caches.nix` and must stay in sync with the `nixConfig` in `flake.nix`. After system-wide changes, run `nix flake check` here, then build or switch the real hosts from the private flake.

## Secrets

Hosts and secrets live in the private flake; this repo has no secrets and no secret recipes. Shared modules take secret paths as `nix-config.*` options (e.g. `nix-config.user.hashedPasswordFile`) that the host sets, instead of reading a secrets backend's config.

## Gotchas

- profile-sync-daemon was removed 2026-04-28 (commit `75d96c6`). Do not re-enable it unless both hold: nixpkgs psd v7+ ships fuse-overlayfs (watch PR #500548), and a real wear-or-APST benchmark on modern NVMe supports it. The rationale is in the comment block in `nixos/core/pc.nix`, which also lists the per-host on-disk cleanup (firefox profile symlink + `default-backup/`) needed on first switch.

- Noctalia 3rd-party plugins use composite keys. Plugins outside the official `github.com/noctalia-dev/noctalia-plugins` repo are keyed `<first-6-hex-of-sha256(sourceUrl)>:<manifest-id>` in `plugins.json`, in both the `states` map and the bar widget id (source: `PluginRegistry.generateCompositeKey`). Compute the prefix in `home/desktop/noctalia/default.nix` with `builtins.substring 0 6 (builtins.hashString "sha256" sourceUrl)`. A wrong key causes an endless reinstall and orphan-delete loop of the bar widget.

- Pre-commit runs `treefmt` plus the non-formatter checks. `treefmt` owns every formatter and fixer (`alejandra`, `ruff`, `statix`, `deadnix`, `shellcheck`, `shfmt`, `prettier`; see `flake-modules/development.nix`), and `pre-commit-hooks.nix` holds the hook list (`treefmt`, `check-json`, `check-merge-conflicts`, `betterleaks`). `nix fmt` applies the same formatting, so format before committing. When a hook rewrites staged files it exits non-zero with `files were modified by this hook`: `git add` the reformatted files and re-run the same commit, which then passes. If statix or deadnix flagged something (e.g. repeated `home.*` keys), fix the source first, then re-stage and commit. Do not change the commit message.

- Pin fetchers to a commit SHA, never a branch ref. `fetchFromGitHub` (or any fixed-output fetcher) with `rev = "main"` plus a fixed hash only works until upstream pushes, then fails with `hash mismatch in fixed-output derivation`. This broke the Mac rebuild for `gvfs.yazi` and `freecad-mcp` (commits `4d69769`, `0cc4cb6`). Pin `rev` to a full 40-char commit and scaffold with `nurl <url>`. Find offenders with `grep -rnE 'rev = "(main|master|HEAD)"' --include=*.nix .`.

- Nested Wayland compositors need their own `XDG_RUNTIME_DIR`, or a later `nh os switch` can fail activation. See the `nested-wayland` skill.

- Inputs update nightly via `.github/workflows/update.yml` (logic in `scripts/update-bot/`). A nixpkgs package that breaks on a bump is pinned to the `nixpkgs-fallback` input through `pins.json` (the pin overlay is first in `lib/overlays.nix`). Hold a package by hand with a `"mode": "hold"` entry (top-level attrs only), freeze an input with `frozenInputs`, and never move `nixpkgs-fallback` by hand: the bot advances it only when no pins remain.

Run `just --list` for the command recipes.
