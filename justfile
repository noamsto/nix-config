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
    @just restart-noctalia

# Switch NixOS system configuration with staged changes only
switch-staged HOST="$(hostname)":
    nh os switch -S .#{{HOST}}
    @just restart-noctalia

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
    @just restart-noctalia

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

# Restart noctalia-shell after a rebuild.
#
# `nh os switch` flips /run/current-system, leaving the running quickshell with
# stale references (icon themes, fontconfig, /etc/os-release). Symptom: the
# Nix distro logo on ControlCenter (useDistroLogo=true) and other
# dynamically-resolved icons disappear until restart. Upstream acknowledged
# this in the (now-removed) systemd integration docs and deprecated that path
# rather than fix it:
#   https://docs.noctalia.dev/getting-started/nixos/#running-the-shell
#
# Wired here rather than a Nix-level hook: NixOS activation runs as root with
# no graphical session env, and HM activation misses `nh os switch` entirely.
restart-noctalia:
    #!/usr/bin/env bash
    set -euo pipefail
    # Match by the binary path the noctalia-shell wrapper exec's into.
    # The wrapper drops its own name on exec, so the cmdline ends up as just
    # `…/bin/quickshell` with no `noctalia-shell` token to match against.
    pat='bin/quickshell$'
    if ! pgrep --quiet -f "$pat"; then
        exit 0
    fi
    echo "♻️  Restarting noctalia-shell to refresh runtime state..."
    # setsid -f detaches the new process from just's lifetime
    pkill -f "$pat" 2>/dev/null || true
    setsid -f noctalia-shell </dev/null >/dev/null 2>&1 || true

# Allow charging to 100% until next reboot / `sudo systemctl restart tlp`
# (g5 only — fresh-battery fuel-gauge calibration).
battery-calibrate:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$(hostname)" != "thinkpad-p14s-g5" ]; then
        echo "❌ battery-calibrate is gated to thinkpad-p14s-g5 (current: $(hostname))" >&2
        exit 1
    fi
    bat=/sys/class/power_supply/BAT0
    echo "🔋 Current: $(cat $bat/capacity)% — start=$(cat $bat/charge_start_threshold) stop=$(cat $bat/charge_stop_threshold)"
    echo "→ Raising stop threshold to 100 (runtime only; TLP restores 60/80 on reboot or 'sudo systemctl restart tlp')"
    echo 100 | sudo tee $bat/charge_stop_threshold > /dev/null
    echo "✅ stop=$(cat $bat/charge_stop_threshold)"
    echo ""
    echo "Calibration cycle:"
    echo "  1. Charge to 100% (plugged in)."
    echo "  2. Unplug, use until battery hits ~5% and the laptop warns / suspends."
    echo "  3. Plug in, charge back to 100%."
    echo "  4. Restore thresholds: sudo systemctl restart tlp"

# Rebind hid-multitouch to recover a touchpad that has gone silent (common on AMD ThinkPads post-suspend)
touchpad-rebind:
    #!/usr/bin/env bash
    set -euo pipefail
    drv=/sys/bus/hid/drivers/hid-multitouch
    id=$(find "$drv" -mindepth 1 -maxdepth 1 -regextype posix-extended \
        -regex '.*/[0-9A-F]{4}:[0-9A-F]{4}:[0-9A-F]{4}\.[0-9A-F]+' -printf '%f\n' | head -n1)
    if [ -z "$id" ]; then
        echo "❌ No HID device bound to hid-multitouch" >&2
        exit 1
    fi
    echo "♻️  Rebinding $id on hid-multitouch..."
    sudo sh -c "echo '$id' > '$drv/unbind' && sleep 1 && echo '$id' > '$drv/bind'"
    echo "✅ Done. Touch the touchpad to verify."

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
