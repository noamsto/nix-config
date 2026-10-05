# CLAUDE.md

NixOS and Home Manager configuration for personal laptops, using flake-parts. Desktop modes are KDE Plasma and Hyprland; x86_64-linux only. Raspberry Pi configs live in `noamsto/nix-rpi`.

## Skills

Project skills load on demand from `.agents/skills` (symlinked into `.claude/skills`). Call the matching one before running commands, since the gotchas live only there:

- `nix-rebuild`: any `nh`, `nixos-rebuild`, `home-manager`, `nix flake`/`build`/`develop`/`fmt`, verifying a change, or debugging a failed build. Has the narrowest-check ladder and the `git add` gotcha.
- `thinkfan-tuning`: `hardware.thinkpad.thinkfan`, fan curves, sensor paths.
- `secure-boot-tpm`: Lanzaboote, Secure Boot keys, TPM2 LUKS enrollment (hosts importing `nixos/core/lanzaboote.nix`).
- `nix-package-authoring`: new derivations under `packages/`, `nurl`/`nix-init`, `nix-locate`.
- `claude-code-settings`: `home/ai/claude-code` settings, hooks, plugins.
- `nested-wayland`: launching a nested Hyprland, or portals failing after one.

## Large files

`home/terminal/fish/default.nix` (~545 lines), `home/desktop/noctalia/default.nix` (~640) and `home/desktop/hyprland/scripts/sh/theme-toggle.sh` (~1500) are too big to read whole. Search for the option or function first and read only that slice.

## How configuration flows

`options.nix` defines the custom options: `desktop.mode` (none/kde/hyprland), `machine.type` (server/desktop/laptop), `profile` (personal/work), `username`, `email`, `hostname`, and the read-only `flakePath`. `lib/host-configs.nix` is the single source of truth for per-host settings and SSH public keys; NixOS hosts (`hosts/*/default.nix`) and the `homeConfigurations` aliases in `flake-modules/home-manager.nix` both take their values from it, using `inherit`. Home Manager modules read `osConfig`, so a new host needs an entry in `host-configs.nix`.

Gate features with `lib.optionals` or conditional imports on these options:

- `osConfig.profile == "work"` for work packages (`home/work/`) and the kubernetes module.
- `osConfig.desktop.mode == "hyprland"` for Hyprland modules; desktop packages only when `desktop.mode != "none"`.
- Use the derived booleans instead of raw comparisons: `config.desktop.isEnabled`, `config.desktop.isHyprland`, `config.machine.isLaptop`, `config.machine.isPC`. Write `inherit (config.machine) isLaptop;` in let-bindings.
- Use `config.flakePath` (NixOS) or `config.home.homeDirectory` (HM) instead of hardcoded paths.

Packages: system-wide ones go in `nixos/packages.nix`, user ones in `home/packages.nix` with profile/desktop conditionals. NixOS modules go under `nixos/`, Home Manager modules under `home/`, each with a `default.nix` using `imports = [...]`. Binary caches are in `lib/caches.nix` and must stay in sync with the `nixConfig` in `flake.nix`. After system-wide changes, check both `nh os switch` and `nh home switch`.

## Secrets

Agenix; encrypted files live in the private `mysecrets` flake input. Use `just secret-edit <name>`, `just secret-rekey`, `just secret-list` (or `agenix -e secrets/<name>.age`, `agenix -r`).

## Gotchas

- profile-sync-daemon was removed 2026-04-28 (commit `75d96c6`). Do not re-enable it unless both hold: nixpkgs psd v7+ ships fuse-overlayfs (watch PR #500548), and a real wear-or-APST benchmark on modern NVMe supports it. The rationale is in the comment block in `nixos/core/pc.nix`, which also lists the per-host on-disk cleanup (firefox profile symlink + `default-backup/`) needed on first switch.

- Noctalia 3rd-party plugins use composite keys. Plugins outside the official `github.com/noctalia-dev/noctalia-plugins` repo are keyed `<first-6-hex-of-sha256(sourceUrl)>:<manifest-id>` in `plugins.json`, in both the `states` map and the bar widget id (source: `PluginRegistry.generateCompositeKey`). Compute the prefix in `home/desktop/noctalia/default.nix` with `builtins.substring 0 6 (builtins.hashString "sha256" sourceUrl)`. A wrong key causes an endless reinstall and orphan-delete loop of the bar widget.

- Pre-commit hooks reformat files, so the first `git commit` fails. The hooks (`alejandra`, `deadnix`, `statix`, `prettier`; see `flake-modules/development.nix`) rewrite files and exit non-zero with `files were modified by this hook`. This is expected: `git add` the reformatted files and re-run the same commit, which then passes. If statix or deadnix flagged something (e.g. repeated `home.*` keys), fix the source first, then re-stage and commit. Do not change the commit message.

- Pin fetchers to a commit SHA, never a branch ref. `fetchFromGitHub` (or any fixed-output fetcher) with `rev = "main"` plus a fixed hash only works until upstream pushes, then fails with `hash mismatch in fixed-output derivation`. This broke the Mac rebuild for `gvfs.yazi` and `freecad-mcp` (commits `4d69769`, `0cc4cb6`). Pin `rev` to a full 40-char commit and scaffold with `nurl <url>`. Find offenders with `grep -rnE 'rev = "(main|master|HEAD)"' --include=*.nix .`.

- Nested Wayland compositors need their own `XDG_RUNTIME_DIR`, or a later `nh os switch` can fail activation. See the `nested-wayland` skill.

Run `just --list` for the command recipes.
