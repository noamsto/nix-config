#!/usr/bin/env bash
# Setup script for NAS Pi with ZFS and dual SSDs
# This script helps identify disk IDs and prepare the disko configuration

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
NASPI_DIR="$CONFIG_DIR/hosts/naspi"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

print_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to detect SSDs
detect_ssds() {
  print_info "Detecting available SSDs..."
  echo ""

  print_info "Available block devices:"
  lsblk -d -o NAME,SIZE,TYPE,MODEL,TRAN | grep -E "(ssd|ata|usb)"
  echo ""

  print_info "Disk IDs (recommended for stable identification):"
  # Use find instead of ls | grep for better handling of filenames
  find /dev/disk/by-id/ -maxdepth 1 -name "*ata-*" -o -name "*usb-*" | grep -v part | head -10 | xargs -r ls -la 2>/dev/null || true
  echo ""
}

# Function to generate hostId
generate_hostid() {
  if [[ -f /etc/machine-id ]]; then
    HOSTID=$(head -c 8 /etc/machine-id)
    print_info "Generated hostId from machine-id: $HOSTID"
  else
    HOSTID=$(openssl rand -hex 4)
    print_info "Generated random hostId: $HOSTID"
  fi
  echo "$HOSTID"
}

# Function to update disko configuration with disk IDs
update_disko_config() {
  local ssd1_id="$1"
  local ssd2_id="$2"
  local hostid="$3"

  print_info "Updating disko-zfs.nix with disk IDs..."

  # Create a temporary file with the updated configuration
  local temp_config
  temp_config=$(mktemp)

  sed -e "s|ata-YOUR_SSD1_ID|$ssd1_id|g" \
    -e "s|ata-YOUR_SSD2_ID|$ssd2_id|g" \
    -e "s|8425e349|$hostid|g" \
    "$NASPI_DIR/disko-zfs.nix" >"$temp_config"

  # Backup original and replace
  cp "$NASPI_DIR/disko-zfs.nix" "$NASPI_DIR/disko-zfs.nix.bak"
  mv "$temp_config" "$NASPI_DIR/disko-zfs.nix"

  print_success "Updated $NASPI_DIR/disko-zfs.nix"
  print_info "Backup saved as disko-zfs.nix.bak"
}

# Function to update ZFS system configuration with hostId
update_zfs_system_config() {
  local hostid="$1"

  print_info "Updating zfs-system.nix with hostId..."

  # Update the hostId in the ZFS system configuration
  sed -i.bak "s/8425e349/$hostid/g" "$NASPI_DIR/zfs-system.nix"

  print_success "Updated $NASPI_DIR/zfs-system.nix"
  print_info "Backup saved as zfs-system.nix.bak"
}

# Function to create the nixos configuration update
update_nixos_config() {
  print_info "Updating NixOS configuration to use ZFS..."

  # Update the flake to use the new ZFS configuration
  local flake_config="$CONFIG_DIR/flake-modules/nixos-systems.nix"

  # Check if we need to add ZFS configuration reference
  if grep -q "disko-zfs.nix" "$flake_config"; then
    print_info "ZFS disko configuration already referenced in nixos-systems.nix"
  else
    print_warn "You may need to manually update $flake_config to use disko-zfs.nix"
    print_warn "Change the import from './disko.nix' to './disko-zfs.nix'"
    print_warn "And update the default.nix import to default-zfs.nix"
  fi
}

# Function to show next steps
show_next_steps() {
  echo ""
  print_success "Configuration updated! Next steps:"
  echo ""
  echo "1. Review the generated configuration files:"
  echo "   - $NASPI_DIR/disko-zfs.nix"
  echo "   - $NASPI_DIR/zfs-system.nix"
  echo "   - $NASPI_DIR/default-zfs.nix"
  echo ""
  echo "2. Update your flake configuration:"
  echo "   - Edit flake-modules/nixos-systems.nix"
  echo "   - Change the disko import from './disko.nix' to './disko-zfs.nix'"
  echo "   - Change the host import from '../hosts/naspi' to '../hosts/naspi/default-zfs.nix'"
  echo ""
  echo "3. Test the configuration:"
  echo "   cd $CONFIG_DIR"
  echo "   nix flake check"
  echo "   nom build .#nixosConfigurations.naspi.config.system.build.toplevel"
  echo ""
  echo "4. Deploy to your Raspberry Pi:"
  echo "   ./scripts/naspi-deploy.sh naspi.local install"
  echo ""
  print_warn "WARNING: This will completely repartition your drives!"
  print_warn "Ensure you have backups of any important data."
}

# Main function
main() {
  print_info "NAS Pi ZFS Setup Script"
  print_info "======================="
  echo ""

  # Detect SSDs
  detect_ssds

  # Get disk IDs from user
  echo ""
  print_info "Please identify your two SSDs from the list above."
  echo -n "Enter the first SSD ID (e.g., ata-Samsung_SSD_980_PRO_2TB_...): "
  read -r SSD1_ID

  echo -n "Enter the second SSD ID (e.g., ata-Samsung_SSD_980_PRO_2TB_...): "
  read -r SSD2_ID

  # Validate inputs
  if [[ ! -e "/dev/disk/by-id/$SSD1_ID" ]]; then
    print_error "First SSD ID not found: /dev/disk/by-id/$SSD1_ID"
    exit 1
  fi

  if [[ ! -e "/dev/disk/by-id/$SSD2_ID" ]]; then
    print_error "Second SSD ID not found: /dev/disk/by-id/$SSD2_ID"
    exit 1
  fi

  # Generate hostId
  HOSTID=$(generate_hostid)

  # Update configurations
  update_disko_config "$SSD1_ID" "$SSD2_ID" "$HOSTID"
  update_zfs_system_config "$HOSTID"
  update_nixos_config

  # Show next steps
  show_next_steps
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
  print_warn "This script should be run as a regular user, not root"
  print_warn "Some operations may require sudo, which will be prompted"
fi

# Run main function
main "$@"
