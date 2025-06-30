#!/usr/bin/env bash
set -euo pipefail

# Build SD card image for Raspberry Pi
# Usage: ./scripts/naspi-build-image.sh

echo "🏗️  Building Raspberry Pi SD card image..."

# Build the SD image
echo "📦 Building SD image..."
nom build ".#sdImages.naspi" --out-link result-naspi-image

# Get the actual image path
IMAGE_PATH=$(readlink -f result-naspi-image)
IMAGE_FILE="$IMAGE_PATH/sd-image/nixos-sd-image-*-aarch64-linux.img"

echo "✅ Image built successfully!"
echo "📁 Image location: $IMAGE_FILE"
echo ""
echo "💾 To flash to SD card:"
echo "   sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress"
echo "   (Replace /dev/sdX with your SD card device)"
echo ""
echo "🔧 Or use a GUI tool like Raspberry Pi Imager"