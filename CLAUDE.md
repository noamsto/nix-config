# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **NixOS Configuration Repository** using Nix flakes that manages both NixOS system configurations and Home Manager user configurations. It's a personal dotfiles repository with support for multiple hosts (laptops) and desktop environments (KDE Plasma, Hyprland). Raspberry Pi configurations live in a separate repo (`noamsto/nix-rpi`).

## Skills

Command-heavy and host-specific reference material lives in skills (loaded on demand), not in this file:

- **`nix-rebuild`** — invoke before running `nh`, `nixos-rebuild`, `home-manager`, `nix flake` / `build` / `develop` / `fmt`, or debugging a failed build. Covers the `git add` gotcha, `just` wrappers, host/config list, binary caches, devshell tooling.
- **`thinkfan-tuning`** — invoke when editing `hardware.thinkpad.thinkfan`, fan curves, or sensor paths on ThinkPad hosts (gen4/gen5/gen6).
- **`secure-boot-tpm`** — invoke when touching Lanzaboote, Secure Boot keys, or TPM2 LUKS enrollment on hosts that import `nixos/core/lanzaboote.nix` (currently g5, g6).

If a task matches any of the above, call the skill **before** running commands — the workflow gotchas only live there.

## Architecture Overview

### Flake-Parts Modular Structure

This flake uses **flake-parts** for a modular, composable architecture:

```
flake.nix                          # Entry point - imports flake-modules
├── flake-modules/
│   ├── development.nix            # devShells, treefmt, pre-commit hooks
│   ├── nixos-systems.nix          # All nixosConfigurations
│   └── home-manager.nix           # Standalone homeConfigurations
├── lib/
│   ├── host-configs.nix           # Shared host settings + SSH keys (used by both NixOS and HM)
│   ├── caches.nix                 # Binary cache configuration (SYNC with flake.nix nixConfig)
│   └── overlays.nix               # Package overlays
├── packages/                      # Custom package definitions
└── justfile                       # Command runner recipes
```

**Key benefits:**

- Each flake module is self-contained and focused
- Outputs are defined close to their implementation
- Easy to add new systems or outputs without modifying flake.nix
- `perSystem` configuration in development.nix handles per-architecture setup

### Configuration System

The repository uses a **modular architecture** with conditional imports based on configuration options:

**Core Configuration Files:**

- **`options.nix`** - Defines custom options that control what gets imported:
  - `desktop.mode`: "none" | "kde" | "hyprland"
  - `desktop.isEnabled`, `desktop.isHyprland` - Derived read-only booleans
  - `machine.type`: "server" | "desktop" | "laptop"
  - `machine.isLaptop`, `machine.isPC` - Derived read-only booleans
  - `profile`: "personal" | "work"
  - `username`, `email`, `hostname` - Per-host identity settings
  - `flakePath` - Derived from username, read-only (e.g. `/home/noams/nix-config`)

  **Use derived booleans** in modules instead of raw comparisons:
  ```nix
  # Good - use derived options
  inherit (config.machine) isLaptop;
  inherit (config.desktop) isEnabled;

  # Avoid - raw comparisons
  isLaptop = config.machine.type == "laptop";
  ```

- **`lib/host-configs.nix`** - Shared configuration source of truth:
  - Single file defining settings for all hosts
  - Contains `sshPublicKeys` for shared SSH key constants
  - Used by **both** NixOS systems and standalone Home Manager configs
  - Ensures consistency between full rebuilds and HM-only rebuilds
  - All hosts should use `inherit` from this file

**How Configuration Flows:**

1. **NixOS systems** (`hosts/*/default.nix`) import host config and set options
2. **Standalone HM configs** (`flake-modules/home-manager.nix`) pass host config as `osConfig`
3. **Modules** check `osConfig` options to conditionally enable features
4. **Package lists** use `lib.optionals` to add packages based on profile/desktop mode

### Directory Structure

```
├── flake.nix              # Entry point - imports flake-modules
├── flake-modules/         # Flake-parts modules (systems, HM, dev)
├── justfile               # Command runner recipes
├── options.nix            # Custom configuration options
├── lib/                   # Shared config (host-configs, caches, overlays)
├── nixos/                 # System-level NixOS modules
│   ├── core/              # Boot, locale, networking, users, lanzaboote, pc.nix
│   ├── desktop/           # Desktop environments (KDE, SDDM)
│   ├── hardware/          # ThinkPad-specific (thinkpad-common, thinkfan)
│   ├── hyprland/          # Hyprland compositor system config
│   ├── laptop/            # Laptop features (pam-lid-check, suspend-handling)
│   ├── services/          # System services
│   ├── virtualization/    # Containers, VMs
│   └── xremap/            # Key remapping
├── home/                  # User-level Home Manager modules
│   ├── ai/                # AI tools (opencode, etc.)
│   ├── desktop/           # Desktop apps, window managers, themes
│   ├── terminal/          # Shell, terminal multiplexer
│   ├── nvim/              # Neovim/LazyVim configuration
│   ├── git/               # Git and related tools
│   ├── kubernetes/        # K8s tools (work profile only)
│   └── work/              # Work profile packages (slack, AWS, etc.)
├── hosts/                 # Per-host configurations (thinkpad-p14s, thinkpad-p14s-g5, thinkpad-p14s-g6)
├── secrets/               # Agenix encrypted secrets
├── packages/              # Custom package definitions
└── overlays/              # Nix package overlays
```

### Key Design Patterns

1. **Conditional Module Loading**: Modules check `osConfig` options before enabling features
   - Example: `home/desktop/default.nix` only imports Hyprland if `osConfig.desktop.mode == "hyprland"`
   - Example: `home/noams.nix` only imports kubernetes module if `osConfig.profile == "work"`

2. **Profile-based Packages**: Work vs personal profile determines which packages are installed
   - Work packages defined in `home/work/default.nix`, imported when `osConfig.profile == "work"`
   - Work packages include: slack, AWS tools, chromium, postman, dbeaver
   - Desktop packages only installed when `osConfig.desktop.mode != "none"`

3. **Shared Configuration**: `lib/host-configs.nix` ensures NixOS and Home Manager stay in sync
   - Both full rebuilds and HM-only rebuilds use the same source of truth
   - Prevents drift between system and user configurations

4. **Secret Management**: Uses agenix for encrypted secrets with separate private repository
   - Secrets stored in `mysecrets` flake input (private GitHub repo)
   - Edit with: `agenix -e secrets/<secret_name>.age` or `just secret-edit <secret_name>`

5. **Single architecture**: x86_64-linux only (RPi configs live in `noamsto/nix-rpi`)
   - `perSystem` in flake-parts handles per-architecture outputs

## Important Configuration Files

- **`flake.nix`** - Entry point, imports flake-modules
- **`justfile`** - Command runner with convenient wrappers
- **`flake-modules/nixos-systems.nix`** - Defines all NixOS system configurations
- **`flake-modules/home-manager.nix`** - Standalone Home Manager configurations with auto-detection
- **`lib/host-configs.nix`** - Shared host settings (source of truth)
- **`options.nix`** - Custom option definitions
- **`home/noams.nix`** - Main Home Manager configuration entry point
- **`home/default.nix`** - Home Manager module entry point (for NixOS module usage)
- **`nixos/default.nix`** - System-level module imports

## Working with Secrets

```bash
agenix -e secrets/<secret_name>.age    # Edit encrypted secret
agenix -r                              # Rekey all secrets

# Or use just commands:
just secret-edit <secret_name>         # Edit encrypted secret
just secret-rekey                      # Rekey all secrets
just secret-list                       # List available secrets
```

Secrets are stored in a separate private repository (`mysecrets` input) and managed via agenix.

## Common Patterns

When adding new features, follow these patterns:

- **Use derived boolean options** in NixOS modules instead of raw comparisons:
  - `config.desktop.isEnabled` instead of `config.desktop.mode != "none"`
  - `config.desktop.isHyprland` instead of `config.desktop.mode == "hyprland"`
  - `config.machine.isLaptop` instead of `config.machine.type == "laptop"`
  - `config.machine.isPC` instead of `isLaptop || isDesktop`
  - Use `inherit (config.machine) isLaptop;` for cleaner let-bindings

- **Check `osConfig.profile`** when adding work-specific configurations
  - Example: `++ lib.optionals (osConfig.profile == "work") work-packages`

- **Use conditional imports** based on `desktop.mode` for desktop environment features
  - Example: `++ lib.optionals (osConfig.desktop.mode == "hyprland") [./hyprland]`

- **Use `config.flakePath`** (NixOS) or `config.home.homeDirectory` (HM) instead of hardcoded paths

- **Add new packages** to appropriate files:
  - `nixos/packages.nix` - System-wide packages (vim, git, essential CLI tools)
  - `home/packages.nix` - User packages with profile/desktop conditionals

- **Update `lib/host-configs.nix`** when adding a new host
  - This ensures both NixOS and standalone HM configs work consistently

- **Follow existing module structure** when adding new functionality
  - Place NixOS modules in `nixos/`
  - Place Home Manager modules in `home/`
  - Use `default.nix` as module entry point with `imports = [...]`

- **Test on multiple hosts** when making system-wide changes
  - Test with both `nh os switch` and `nh home switch` to catch issues


## Additional Resources

- Run `just help` for command usage
- Use `just --list` to discover all available commands
