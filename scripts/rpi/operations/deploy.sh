#!/usr/bin/env bash
# Deploy configuration updates to existing Raspberry Pi system
# Usage: deploy.sh <host-config> [build-strategy]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/rpi-common.sh
source "$SCRIPT_DIR/../../../lib/rpi-common.sh"

# =============================================================================
# Parse Arguments
# =============================================================================

if [[ $# -lt 1 ]]; then
  print_error "Usage: $0 <host-config> [build-strategy]"
  print_info "Example: $0 naspi auto"
  print_info "Example: $0 naspi local"
  print_info "Example: $0 naspi remote"
  exit 1
fi

HOST_CONFIG=$1
STRATEGY=${2:-auto}

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
USER=$(get_user "$HOST_CONFIG")
FLAKE=$(get_flake "$HOST_CONFIG")
BUILD=$(resolve_build_strategy "$HOST_CONFIG" "$STRATEGY")

print_info "Target: $HOST_CONFIG ($USER@$HOSTNAME)"
print_info "Flake: $FLAKE"

# =============================================================================
# Validate Connectivity
# =============================================================================

validate_ssh "$USER" "$HOSTNAME"

# =============================================================================
# Deploy Configuration
# =============================================================================

print_step "Deploying configuration..."

if [[ $BUILD == "local" ]]; then
  print_info "Build strategy: Local (using your binary cache)"
  echo ""

  nixos-rebuild switch \
    --flake ".#$FLAKE" \
    --target-host "$USER@$HOSTNAME" \
    --use-remote-sudo

elif [[ $BUILD == remote:* ]]; then
  BUILD_HOST="${BUILD#remote:}"
  print_info "Build strategy: Remote ($BUILD_HOST)"
  echo ""

  nixos-rebuild switch \
    --flake ".#$FLAKE" \
    --target-host "$USER@$HOSTNAME" \
    --build-host "$BUILD_HOST" \
    --use-remote-sudo |& nom

else
  # Custom build host
  print_info "Build strategy: Custom ($BUILD)"
  echo ""

  nixos-rebuild switch \
    --flake ".#$FLAKE" \
    --target-host "$USER@$HOSTNAME" \
    --build-host "$BUILD" \
    --use-remote-sudo |& nom
fi

# =============================================================================
# Success
# =============================================================================

echo ""
print_success "Deployment complete!"
print_info "Configuration activated on $HOSTNAME"
print_info "No reboot required (changes are live)"
