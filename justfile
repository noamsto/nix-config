# NixOS Configuration Management
# Improved deployment and management commands

# Default recipe - show available commands
default:
    @just --list

# =============================================================================
# Development & Validation
# =============================================================================

# Format all code using alejandra and other formatters
fmt:
    nix fmt

# Check flake configuration
check:
    nix flake check

# Update all flake inputs
update:
    nix flake update

# Enter development shell
dev:
    nix develop

# =============================================================================
# Local System Management
# =============================================================================

# Build NixOS system (dry-run)
build HOST="$(hostname)":
    nh os build .#{{HOST}}

# Switch NixOS system configuration
switch HOST="$(hostname)":
    nh os switch .#{{HOST}}

# Switch NixOS system configuration with staged changes only
switch-staged HOST="$(hostname)":
    nh os switch -S .#{{HOST}}

# Boot NixOS configuration (apply on next reboot)
boot HOST="$(hostname)":
    nh os boot .#{{HOST}}

# Build specific derivation with nom output
build-with-nom DERIVATION:
    nom build ".#{{DERIVATION}}"

# =============================================================================
# Home Manager
# =============================================================================

# Switch Home Manager configuration
home-switch CONFIG="noams@$(hostname)":
    nix run home-manager/master -- switch --flake .#{{CONFIG}}

# Build Home Manager configuration
home-build CONFIG="noams@$(hostname)":
    nom build .#homeConfigurations.{{CONFIG}}.activationPackage

# =============================================================================
# Raspberry Pi Management
# =============================================================================
# All RPi operations now use the unified CLI: scripts/rpi/rpi
# Run './scripts/rpi/rpi help' for detailed usage information

# List all available Raspberry Pi configurations
rpi-list:
    ./scripts/rpi/rpi list

# Build Raspberry Pi installer image
rpi-build-installer:
    @echo "🏗️  Building RPI4 installer SD card image..."
    ./scripts/rpi/rpi rpi4-installer build

# Deploy configuration update to naspi
naspi-deploy STRATEGY="auto":
    @echo "🔄 Deploying configuration update to naspi..."
    ./scripts/rpi/rpi naspi deploy {{STRATEGY}}

# Quick naspi deploy (alias)
naspi:
    @just naspi-deploy

# Deploy naspi over Tailscale (when not on local network)
naspi-deploy-tailscale:
    @echo "🔄 Deploying configuration update to naspi via Tailscale..."
    nixos-rebuild switch --flake ".#naspi" --target-host noams@naspi --use-remote-sudo --accept-flake-config |& nom

# Fresh installation of naspi (DESTRUCTIVE!)
naspi-install:
    @echo "⚠️  This will WIPE and REPARTITION naspi!"
    @echo "⚠️  Fresh installation with ZFS RAID1 on dual SSDs"
    @echo ""
    ./scripts/rpi/rpi naspi install

# Deploy configuration update to argon-rpi4
argon-deploy STRATEGY="auto":
    @echo "🔄 Deploying configuration update to argon-rpi4..."
    ./scripts/rpi/rpi argon-rpi4 deploy {{STRATEGY}}

# Fresh installation of argon-rpi4 (DESTRUCTIVE!)
argon-install:
    @echo "⚠️  This will WIPE and REPARTITION argon-rpi4!"
    @echo "⚠️  Fresh installation with Btrfs on external SSD"
    @echo ""
    ./scripts/rpi/rpi argon-rpi4 install

# SSH into any Raspberry Pi
rpi-ssh HOST USER="noams":
    ssh {{USER}}@{{HOST}}.local

# Reboot any Raspberry Pi
rpi-reboot HOST USER="noams":
    @echo "🔄 Rebooting {{HOST}}..."
    ssh {{USER}}@{{HOST}}.local sudo reboot || echo "✅ Reboot initiated"

# Check Raspberry Pi status
rpi-status HOST USER="noams":
    @echo "📊 Status of {{HOST}}:"
    ssh {{USER}}@{{HOST}}.local "echo '🖥️  Hostname:' \$(hostname) && echo '⚡ Uptime:' \$(uptime -p) && echo '💾 Memory:' && free -h | head -2 && echo '💿 Disk:' && df -h | head -2"

# =============================================================================
# Secret Management
# =============================================================================

# Edit encrypted secret
secret-edit SECRET:
    agenix -e secrets/{{SECRET}}.age

# Rekey all secrets
secret-rekey:
    agenix -r

# List available secrets
secret-list:
    @find secrets -name "*.age" -exec basename {} .age \;

# =============================================================================
# Utility Commands
# =============================================================================

# Show system information
info:
    @echo "🖥️  System Information:"
    @echo "Hostname: $(hostname)"
    @echo "NixOS Version: $(nixos-version)"
    @echo "Architecture: $(uname -m)"
    @echo ""
    @echo "🔧 Available NixOS Configurations:"
    @nix flake show --json | jq -r '.nixosConfigurations | keys[]' | sort
    @echo ""
    @echo "🏠 Available Home Manager Configurations:"
    @nix flake show --json | jq -r '.homeConfigurations | keys[]' 2>/dev/null | sort || echo "None found"

# Clean up build artifacts
clean:
    @echo "🧹 Cleaning up build artifacts..."
    rm -rf result*
    nix-collect-garbage

# Clean up aggressively (including generations)
clean-all:
    @echo "🧹 Aggressive cleanup (including generations)..."
    rm -rf result*
    sudo nix-collect-garbage -d
    nix-collect-garbage -d

# Show flake inputs and their status
status:
    @echo "📦 Flake Input Status:"
    nix flake metadata

# Check if any staged git changes exist
check-staged:
    #!/usr/bin/env bash
    if ! git diff --cached --quiet; then
        echo "✅ Staged changes detected - builds will include them"
        echo "📝 Staged files:"
        git diff --cached --name-only | sed 's/^/  /'
    else
        echo "ℹ️  No staged changes - builds will use committed files only"
        echo "💡 Tip: Use 'git add <files>' to stage changes before building"
    fi

# =============================================================================
# Help & Documentation
# =============================================================================

# Show detailed help for Raspberry Pi commands
help-rpi:
    @echo "🍓 Raspberry Pi Deployment Guide"
    @echo "=================================="
    @echo ""
    @echo "📋 Workflow: SD Installer → Install → Deploy (config updates)"
    @echo ""
    @echo "🏗️  Initial Installation:"
    @echo "1. just rpi-build-installer     # Build installer SD image"
    @echo "2. Flash to SD card (use Raspberry Pi Imager or dd)"
    @echo "3. Boot Pi from SD card"
    @echo "4a. just naspi-install          # Fresh install with ZFS RAID1"
    @echo "4b. just argon-install          # Fresh install with Btrfs on SSD"
    @echo "5. Remove SD card and reboot    # System boots from target disk"
    @echo ""
    @echo "🔄 Configuration Updates:"
    @echo "just naspi-deploy               # Update naspi (auto build strategy)"
    @echo "just naspi-deploy local         # Update naspi (build locally)"
    @echo "just naspi-deploy remote        # Update naspi (build on target)"
    @echo "just argon-deploy               # Update argon-rpi4"
    @echo ""
    @echo "🛠️  Management:"
    @echo "just rpi-list                   # List all configurations"
    @echo "just rpi-status naspi           # Check system status"
    @echo "just rpi-ssh naspi              # SSH into system"
    @echo "just rpi-reboot naspi           # Reboot system"
    @echo ""
    @echo "🔧 Direct CLI Usage:"
    @echo "./scripts/rpi/rpi help          # Show full CLI help"
    @echo "./scripts/rpi/rpi list          # List configurations"
    @echo "./scripts/rpi/rpi naspi deploy  # Deploy to naspi"
    @echo ""
    @echo "📝 Key concepts:"
    @echo "• install = nixos-anywhere + disko (wipes disk, creates partitions)"
    @echo "• deploy  = nixos-rebuild (updates existing configuration)"
    @echo "• Build strategies: auto (use host default), local, remote"

# Show general help
help:
    @echo "🔧 NixOS Configuration Management"
    @echo "================================="
    @echo ""
    @echo "📚 Quick Start:"
    @echo "just dev              # Enter development shell"
    @echo "just check            # Validate configuration"
    @echo "just switch           # Apply configuration"
    @echo ""
    @echo "🍓 Raspberry Pi:"
    @echo "just help-rpi         # Detailed Pi deployment guide"
    @echo "just rpi-list         # List all Pi configurations"
    @echo "just naspi-deploy     # Deploy to naspi"
    @echo "just argon-deploy     # Deploy to argon-rpi4"
    @echo ""
    @echo "🔧 Maintenance:"
    @echo "just fmt              # Format code"
    @echo "just clean            # Clean build artifacts"
    @echo "just update           # Update flake inputs"
    @echo ""
    @echo "📖 Run 'just --list' for all available commands"
