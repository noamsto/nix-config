# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **NixOS Configuration Repository** using Nix flakes that manages both NixOS system configurations and Home Manager user configurations. It's a personal dotfiles repository with support for multiple hosts (laptops, servers, Raspberry Pi) and desktop environments (KDE Plasma, Hyprland).

## ToonFormat Preference

**IMPORTANT**: When outputting structured data (especially arrays/tables), prefer **ToonFormat** over JSON for token efficiency.

ToonFormat provides 30-60% token savings compared to JSON. Use it for configuration summaries, package lists, file structures, etc.

**Format example:**

```toon
hosts[3]{name,type,profile,desktop}:
 thinkpad-p14s,laptop,personal,hyprland
 thinkpad-p14s-g5,laptop,work,hyprland
 naspi,server,personal,none
```

**When to use:**

- Package lists, configuration summaries, file trees
- Any tabular data or repeated structures
- Data-heavy responses

Only use JSON when specifically required or when deeply nested structures are needed.

## Development Commands

### Quick Reference with Just

This repository includes a comprehensive `justfile` with convenient command wrappers. Use `just --list` to see all available commands.

**Most common commands:**

```bash
just --list           # Show all available commands
just switch           # Apply NixOS configuration
just check            # Validate flake
just fmt              # Format all code
just update           # Update flake inputs
just clean            # Clean build artifacts

# Raspberry Pi commands
just help-rpi         # Detailed Pi deployment guide
just rpi-list         # List all Pi configurations
just naspi-deploy     # Deploy to naspi
just naspi-install    # Fresh install to naspi (DESTRUCTIVE!)
just argon-deploy     # Deploy to argon-rpi4
```

### Core Development

```bash
nix develop              # Enter development shell with all tools
nix fmt                  # Format all code using alejandra and other formatters
nix flake check          # Validate flake configuration
nix flake update         # Update all inputs (equivalent to updating flake.lock)
```

### System Rebuilds

```bash
# Local system rebuild (full NixOS + Home Manager)
sudo nixos-rebuild switch --flake .#<hostname>
nh os switch .           # Using nh helper (preferred)
nh os switch -S          # With --show-trace for debugging

# Home Manager only - Hybrid approach for faster development
nh home switch .         # Fast user-only rebuild (auto-detects username@hostname)
home-manager switch --flake .#<config>  # Manual standalone rebuild with specific config

# Raspberry Pi deployment
# All RPi operations use unified CLI: ./scripts/rpi/rpi
./scripts/rpi/rpi list                    # List all available configurations
./scripts/rpi/rpi help                    # Show detailed usage help

# Quick commands via justfile (recommended)
just naspi                                # Deploy to naspi (fastest)
just naspi-deploy                         # Deploy with auto build strategy
just naspi-deploy local                   # Deploy with local build
just naspi-deploy remote                  # Deploy with remote build
just rpi-build-installer                  # Build minimal installer image

# Direct CLI usage
./scripts/rpi/rpi naspi deploy            # Update existing system (auto strategy)
./scripts/rpi/rpi naspi deploy local      # Deploy with local build
./scripts/rpi/rpi naspi deploy remote     # Deploy with remote build
./scripts/rpi/rpi naspi install           # Fresh install with disko (DESTRUCTIVE!)
./scripts/rpi/rpi rpi4-installer build    # Build installer image
./scripts/rpi/rpi argon-rpi4 deploy       # Deploy to argon-rpi4

# Build strategies:
# - auto: Use host's default strategy (recommended)
# - local: Build on development machine (uses local cache, cross-compile)
# - remote: Build on target Pi (slower, but native aarch64, no overheating)
```

### Available Hosts

**NixOS Systems:**

- `thinkpad-p14s` - Main laptop (personal, Hyprland)
- `thinkpad-p14s-g5` - Work laptop (work profile, Hyprland)
- `naspi` - Raspberry Pi 4 with ZFS RAID1 on dual SSDs
- `argon-rpi4` - Raspberry Pi 4 with Argon V2 case and external SSD boot
- `rpi4-installer` - Minimal RPi4 installer image
- `rpi4-standard` - Standard RPi4 configuration using NixOS wiki approach

**Standalone Home Manager (for development):**

- `noams@thinkpad-p14s` - Auto-detected by nh (personal)
- `noams@thinkpad-p14s-g5` - Auto-detected by nh (work)
- `noams@naspi` - Raspberry Pi Home Manager
- `noams-kde` - KDE variant for testing
- `noams-hyprland` - Legacy name for personal profile
- `noams-hyprland-work` - Legacy name for work profile

### Hybrid Home Manager Approach

This repository uses **both** Home Manager as a NixOS module (production) AND standalone Home Manager (development):

**Production/Full Rebuilds:**

- Uses Home Manager as NixOS module (imported in each host's configuration)
- Command: `nh os switch .` or `nh os switch -S` (with --show-trace)
- Updates both system and user configurations together
- Takes 2-3 minutes, includes full validation

**Development/Fast Rebuilds:**

- Uses standalone Home Manager configurations defined in `flake-modules/home-manager.nix`
- Command: `nh home switch .` (auto-detects username@hostname)
- Updates only user configuration (~30 seconds)
- Perfect for testing dotfile changes, themes, applications

**How it works:**

- Standalone configs use `lib/host-configs.nix` to share the same options (profile, desktop.mode, etc.)
- `nh home switch` auto-selects config based on `username@hostname` pattern
- Both approaches use the same modules from `home/`, ensuring consistency

**When to use each:**

- Use `nh home switch .` for quick iteration on user configurations
- Use `nh os switch .` for system changes or final validation before commits

### Development Tools Available in Shell

When you run `nix develop`, you get:

- `agenix` - Secret management and editing
- `nh` - NixOS helper for easier rebuilds
- `nixos-anywhere` - Remote NixOS deployment
- `nom` (nix-output-monitor) - Better build output
- `just` - Command runner (see `just --list`)
- `prettier` - Code formatting for non-Nix files
- `statix` - Nix linter
- `jq` - JSON processing
- `tokei` - Code statistics
- Pre-commit hooks (alejandra, prettier, shellcheck)

**Shell aliases** (when using fish):

- `nix-agent` - Helper for agent-related operations
- `nbuild` - Alias for `nom build`
- `dev-stats` - Show project statistics (uses tokei and git)

### Binary Caches

The flake is pre-configured with multiple binary caches for faster builds:

- `cache.nixos.org` - Official NixOS cache
- `hyprland.cachix.org` - Hyprland compositor
- `nixpkgs-unfree.cachix.org` - Unfree packages
- `nix-community.cachix.org` - Community packages
- `nixos-raspberrypi.cachix.org` - Raspberry Pi builds
- `claude-code.cachix.org` - Claude Code packages

These are automatically used and significantly speed up builds. No manual configuration needed.

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
│   ├── host-configs.nix           # Shared host settings (used by both NixOS and HM)
│   └── overlays.nix               # Package overlays
├── packages/                      # Custom package definitions
└── justfile                       # Command runner recipes
```

**Key benefits:**

- Each flake module is self-contained and focused
- Outputs are defined close to their implementation
- Easy to add new systems or outputs without modifying flake.nix
- `perSystem` configuration in development.nix handles per-architecture setup

### Raspberry Pi Configurations

The repository provides **multiple NixOS configurations for Raspberry Pi**:

1. **`naspi`** - Production NAS with ZFS RAID1
   - Dual SSD setup with ZFS mirroring
   - Uses disko for automatic partitioning
   - Command: `just install-naspi` or `./scripts/naspi-deploy.sh naspi.local install`
   - **IMPORTANT**: Boots from USB SSD, not SD card - Remove SD card from slot to avoid boot interference

2. **`argon-rpi4`** - Raspberry Pi with Argon V2 case
   - External SSD boot configuration
   - Uses disko for disk management
   - Optimized for Argon case features (fan control, power button)
   - Command: `just install-argon` or `just rpi-install-argon`

3. **`rpi4-installer`** - Minimal installer image
   - Lightweight bootable SD image for initial deployment
   - Build: `just rpi-build-installer` or `./scripts/build-rpi4-installer.sh`
   - Deploy: `./scripts/naspi-deploy.sh rpi4-installer install`

### NasPi Boot Troubleshooting

If naspi fails to boot or shows these errors:

- "Card did not respond to voltage select! : -110"
- "Timeout waiting for cmd & data inhibit"
- "mmc1 busy timeout"
- "[FAILED] Failed to start Emergency SSH"

**Root Cause**: SD card in slot interfering with USB/SSD boot

**Solution**:

1. Remove SD card from Raspberry Pi slot
2. Update EEPROM boot order: `sudo rpi-eeprom-config --edit` → Set `BOOT_ORDER=0x4f6` (USB priority)
3. Check boot verification: `sudo journalctl -u naspi-boot-verify.service`

See `hosts/naspi/README.md` for comprehensive troubleshooting, ZFS management, and service configuration.

### ThinkPad Configuration

The repository has specialized support for ThinkPad P14s laptops (Gen 4 and Gen 5):

**Hardware Modules** (`nixos/hardware/`):

- `thinkpad-common.nix` - Shared boot settings, kernel modules, AMD microcode
- `thinkfan.nix` - Generation-aware fan control with custom options

**Thinkfan Configuration:**

```nix
# In hosts/<hostname>/default.nix
hardware.thinkpad.thinkfan = {
  enable = true;           # Enable thinkfan service
  generation = "gen5";     # "gen4" or "gen5" - sets sensor paths and fan curves
};
```

**Laptop Features** (`nixos/laptop/`):

- `pam-lid-check.nix` - Skips fingerprint auth when lid is closed (clamshell mode)
- `suspend-handling.nix` - Suppresses spurious AC wakes, clears phantom monitors

### Secure Boot & TPM (thinkpad-p14s-g5)

The Gen 5 ThinkPad uses **Lanzaboote** for Secure Boot and **TPM2** for LUKS auto-unlock:

**Current Configuration:**

```nix
# Secure Boot with Lanzaboote (auto key generation/enrollment)
boot.lanzaboote = {
  enable = true;
  pkiBundle = "/etc/secureboot";
  autoGenerateKeys.enable = true;
  autoEnrollKeys.enable = true;
};

# TPM2-based LUKS auto-unlock
boot.initrd.luks.devices.root.crypttabExtraOpts = ["tpm2-device=auto"];
```

**Initial Setup (one-time):**

1. First boot enrolls Secure Boot keys automatically
2. After successful boot, enroll TPM for LUKS:
   ```bash
   sudo systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p2
   ```
3. Verify with: `sudo systemd-cryptenroll /dev/nvme0n1p2`

**Troubleshooting:**

- If TPM unlock fails, system falls back to password prompt
- Check TPM status: `sudo tpm2_getcap properties-fixed`
- Re-enroll after BIOS updates: `sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto /dev/nvme0n1p2`
- Secure Boot status: `sbctl status`

**Tools available:**

- `sbctl` - Secure Boot key management
- `tpm2-tools` - TPM utilities

### Configuration System

The repository uses a **modular architecture** with conditional imports based on configuration options:

**Core Configuration Files:**

- **`options.nix`** - Defines custom options that control what gets imported:
  - `desktop.mode`: "none" | "kde" | "hyprland"
  - `machine.type`: "server" | "desktop" | "laptop"
  - `profile`: "personal" | "work"
  - `username`, `email`, `hostname` - Per-host identity settings

- **`lib/host-configs.nix`** - Shared configuration source of truth:
  - Single file defining settings for all hosts (thinkpad-p14s, thinkpad-p14s-g5, naspi)
  - Used by **both** NixOS systems and standalone Home Manager configs
  - Ensures consistency between full rebuilds and HM-only rebuilds
  - Example:
    ```nix
    thinkpad-p14s = {
      username = "noams";
      email = "noamstolero@gmail.com";
      hostname = "thinkpad-p14s";
      desktop.mode = "hyprland";
      machine.type = "laptop";
      profile = "personal";
    };
    ```

**How Configuration Flows:**

1. **NixOS systems** (`hosts/*/default.nix`) import host config and set options
2. **Standalone HM configs** (`flake-modules/home-manager.nix`) pass host config as `osConfig`
3. **Modules** check `osConfig` options to conditionally enable features
4. **Package lists** use `lib.optionals` to add packages based on profile/desktop mode

### Directory Structure

```
├── flake.nix              # Main flake definition
├── justfile               # Command runner recipes
├── options.nix            # Custom configuration options
├── nixos/                 # System-level NixOS modules
│   ├── core/              # Boot, locale, networking, users, pc.nix
│   ├── desktop/           # Desktop environments (KDE, SDDM)
│   ├── hardware/          # Hardware-specific modules
│   │   ├── thinkpad-common.nix  # Shared ThinkPad settings
│   │   └── thinkfan.nix         # Generation-aware fan control
│   ├── laptop/            # Laptop-specific features
│   │   ├── pam-lid-check.nix    # Skip fprintd when lid closed
│   │   └── suspend-handling.nix # AC wake suppression, phantom monitors
│   └── virtualization/    # Containers, VMs
├── home/                  # User-level Home Manager modules
│   ├── desktop/           # Desktop apps, window managers, themes
│   ├── terminal/          # Shell, terminal multiplexer
│   ├── nvim/              # Neovim configuration
│   ├── git/               # Git and related tools
│   └── work/              # Work profile packages (slack, AWS, etc.)
├── hosts/                 # Per-host configurations
│   └── naspi/             # NasPi configuration
│       └── README.md      # Detailed NasPi documentation
├── scripts/               # Deployment and management scripts
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

5. **Multi-architecture Support**: x86_64-linux and aarch64-linux (for Raspberry Pi)
   - Different nixpkgs instances for each architecture
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

## Testing Changes

**CRITICAL**: Nix flakes only see git-tracked files. Always stage changes before testing!

```bash
# 1. Stage your changes first (unstaged files are invisible to nix!)
git add <files>

# Or check if you have staged changes:
just check-staged

# 2. Validate flake structure
nix flake check              # Or: just check

# 3. Test builds without switching
nh os build .                    # Test NixOS build
nh home build .                  # Test Home Manager build
nom build .#nixosConfigurations.<hostname>.config.system.build.toplevel
nom build .#homeConfigurations.<config>.activationPackage

# 4. Apply changes
nh os switch .                   # Full system rebuild (or: just switch)
nh home switch .                 # Home Manager only (faster)
```

**Common gotcha**: If you see "file not found" errors, check if you forgot to `git add` new files!

## Common Patterns

When adding new features, follow these patterns:

- **Check `osConfig.profile`** when adding work-specific configurations
  - Example: `++ lib.optionals (osConfig.profile == "work") work-packages`

- **Use conditional imports** based on `desktop.mode` for desktop environment features
  - Example: `++ lib.optionals (osConfig.desktop.mode == "hyprland") [./hyprland]`

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

## Known Issues & Failed Experiments

### Noctalia Google Calendar Integration (Not Working)

**Attempted:** 2025-12-29

**Goal:** Show Google Calendar events in Noctalia's clock popup via evolution-data-server.

**What Noctalia docs say:** Add to NixOS config:
```nix
services.gnome.evolution-data-server.enable = true;
environment.systemPackages = [ (python3.withPackages (p: [ p.pygobject3 ])) ];
environment.sessionVariables.GI_TYPELIB_PATH = lib.makeSearchPath "lib/girepository-1.0" (with pkgs; [
  evolution-data-server libical glib.out libsoup_3 json-glib gobject-introspection
]);
```

**Problem:** Google OAuth callback doesn't work on NixOS + Hyprland:
1. `gnome-control-center` refuses to run outside GNOME (workaround: `XDG_CURRENT_DESKTOP=GNOME`)
2. OAuth opens in Firefox, but callback URL (`com.googleusercontent.apps.XXX://`) doesn't return to GOA
3. Even with `WEBKIT_FORCE_SANDBOX=0`, the custom URL scheme handler fails
4. This is a NixOS + Hyprland + GNOME Online Accounts issue, not Noctalia-specific

**Alternatives not tried:**
- Evolution (has embedded OAuth webview)
- ICS subscription (read-only, no OAuth)
- Manual evolution-data-server configuration

**Reference:** Noctalia issue #682 confirms the NixOS config is correct; the OAuth callback is the blocker.

## Additional Resources

- Run `just help` or `just help-rpi` for detailed command usage
- See `hosts/naspi/README.md` for comprehensive NasPi documentation
- Use `just --list` to discover all available commands
