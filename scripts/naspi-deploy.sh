#!/usr/bin/env bash
set -euo pipefail

# Deploy NixOS configuration to Raspberry Pi remotely using nixos-anywhere
# Usage: ./scripts/naspi-deploy.sh [hostname] [mode]
# Modes: install (fresh install), switch (update existing)

HOSTNAME="${1:-naspi.local}"
MODE="${2:-switch}"

echo "🚀 Deploying NixOS configuration to $HOSTNAME using nixos-anywhere..."

case "$MODE" in
  "install")
    echo "⚠️  FRESH INSTALL MODE - This will wipe the target system!"
    echo "Press Enter to continue or Ctrl+C to abort..."
    read -r
    
    echo "📦 Building and installing NixOS..."
    nix run github:nix-community/nixos-anywhere -- \
      --flake ".#naspi" \
      --build-on-remote \
      "root@$HOSTNAME"
    ;;
  "switch")
    echo "🔄 Updating existing NixOS system..."
    
    # Build the configuration locally first
    echo "📦 Building configuration locally..."
    nom build ".#nixosConfigurations.naspi.config.system.build.toplevel" --out-link result-naspi

    # Copy and activate using nixos-anywhere
    nix run github:nix-community/nixos-anywhere -- \
      --flake ".#naspi" \
      --build-on-remote \
      --no-reboot \
      "noams@$HOSTNAME"
    ;;
  *)
    echo "❌ Invalid mode: $MODE"
    echo "Usage: $0 [hostname] [install|switch]"
    exit 1
    ;;
esac

echo "✅ Deployment completed successfully!"
echo "🔗 SSH access: ssh noams@$HOSTNAME"