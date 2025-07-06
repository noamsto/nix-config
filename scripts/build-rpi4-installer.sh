#!/usr/bin/env bash
set -euo pipefail

# Build RPI4 installer SD card image using nvmd pattern
# Usage: ./scripts/build-rpi4-installer.sh

echo "🏗️  Building RPI4 installer SD card image..."
echo "ℹ️  This creates a minimal installer image that can be used to deploy your full configuration."

# Build the installer SD image
echo "📦 Building installer SD image..."
nom build ".#rpi4-installer" --out-link result-rpi4-installer

# Get the actual image path
IMAGE_PATH=$(readlink -f result-rpi4-installer)

# Find the actual image file (can be .img, .img.zst, or .raw)
if [[ -f "$IMAGE_PATH/sd-image/nixos-sd-image.*.img" ]]; then
  IMAGE_FILE=$(find "$IMAGE_PATH" -name "*.img" | head -1)
elif [[ -f "$IMAGE_PATH" ]] && [[ "$IMAGE_PATH" == *.img* ]]; then
  IMAGE_FILE="$IMAGE_PATH"
else
  echo "🔍 Looking for image file in: $IMAGE_PATH"
  IMAGE_FILE=$(find "$IMAGE_PATH" -name "*.img*" -o -name "*.raw" | head -1)
  
  if [[ -z "$IMAGE_FILE" ]]; then
    find "$IMAGE_PATH" -name "*.img*" -o -name "*.raw" | head -5
    echo ""
    echo "❌ Could not find image file. Check the build output above."
    exit 1
  fi
fi

echo "✅ Installer image built successfully!"
echo "📁 Image location: $IMAGE_FILE"
echo ""
echo "🎯 This installer image includes:"
echo "   • Minimal NixOS installer for Raspberry Pi 4"
echo "   • SSH access with your pre-configured SSH key"
echo "   • Network connectivity for remote deployment"
echo "   • All tools needed for nixos-anywhere deployment"
echo ""
echo "📋 Usage instructions:"
echo "1. Flash to SD card:"
if [[ "$IMAGE_FILE" == *.zst ]]; then
  echo "   # Decompress and flash:"
  echo "   zstd -d \"$IMAGE_FILE\" -o /tmp/installer.img"
  echo "   sudo dd if=/tmp/installer.img of=/dev/sdX bs=4M status=progress"
  echo "   # Or flash compressed directly:"
  echo "   zstd -dc \"$IMAGE_FILE\" | sudo dd of=/dev/sdX bs=4M status=progress"
else
  echo "   sudo dd if=\"$IMAGE_FILE\" of=/dev/sdX bs=4M status=progress"
fi
echo "   (Replace /dev/sdX with your SD card device)"
echo ""
echo "2. Boot the RPi4 with this SD card"
echo ""
echo "3. Deploy your full configuration:"
echo "   ./scripts/naspi-deploy.sh rpi4-installer.local install"
echo ""
echo "🔧 Or use a GUI tool like Raspberry Pi Imager to flash the image"
