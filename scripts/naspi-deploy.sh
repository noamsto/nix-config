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
  if [[ $HOSTNAME == *"installer"* ]]; then
    echo "🎯 INSTALLER TARGET MODE - Installing to system running from installer"
    echo "ℹ️  Using existing installer partition layout (no repartitioning)"
    echo "   • Uses /dev/disk/by-label/FIRMWARE for /boot/firmware"
    echo "   • Uses /dev/disk/by-label/NIXOS_SD for /"
    echo ""

    echo "📦 Building and installing NixOS on installer system..."
    echo "ℹ️  Using nixos-rebuild with nom (not nixos-anywhere) since no disk partitioning needed"
    nixos-rebuild boot \
      --flake ".#naspi-installer-target" \
      --target-host "nixos@$HOSTNAME" \
      --build-host "nixos@$HOSTNAME" \
      --use-remote-sudo |& nom

    echo "🔄 Configuration built and set as boot default. Reboot required to activate:"
    echo "   ssh nixos@$HOSTNAME sudo reboot"
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
    nix run --add-root ./result-nixos-anywhere --indirect github:nix-community/nixos-anywhere -- \
      --flake .#naspi \
      --build-on-remote \
      "noams@$HOSTNAME"
  fi
  ;;
"switch")
  echo "🔄 Updating existing NixOS system..."
  echo "ℹ️  This assumes the system was already installed with disko partitioning"

  echo "🔄 Switching configuration via SSH using nixos-rebuild with nom..."
  nixos-rebuild boot \
    --flake ".#naspi" \
    --target-host "noams@$HOSTNAME" \
    --build-host "noams@$HOSTNAME" \
    --use-remote-sudo |& nom

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
  echo "   ./scripts/naspi-deploy.sh rpi4-installer.local install"
  exit 1
  ;;
esac

echo "✅ Deployment completed successfully!"
echo "🔗 SSH access: ssh noams@$HOSTNAME"
