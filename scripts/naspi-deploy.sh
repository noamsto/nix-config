#!/usr/bin/env bash
set -euo pipefail

# Deploy NixOS configuration to Raspberry Pi remotely using nixos-anywhere + disko
# Usage: ./scripts/naspi-deploy.sh [hostname] [mode]
# Modes: install (fresh install with disko), switch (update existing)

HOSTNAME="${1:-naspi-nix.local}"
MODE="${2:-switch}"

echo "🚀 Deploying NixOS configuration to $HOSTNAME using nixos-anywhere + disko..."

case "$MODE" in
"install")
  if [[ "$HOSTNAME" == *"installer"* ]]; then
    echo "🎯 INSTALLER TARGET MODE - Installing to system running from installer"
    echo "ℹ️  Using existing installer partition layout (no repartitioning)"
    echo "   • Uses /dev/disk/by-label/FIRMWARE for /boot/firmware"
    echo "   • Uses /dev/disk/by-label/NIXOS_SD for /"
    echo ""
    
    echo "📦 Building and installing NixOS on installer system..."
    nix run github:nix-community/nixos-anywhere -- \
      --flake ".#naspi-installer-target" \
      --build-on-remote \
      "nixos@$HOSTNAME"
  else
    echo "⚠️  FRESH INSTALL MODE with DISKO - This will wipe and repartition the target system!"
    echo "🎯 Disko will create:"
    echo "   • 512MB vfat firmware partition (/boot/firmware)"
    echo "   • ext4 root filesystem optimized for microSD"
    echo ""
    echo "💡 TIP: For installer-booted systems, use hostname with 'installer' in the name"
    echo ""
    echo "Press Enter to continue with disko install or Ctrl+C to abort..."
    read -r

    echo "📦 Building and installing NixOS with disko partitioning..."
    nix run github:nix-community/nixos-anywhere -- \
      --flake ".#naspi" \
      --build-on-remote \
      "noams@$HOSTNAME"
  fi
  ;;
"switch")
  echo "🔄 Updating existing NixOS system..."
  echo "ℹ️  This assumes the system was already installed with disko partitioning"

  # Build the configuration locally first
  echo "📦 Building configuration locally..."
  nom build ".#nixosConfigurations.naspi.config.system.build.toplevel" --out-link result-naspi

  # Use regular nixos-rebuild for updates (no repartitioning)
  echo "🔄 Switching configuration via SSH..."
  nix run nixpkgs#nixos-rebuild -- switch \
    --flake ".#naspi" \
    --target-host "noams@$HOSTNAME" \
    --build-host "noams@$HOSTNAME"
  ;;
"disko-install")
  echo "🔧 DISKO INSTALL MODE - Fresh installation using disko-install"
  echo "⚠️  This will completely wipe and repartition the target disk!"
  echo "Press Enter to continue or Ctrl+C to abort..."
  read -r

  echo "📦 Running disko-install..."
  nix run github:nix-community/disko#disko-install -- \
    --flake ".#naspi" \
    --disk main /dev/mmcblk0 \
    "nixos@$HOSTNAME"
  ;;
*)
  echo "❌ Invalid mode: $MODE"
  echo "Usage: $0 [hostname] [install|switch|disko-install]"
  echo ""
  echo "Modes:"
  echo "  install       - Fresh install using nixos-anywhere + disko"
  echo "  switch        - Update existing system (no repartitioning)"
  echo "  disko-install - Fresh install using disko-install directly"
  echo ""
  echo "💡 For fresh installs, consider using the rpi4-installer method:"
  echo "   ./scripts/build-rpi4-installer.sh  # Build installer image"
  echo "   # Flash to SD card and boot, then:"
  echo "   ./scripts/naspi-deploy.sh rpi4-installer.local install"
  exit 1
  ;;
esac

echo "✅ Deployment completed successfully!"
echo "🔗 SSH access: ssh noams@$HOSTNAME"
