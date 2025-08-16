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

# Build Raspberry Pi installer image
rpi-build-installer:
    @echo "🏗️  Building RPI4 installer SD card image..."
    @echo "ℹ️   This creates a minimal installer image for deployment"
    nom build ".#rpi4-installer" --out-link result-rpi4-installer
    @echo "✅ Installer image built successfully!"
    @echo "📁 Image location: $(readlink -f result-rpi4-installer)"
    @echo ""
    @echo "📋 Next steps:"
    @echo "1. Flash to SD card: just rpi-flash-installer"
    @echo "2. Boot Pi from SD card"
    @echo "3. Install config: just rpi-install-argon"

# Flash installer image to SD card (interactive)
rpi-flash-installer DEVICE="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -e result-rpi4-installer ]]; then
        echo "❌ No installer image found. Run 'just rpi-build-installer' first."
        exit 1
    fi
    
    IMAGE_PATH=$(readlink -f result-rpi4-installer)
    IMAGE_FILE=$(find "$IMAGE_PATH" -name "*.img*" -o -name "*.raw" | head -1)
    
    if [[ -z "$IMAGE_FILE" ]]; then
        echo "❌ Could not find image file in $IMAGE_PATH"
        exit 1
    fi
    
    if [[ "{{DEVICE}}" == "" ]]; then
        echo "📡 Available block devices:"
        lsblk -d -n -o NAME,SIZE,MODEL | grep -E "(sd[a-z]|mmcblk)" || echo "   No removable devices found"
        echo ""
        echo -n "Enter device (e.g., /dev/sdb): "
        read -r DEVICE
    else
        DEVICE="{{DEVICE}}"
    fi
    
    if [[ ! -e "$DEVICE" ]]; then
        echo "❌ Device $DEVICE does not exist"
        exit 1
    fi
    
    echo "⚠️  WARNING: This will overwrite all data on $DEVICE"
    echo "📁 Source image: $IMAGE_FILE"
    echo "🎯 Target device: $DEVICE"
    echo ""
    echo -n "Continue? [y/N]: "
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted."
        exit 1
    fi
    
    echo "🔄 Flashing image..."
    if [[ "$IMAGE_FILE" == *.zst ]]; then
        sudo zstd -dc "$IMAGE_FILE" | sudo dd of="$DEVICE" bs=4M status=progress
    else
        sudo dd if="$IMAGE_FILE" of="$DEVICE" bs=4M status=progress
    fi
    
    echo "🔄 Syncing..."
    sudo sync
    echo "✅ Image flashed successfully to $DEVICE"

# Build standard RPi4 image
rpi-build-standard:
    @echo "🏗️  Building standard RPI4 SD image..."
    nom build ".#rpi4-standard-image" --out-link result-rpi4-standard

# =============================================================================
# Raspberry Pi Deployment
# =============================================================================

# Install argon-rpi4 using nixos-anywhere + disko (fresh install with partitioning)
rpi-install-argon HOST="rpi4-installer" BUILDERS="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🚀 Installing argon-rpi4 configuration to {{HOST}}..."
    echo "⚠️  FRESH INSTALL with nixos-anywhere + disko"
    echo "🎯 Will completely wipe and repartition target disk:"
    echo "   • 1GB vfat firmware partition (/boot/firmware)"
    echo "   • Btrfs root with subvolumes (@, @home, @nix, @var, @snapshots, @swap)"
    echo "   • Optimized for SSD in Argon ONE v2 case"
    echo ""
    echo "Press Enter to continue or Ctrl+C to abort..."
    read
    echo "📦 Installing with nixos-anywhere..."
    if [[ "{{BUILDERS}}" != "" ]]; then
        echo "🏗️  Using remote builders: {{BUILDERS}}"
        export NIX_BUILD_HOOK=""
        # Configure builders via nix option
        nix run github:nix-community/nixos-anywhere -- \
            --flake .#argon-rpi4 \
            --build-on remote \
            --option builders "{{BUILDERS}}" \
            --option builders-use-substitutes true \
            nixos@{{HOST}}
    else
        nix run github:nix-community/nixos-anywhere -- \
            --flake .#argon-rpi4 \
            --option max-jobs 1 \
            --option cores 0 \
            nixos@{{HOST}}
    fi
    echo "✅ Installation complete! Remove SD card and reboot to boot from target disk."

# Install argon-rpi4 with mixed local+remote building (RECOMMENDED)
rpi-install-argon-mixed HOST="rpi4-installer":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🚀 Installing argon-rpi4 with mixed building (local AMD + remote aarch64)..."
    echo "⚠️  FRESH INSTALL with nixos-anywhere + disko"
    echo "🎯 Will completely wipe and repartition target disk"
    echo "🏗️  Build strategy: Local AMD (x86_64) + Remote Pi (aarch64)"
    echo ""
    echo "Press Enter to continue or Ctrl+C to abort..."
    read
    echo "📦 Installing with distributed building..."
    # Configure mixed building: local AMD + remote aarch64
    export NIX_CONFIG="builders = ssh://nixos@{{HOST}} aarch64-linux - 2 2 big-parallel"
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#argon-rpi4 \
        --option max-jobs 4 \
        --option cores 4 \
        --option builders-use-substitutes true \
        nixos@{{HOST}}
    echo "✅ Installation complete! Remove SD card and reboot to boot from target disk."

# Deploy configuration update to existing argon-rpi4 system  
rpi-deploy-argon HOST="argon-rpi4.local" BUILDERS="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔄 Deploying configuration update to {{HOST}}..."
    echo "ℹ️  Updates existing system (no repartitioning)"
    
    BUILDERS_FLAG=""
    if [[ "{{BUILDERS}}" != "" ]]; then
        echo "🏗️  Using remote builders: {{BUILDERS}}"
        BUILDERS_FLAG="--builders {{BUILDERS}}"
    fi
    
    nixos-rebuild boot \
    --flake ".#argon-rpi4" \
    --target-host "noams@{{HOST}}" \
    --build-host "noams@{{HOST}}" \
    $BUILDERS_FLAG \
    --sudo | nom
    echo "🔄 Configuration updated. Reboot to activate: just rpi-reboot {{HOST}}"

# Deploy argon-rpi4 update with mixed local+remote building (RECOMMENDED)
rpi-deploy-argon-mixed HOST="argon-rpi4.local":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔄 Deploying update with mixed building (local AMD + remote aarch64)..."
    echo "ℹ️  Updates existing system (no repartitioning)"
    echo "🏗️  Build strategy: Local AMD (x86_64) + Remote Pi (aarch64)"
    
    # Configure mixed building: local AMD + remote aarch64
    export NIX_CONFIG="builders = ssh://noams@{{HOST}} aarch64-linux - 2 2 big-parallel"
    nixos-rebuild boot \
    --flake ".#argon-rpi4" \
    --target-host "noams@{{HOST}}" \
    --build-host "localhost" \
    --option max-jobs 4 \
    --option cores 4 \
    --option builders-use-substitutes true \
    --sudo | nom
    echo "🔄 Configuration updated. Reboot to activate: just rpi-reboot {{HOST}}"

# =============================================================================
# Generic RPi Management
# =============================================================================

# Install any Pi configuration using nixos-anywhere + disko
rpi-install CONFIG HOST BUILDERS="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🚀 Installing {{CONFIG}} to {{HOST}} using nixos-anywhere + disko..."
    echo "⚠️  Will completely wipe and repartition target disk!"
    echo "Press Enter to continue or Ctrl+C to abort..."
    read
    BUILDERS_FLAG=""
    if [[ "{{BUILDERS}}" != "" ]]; then
        echo "🏗️  Using remote builders: {{BUILDERS}}"
        BUILDERS_FLAG="--builders {{BUILDERS}}"
    fi
    nix run github:nix-community/nixos-anywhere -- \
        --flake ".#{{CONFIG}}" \
        --build-on remote \
        $BUILDERS_FLAG \
        nixos@{{HOST}}

# Deploy configuration update to existing Pi system
rpi-deploy CONFIG HOST BUILDERS="":
    #!/usr/bin/env bash
    set -euo pipefail
    echo "🔄 Deploying {{CONFIG}} update to {{HOST}}..."
    
    BUILDERS_FLAG=""
    if [[ "{{BUILDERS}}" != "" ]]; then
        echo "🏗️  Using remote builders: {{BUILDERS}}"
        BUILDERS_FLAG="--builders {{BUILDERS}}"
    fi
    
    nixos-rebuild boot \
    --flake ".#{{CONFIG}}" \
    --target-host "noams@{{HOST}}" \
    --build-host "noams@{{HOST}}" \
    $BUILDERS_FLAG \
    --sudo | nom

# Reboot Raspberry Pi
rpi-reboot HOST USER="nixos":
    @echo "🔄 Rebooting {{HOST}}..."
    ssh {{USER}}@{{HOST}} sudo reboot || echo "✅ Reboot initiated"

# Check Raspberry Pi status
rpi-status HOST USER="nixos":
    @echo "📊 Status of {{HOST}}:"
    ssh {{USER}}@{{HOST}} "echo '🖥️  Hostname:' \$(hostname) && echo '⚡ Uptime:' \$(uptime -p) && echo '💾 Memory:' && free -h | head -2 && echo '💿 Disk:' && df -h | head -2"

# SSH into Raspberry Pi
rpi-ssh HOST USER="nixos":
    ssh {{USER}}@{{HOST}}

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

# Quick install to argon-rpi4 (most common use case)
install-argon: check-staged
    just rpi-install-argon

# =============================================================================
# Help & Documentation
# =============================================================================

# Show detailed help for Raspberry Pi commands
help-rpi:
    @echo "🍓 Raspberry Pi Deployment Guide"
    @echo "=================================="
    @echo ""
    @echo "📋 Workflow: SD Installer → Install (nixos-anywhere + disko) → Deploy (config updates)"
    @echo ""
    @echo "🏗️  Initial Installation:"
    @echo "1. just rpi-build-installer     # Build installer SD image"
    @echo "2. just rpi-flash-installer     # Flash to SD card"
    @echo "3. Boot Pi from SD card"
    @echo "4. just rpi-install-argon       # Fresh install with disko (wipes target disk)"
    @echo "5. Remove SD card and reboot    # System boots from target disk"
    @echo ""
    @echo "🔄 Configuration Updates:"
    @echo "just rpi-deploy-argon argon-rpi4.local                                 # Update existing system"
    @echo "just rpi-deploy-argon argon-rpi4.local 'ssh://noams@naspi.local aarch64-linux - 4 2 big-parallel'  # With remote builder"
    @echo ""
    @echo "🏗️  Builder Examples:"
    @echo "Single:   BUILDERS='ssh://noams@naspi.local aarch64-linux - 4 2 big-parallel'"
    @echo "Multiple: BUILDERS='ssh://noams@naspi.local aarch64-linux - 4 2 big-parallel ssh://noams@argon-rpi4.local aarch64-linux - 4 2 big-parallel'"
    @echo ""
    @echo "🛠️  Management:"
    @echo "just rpi-status HOST [USER]     # Check system status"
    @echo "just rpi-ssh HOST [USER]        # SSH into system"
    @echo "just rpi-reboot HOST [USER]     # Reboot system"
    @echo ""
    @echo "📝 Key concepts:"
    @echo "• install = nixos-anywhere + disko (wipes disk, creates partitions)"
    @echo "• deploy  = nixos-rebuild (updates existing configuration)"
    @echo "• SD card is only used for installation, system boots from target disk"

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
    @echo "just deploy-argon     # Quick deploy to argon-rpi4"
    @echo ""
    @echo "🔧 Maintenance:"
    @echo "just fmt              # Format code"
    @echo "just clean            # Clean build artifacts"
    @echo "just update           # Update flake inputs"
    @echo ""
    @echo "📖 Run 'just --list' for all available commands"
