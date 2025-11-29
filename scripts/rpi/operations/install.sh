#!/usr/bin/env bash
# Fresh installation of NixOS on Raspberry Pi using nixos-anywhere + disko
# Usage: install.sh <host-config>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/rpi-common.sh
source "$SCRIPT_DIR/../../../lib/rpi-common.sh"

# =============================================================================
# Parse Arguments
# =============================================================================

if [[ $# -lt 1 ]]; then
  print_error "Usage: $0 <host-config>"
  print_info "Example: $0 naspi"
  print_info "Example: $0 argon-rpi4"
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
HOSTNAME=$(get_hostname "$HOST_CONFIG")
FLAKE=$(get_flake "$HOST_CONFIG")
FILESYSTEM=$(get_filesystem "$HOST_CONFIG")

# Determine target user (installer or regular user)
if [[ $HOSTNAME == *"installer"* ]] || [[ "$(is_installer "$HOST_CONFIG")" == "true" ]]; then
  TARGET_USER=$(get_installer_user "$HOST_CONFIG")
  print_info "Installer-based deployment detected"
else
  TARGET_USER=$(get_user "$HOST_CONFIG")
fi

print_warn "FRESH INSTALLATION MODE"
print_warn "This will WIPE and REPARTITION the target system!"
echo ""
print_info "Target: $HOST_CONFIG ($TARGET_USER@$HOSTNAME)"
print_info "Flake: $FLAKE"
print_info "Filesystem: $FILESYSTEM"
echo ""

# =============================================================================
# Filesystem-Specific Information
# =============================================================================

if [[ $FILESYSTEM == "zfs" ]]; then
  print_info "ZFS configuration will create:"
  print_info "  • RAID1 mirror across dual disks"
  print_info "  • Encrypted datasets with automatic unlock"
  print_info "  • Optimized for NAS workloads"
  echo ""
elif [[ $FILESYSTEM == "btrfs" ]]; then
  print_info "Btrfs configuration will create:"
  print_info "  • Subvolumes for root, home, nix, var"
  print_info "  • Snapshots support"
  print_info "  • Optimized for SSD"
  echo ""
fi

# =============================================================================
# Confirmation
# =============================================================================

confirm_destructive "install" "$HOSTNAME"

# =============================================================================
# ZFS Encryption Key Generation (if needed)
# =============================================================================

ENCRYPTION_KEY_FLAG=""

if [[ $FILESYSTEM == "zfs" ]]; then
  print_step "Generating ZFS encryption key..."

  # Check if generate-zfs-key.sh exists
  if [[ ! -f "$SCRIPT_DIR/../../../scripts/generate-zfs-key.sh" ]]; then
    print_error "ZFS key generation script not found"
    print_info "Expected: scripts/generate-zfs-key.sh"
    exit 1
  fi

  "$SCRIPT_DIR/../../../scripts/generate-zfs-key.sh"

  # Set encryption key flag for nixos-anywhere
  ENCRYPTION_KEY_FLAG="--disk-encryption-keys /tmp/zfs-rpool-key /tmp/zfs-rpool-key"
  print_success "ZFS encryption key generated"
fi

# =============================================================================
# Validate Connectivity
# =============================================================================

validate_ssh "$TARGET_USER" "$HOSTNAME"

# =============================================================================
# Build and Install
# =============================================================================

print_step "Building and installing NixOS..."
echo ""

# Construct nixos-anywhere command
NIXOS_ANYWHERE_CMD=(
  nix run github:nix-community/nixos-anywhere --
  --flake ".#$FLAKE"
)

# Add encryption key if present
if [[ -n $ENCRYPTION_KEY_FLAG ]]; then
  # shellcheck disable=SC2206  # Intentional word splitting for multiple args
  NIXOS_ANYWHERE_CMD+=($ENCRYPTION_KEY_FLAG)
fi

# Add target
NIXOS_ANYWHERE_CMD+=("$TARGET_USER@$HOSTNAME")

# Execute
"${NIXOS_ANYWHERE_CMD[@]}"

# =============================================================================
# Cleanup
# =============================================================================

if [[ $FILESYSTEM == "zfs" ]]; then
  print_step "Cleaning up local key file..."
  rm -f /tmp/zfs-rpool-key
  print_success "ZFS encryption configured with automatic unlock"
fi

# =============================================================================
# Success
# =============================================================================

echo ""
print_success "Installation complete!"
echo ""
print_info "Next steps:"

if [[ $HOSTNAME == *"installer"* ]]; then
  print_info "  1. Remove SD card from Raspberry Pi"
  print_info "  2. Reboot to boot from installed system"
  print_info "  3. SSH to new system: ssh $(get_user "$HOST_CONFIG")@$HOSTNAME"
else
  print_info "  1. System should reboot automatically"
  print_info "  2. SSH to system: ssh $TARGET_USER@$HOSTNAME"
fi

echo ""
print_info "For post-installation setup, see hosts/$HOST_CONFIG/README.md"
