# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **NixOS Configuration Repository** using Nix flakes that manages both NixOS system configurations and Home Manager user configurations. It's a personal dotfiles repository with support for multiple hosts (laptops, servers, Raspberry Pi) and desktop environments (KDE Plasma, Hyprland).

## Development Commands

### Core Development
```bash
nix develop              # Enter development shell with all tools
nix fmt                  # Format all code using alejandra and other formatters
nix flake check          # Validate flake configuration
nix flake update         # Update all inputs (equivalent to updating flake.lock)
```

### System Rebuilds
```bash
# Local system rebuild
sudo nixos-rebuild switch --flake .#<hostname>
nh os switch .           # Using nh helper (preferred)

# Home Manager only
home-manager switch --flake .#<config>

# Raspberry Pi deployment
./scripts/naspi-build-image.sh        # Build SD card image
./scripts/naspi-deploy.sh             # Deploy to existing naspi.local
./scripts/naspi-deploy.sh naspi.local install  # Fresh install via nixos-anywhere
```

### Available Hosts
- `thinkpad-p14s` - Main laptop configuration
- `thinkpad-p14s-g5` - Work laptop (G5 generation)  
- `naspi` - Raspberry Pi 4 NixOS configuration with PWM overlay
- `naspi-raspbian` - Raspberry Pi with Home Manager only

### Development Tools Available in Shell
- `agenix` - Secret management and editing
- `nh` - NixOS helper for easier rebuilds
- `nixos-anywhere` - Remote NixOS deployment
- `nom` (nix-output-monitor) - Better build output
- `prettier` - Code formatting for non-Nix files
- Pre-commit hooks (alejandra, prettier, shellcheck)

## Architecture Overview

### Configuration System
The repository uses a **modular architecture** with conditional imports based on configuration options:

- **`options.nix`** - Defines custom options that control what gets imported:
  - `desktop.mode`: "none" | "kde" | "hyprland" 
  - `machine.type`: "server" | "desktop" | "laptop"
  - `profile`: "personal" | "work"

- **Host-specific configurations** in `hosts/` set these options and import base modules
- **Conditional imports** throughout the codebase based on these options

### Directory Structure
```
├── flake.nix              # Main flake definition
├── options.nix            # Custom configuration options
├── nixos/                 # System-level NixOS modules
│   ├── core/              # Boot, locale, networking, users
│   ├── desktop/           # Desktop environments (KDE, SDDM)
│   └── virtualization/    # Containers, VMs
├── home/                  # User-level Home Manager modules  
│   ├── desktop/           # Desktop apps, window managers, themes
│   ├── terminal/          # Shell, terminal multiplexer
│   ├── nvim/              # Neovim configuration
│   └── git/               # Git and related tools
├── hosts/                 # Per-host configurations
├── secrets/               # Agenix encrypted secrets
├── packages/              # Custom package definitions
└── overlays/              # Nix package overlays
```

### Key Design Patterns

1. **Conditional Module Loading**: Modules check `osConfig` options before enabling features
2. **Profile-based Packages**: Work vs personal profile determines which packages are installed
3. **Secret Management**: Uses agenix for encrypted secrets with separate private repository
4. **Multi-architecture Support**: x86_64-linux and aarch64-linux (for Raspberry Pi)

## Important Configuration Files

- **`flake.nix`** - Main configuration with all inputs and outputs
- **`hosts/nixos_hosts.nix`** - Defines all NixOS system configurations
- **`home/noams.nix`** - Main Home Manager configuration entry point
- **`nixos/default.nix`** - System-level module imports and base configuration

## Working with Secrets

```bash
agenix -e secrets/<secret_name>.age    # Edit encrypted secret
agenix -r                              # Rekey all secrets
```

Secrets are stored in a separate private repository (`mysecrets` input) and managed via agenix.

## Development Environment Features

- **Pre-commit hooks** automatically format code and run checks
- **Treefmt integration** for consistent formatting across file types
- **Development shell** includes all necessary tools for managing the configuration
- **Multi-host support** with shared base configuration and host-specific overrides

## Testing Changes

1. **Stage relevant changes**: `git add <files>` (unstaged files won't be visible to nix builds!)
2. Use `nix flake check` to validate configuration
3. Test builds without switching: `nom build .#nixosConfigurations.<hostname>.config.system.build.toplevel`
4. For Home Manager: `nom build .#homeConfigurations.<config>.activationPackage`
5. Use `nh` for system builds: `nh os build .`

**Important**: Nix flakes only see files tracked by git, so stage your changes before testing builds.

## Common Patterns

- **Check `osConfig.profile`** when adding work-specific configurations
- **Use conditional imports** based on `desktop.mode` for desktop environment features  
- **Add new packages** to appropriate `packages.nix` files (system vs user level)
- **Follow existing module structure** when adding new functionality
- **Test on multiple hosts** when making system-wide changes