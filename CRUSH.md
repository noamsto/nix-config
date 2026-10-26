# CRUSH.md

This file provides guidance for coding agents working with this NixOS configuration repository.

## Build/Test Commands

```bash
nix develop              # Enter development shell with all tools
nix fmt                  # Format all code (alejandra + prettier + ruff + shellcheck)
nix flake check          # Validate flake configuration and run checks
nh os switch .           # Rebuild system (preferred over nixos-rebuild)
nh os build .            # Build without switching
nom build .#nixosConfigurations.<hostname>.config.system.build.toplevel  # Test specific host build
nix run home-manager/master -- switch --flake .#<config>  # Home Manager rebuild
```

## Code Style Guidelines

### Nix Code Style
- **Indentation**: 2 spaces, no tabs
- **Imports**: Use `{pkgs, lib, config, ...}: {` pattern with conditional imports via `lib.optionals`
- **Functions**: Use `let-in` blocks for local variables and utility functions
- **Attribute sets**: Trailing semicolons, consistent indentation, group related options
- **Package lists**: Use `with pkgs; [package1 package2]` format
- **Conditionals**: Use `lib.mkIf` for configuration, `lib.optionals` for lists
- **String interpolation**: Use `"${variable}"` syntax for variable substitution
- **Comments**: Single line `#`, multi-line `/* */`

### Module Structure
- Entry points use `default.nix` files
- Host configs in `hosts/` set options and import base modules
- Conditional imports based on `osConfig.desktop.mode`, `osConfig.machine.type`
- Use descriptive let bindings for complex conditional logic

### File Organization
- System-level: `nixos/` directory
- User-level: `home/` directory  
- Host-specific: `hosts/` directory
- Custom packages: `packages/` directory
- Secrets: agenix, encrypted in the private `mysecrets` input. `hosts/<host>/agenix.nix` imports the agenix module and sets the identity and the user password secret; declare other `age.secrets` in `hosts/<host>/host_secrets.nix`.

**Important**: Stage files with `git add` before testing - Nix flakes only see tracked files!