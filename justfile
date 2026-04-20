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

# Refresh vicinae extension pins (vicinae-extensions flake input + raycast rev/hash)
update-vicinae-extensions:
    home/desktop/hyprland/vicinae/update-sources.fish

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
    @echo "🔧 Maintenance:"
    @echo "just fmt              # Format code"
    @echo "just clean            # Clean build artifacts"
    @echo "just update           # Update flake inputs"
    @echo ""
    @echo "📖 Run 'just --list' for all available commands"
