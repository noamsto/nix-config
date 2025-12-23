#!/usr/bin/env bash
# Build Raspberry Pi installer SD card image
# Usage: build-image.sh <host-config>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../lib/rpi-common.sh"

# =============================================================================
# Parse Arguments
# =============================================================================

if [[ $# -lt 1 ]]; then
  print_error "Usage: $0 <host-config>"
  print_info "Example: $0 rpi4-installer"
  print_info "Example: $0 rpi4-standard"
  exit 1
fi

HOST_CONFIG=$1

# =============================================================================
# Validate Configuration
# =============================================================================

print_step "Validating host configuration..."
validate_host_exists "$HOST_CONFIG"

# =============================================================================
# Resolve Metadata
# =============================================================================

print_step "Loading host metadata..."
FLAKE=$(get_flake "$HOST_CONFIG")
DESCRIPTION=$(get_host_config "$HOST_CONFIG" | jq -r '.description // "Raspberry Pi image"')

print_info "Building: $HOST_CONFIG"
print_info "Description: $DESCRIPTION"
echo ""

# =============================================================================
# Build Image
# =============================================================================

print_step "Building SD card image..."
echo ""

RESULT_LINK="result-${HOST_CONFIG}"

# Build the image
if command -v nom >/dev/null 2>&1; then
  nom build ".#$FLAKE" --out-link "$RESULT_LINK"
else
  print_warn "nom not found, using standard nix build"
  nix build ".#$FLAKE" --out-link "$RESULT_LINK"
fi

# =============================================================================
# Find Image File
# =============================================================================

print_step "Locating image file..."

IMAGE_FILE=$(find_image "$RESULT_LINK")

if [[ -z $IMAGE_FILE ]]; then
  print_error "Failed to locate image file"
  exit 1
fi

print_success "Image file found: $IMAGE_FILE"

# =============================================================================
# Show Usage Information
# =============================================================================

echo ""
print_success "Build complete!"
echo ""
print_info "Image location: $IMAGE_FILE"
print_info "Result link: $RESULT_LINK"
echo ""

# Check if compressed
if [[ $IMAGE_FILE == *.zst ]]; then
  print_info "Image is compressed (zstd)"
  echo ""
  print_info "Flash to SD card (decompressed):"
  echo "  zstd -d \"$IMAGE_FILE\" -o /tmp/installer.img"
  echo "  sudo dd if=/tmp/installer.img of=/dev/sdX bs=4M status=progress"
  echo ""
  print_info "Or flash compressed directly:"
  echo "  zstd -dc \"$IMAGE_FILE\" | sudo dd of=/dev/sdX bs=4M status=progress"
else
  print_info "Flash to SD card:"
  echo "  sudo dd if=\"$IMAGE_FILE\" of=/dev/sdX bs=4M status=progress"
fi

echo ""
print_warn "Replace /dev/sdX with your SD card device (check with 'lsblk')"
echo ""

# Show next steps based on host type
if [[ "$(is_installer "$HOST_CONFIG")" == "true" ]]; then
  print_info "Next steps:"
  print_info "  1. Flash image to SD card"
  print_info "  2. Boot Raspberry Pi from SD card"
  print_info "  3. Deploy full configuration:"
  echo "     ./scripts/rpi/rpi <target-host> install"
  echo ""
  print_info "Or use justfile shortcuts:"
  echo "     just install-naspi"
  echo "     just install-argon"
else
  print_info "Next steps:"
  print_info "  1. Flash image to SD card"
  print_info "  2. Boot Raspberry Pi from SD card"
  print_info "  3. System should be ready to use"
fi

echo ""
print_info "You can also use Raspberry Pi Imager to flash the image"
