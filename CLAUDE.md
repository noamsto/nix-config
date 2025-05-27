# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## System Management Commands

- `nh os switch` - Rebuild and switch NixOS configuration (preferred method using nix-helper)
- `update` - Shell alias for `sudo nixos-rebuild switch`
- `nix flake update` - Update flake inputs to latest versions
- `treefmt` - Format all code in the repository (alejandra for Nix, black for Python, etc.)

## Architecture Overview

This is a NixOS configuration using flakes with home-manager integration. The configuration supports multiple machines and profiles:

### Flake Structure

- Uses `flake-parts` for organization across x86_64-linux and aarch64-linux
- Outputs: `nixosConfigurations`, `homeConfigurations`, and `installerImages` for Raspberry Pi
- Development shell includes tools like `nh`, `agenix`, `treefmt`

### Configuration Layers

- **options.nix**: Centralized options system defining `desktop.mode`, `machine.type`, `profile`, user details
- **nixos/**: System-wide configurations (core, desktop environments, packages, virtualization)
- **home/**: User-specific configurations conditionally loaded based on `desktop.mode` and `profile`
- **hosts/**: Host-specific configurations that import base modules

### Conditional Loading Pattern

Configuration modules are conditionally imported based on system options:

```nix
++ lib.optionals (osConfig.desktop.mode != "none") [./browsers ./obs-studio]
++ lib.optionals (osConfig.desktop.mode == "kde") [./plasma-manager]
++ lib.optionals (osConfig.profile == "work") [./kubernetes ./zoom]
```

### Host Configurations

- **thinkpad-p14s/thinkpad-p14s-g5**: KDE laptops with work profile
- **naspi-nixos**: Raspberry Pi server with minimal setup
- **naspi-raspbian**: Standalone home-manager for Raspbian

### Key Features

- Multi-desktop support (KDE/Hyprland) with specializations for switching
- Work/personal profile separation
- Raspberry Pi 4 support with custom SD card images
- Catppuccin theming integration
- Secrets management with agenix

## Development Workflow

1. Make configuration changes in the appropriate module
2. If a new file is introduced (only new file) stage them so build won't fail
3. Test with `nh os test` or build with `nh os build` before switching or `nh os build -S` to build without specializations
4. Apply changes with `nh os switch`
5. Format code with `treefmt` before committing

## Important Files

- `flake.nix` - Main flake configuration
- `options.nix` - Global configuration options
- `hosts/nixos_hosts.nix` - Host definitions mapping
- `home/noams.nix` - Main user configuration with conditional imports
