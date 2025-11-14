#!/usr/bin/env bash
set -euo pipefail

# Deploy NixOS configuration to Raspberry Pi remotely using nixos-anywhere + disko
# Usage: ./scripts/naspi-deploy.sh [hostname] [mode] [build-host]
# Modes: install (fresh install with disko), switch (update existing)
# Build-host: local (use local cache), remote (build on naspi), or custom ssh host

HOSTNAME="${1:-naspi-nix.local}"
MODE="${2:-switch}"
BUILD_HOST="${3:-remote}"

echo "🚀 Deploying NixOS configuration to $HOSTNAME using nixos-anywhere + disko..."

case "$MODE" in
"install")
  echo "⚠️  FRESH INSTALL MODE with DISKO - This will wipe and repartition the target system!"
  echo "🎯 Disko will create:"
  echo "   • ZFS RAID1 mirror across dual SSDs"
  echo "   • Encrypted ZFS datasets with automatic key file unlock"
  echo "   • Optimized for NAS workloads"
  echo ""

  if [[ $HOSTNAME == *"installer"* ]]; then
    echo "🚀 INSTALLER-BASED DEPLOYMENT DETECTED"
    echo "ℹ️  This will deploy from installer system to target disks using disko"
    echo "   • Installer SD/SSD remains untouched"
    echo "   • Target disks will be wiped and repartitioned"
    echo ""
  fi

  echo "Press Enter to continue with disko install or Ctrl+C to abort..."
  read -r

  # Generate ZFS encryption key
  echo "🔑 Generating ZFS encryption key..."
  ./scripts/generate-zfs-key.sh

  echo "📦 Building and installing NixOS with ZFS encryption..."

  # Determine the correct user based on hostname
  if [[ $HOSTNAME == *"installer"* ]]; then
    TARGET_USER="nixos"
  else
    TARGET_USER="noams"
  fi

  nix run github:nix-community/nixos-anywhere -- \
    --flake .#naspi \
    --disk-encryption-keys /tmp/zfs-rpool-key /tmp/zfs-rpool-key \
    "$TARGET_USER@$HOSTNAME"

  # Clean up local key file
  echo "🧹 Cleaning up local key file..."
  rm -f /tmp/zfs-rpool-key

  echo "✅ ZFS encryption configured with automatic unlock!"
  ;;
"switch")
  echo "🔄 Updating existing NixOS system..."
  echo "ℹ️  This assumes the system was already installed with disko partitioning"

  # Determine build host
  if [[ $BUILD_HOST == "local" ]] || [[ $BUILD_HOST == "localhost" ]]; then
    echo "💾 Building LOCALLY (uses your local cache)"
    echo "🔄 Switching configuration via SSH using nixos-rebuild..."
    nixos-rebuild boot \
      --flake ".#naspi" \
      --target-host "noams@$HOSTNAME" \
      --use-remote-sudo
  elif [[ $BUILD_HOST == "remote" ]]; then
    echo "🏗️  Building REMOTELY on naspi (native build)"
    echo "🔄 Switching configuration via SSH using nixos-rebuild with nom..."
    nixos-rebuild boot \
      --flake ".#naspi" \
      --target-host "noams@$HOSTNAME" \
      --build-host "noams@$HOSTNAME" \
      --use-remote-sudo |& nom
  else
    echo "🏗️  Building on custom host: $BUILD_HOST"
    echo "🔄 Switching configuration via SSH using nixos-rebuild with nom..."
    nixos-rebuild boot \
      --flake ".#naspi" \
      --target-host "noams@$HOSTNAME" \
      --build-host "$BUILD_HOST" \
      --use-remote-sudo |& nom
  fi

  echo "🔄 Configuration built and set as boot default. Reboot required to activate:"
  echo "   ssh noams@$HOSTNAME sudo reboot"
  ;;
"disko-install")
  echo "🔧 DISKO INSTALL MODE - Fresh installation using disko-install"
  echo "⚠️  This will completely wipe and repartition the target disk!"
  echo "Press Enter to continue or Ctrl+C to abort..."
  read -r

  echo "📦 Running disko-install..."
  nix run --add-root ./result-disko-install --indirect github:nix-community/disko#disko-install -- \
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
  echo "   ./scripts/naspi-deploy.sh rpi4-installer install"
  exit 1
  ;;
esac

echo "✅ Deployment completed successfully!"
echo "🔗 SSH access: ssh noams@$HOSTNAME"
