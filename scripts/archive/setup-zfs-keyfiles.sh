#!/usr/bin/env bash

# ZFS Key File Setup Script for NasPI
# This script helps set up key files for automatic ZFS encryption unlock

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ZFS_POOL="rpool"
KEY_DIR="/boot/zfs-keys"
KEY_FILE="$KEY_DIR/$ZFS_POOL"

print_header() {
  echo -e "${BLUE}=== ZFS Key File Setup for NasPI ===${NC}"
  echo
}

print_step() {
  echo -e "${GREEN}[STEP]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
  fi
}

check_zfs_pool() {
  if ! zpool status "$ZFS_POOL" &>/dev/null; then
    print_error "ZFS pool '$ZFS_POOL' not found"
    echo "Available pools:"
    zpool list
    exit 1
  fi
}

create_key_directory() {
  print_step "Creating key directory: $KEY_DIR"
  mkdir -p "$KEY_DIR"
  chmod 700 "$KEY_DIR"
  chown root:root "$KEY_DIR"
}

generate_key_file() {
  print_step "Generating random key file: $KEY_FILE"

  if [[ -f $KEY_FILE ]]; then
    print_warning "Key file already exists: $KEY_FILE"
    read -p "Overwrite existing key file? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      print_error "Aborted by user"
      exit 1
    fi
  fi

  # Generate 32-byte (256-bit) random key
  dd if=/dev/urandom of="$KEY_FILE" bs=32 count=1 2>/dev/null
  chmod 600 "$KEY_FILE"
  chown root:root "$KEY_FILE"

  print_step "Key file generated successfully"
}

configure_zfs_encryption() {
  print_step "Configuring ZFS pool to use key file"

  print_warning "This will prompt for the current encryption passphrase"
  echo "You will need to enter your current ZFS encryption password"
  echo

  # Change key to use the file
  if zfs change-key -o keyformat=raw -o keylocation="file://$KEY_FILE" "$ZFS_POOL"; then
    print_step "ZFS pool configured to use key file"
  else
    print_error "Failed to configure ZFS pool"
    exit 1
  fi
}

test_key_file() {
  print_step "Testing key file functionality"

  # Unload the key
  print_step "Unloading ZFS key..."
  zfs unload-key "$ZFS_POOL" || true

  # Try to load it back using the key file
  print_step "Loading ZFS key from file..."
  if zfs load-key "$ZFS_POOL"; then
    print_step "Key file test successful!"
  else
    print_error "Key file test failed"
    exit 1
  fi
}

backup_key_file() {
  print_step "Creating backup of key file"

  BACKUP_DIR="/root/zfs-key-backup"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"

  cp "$KEY_FILE" "$BACKUP_DIR/$(basename $KEY_FILE).backup.$(date +%Y%m%d-%H%M%S)"

  print_warning "IMPORTANT: Key file backed up to $BACKUP_DIR"
  print_warning "Store this backup in a secure location!"
  print_warning "Without this key, your encrypted data will be inaccessible!"
}

show_security_notes() {
  echo
  echo -e "${YELLOW}=== SECURITY NOTES ===${NC}"
  echo "1. The key file is stored on the unencrypted boot partition"
  echo "2. Anyone with physical access to the SD card can access the key"
  echo "3. This trades security for convenience - suitable for home NAS use"
  echo "4. Keep a secure backup of the key file in case of SD card failure"
  echo "5. The boot partition should be on a separate, removable storage if maximum security is needed"
  echo
}

main() {
  print_header

  check_root
  check_zfs_pool

  show_security_notes

  read -p "Continue with key file setup? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Aborted by user"
    exit 1
  fi

  create_key_directory
  generate_key_file
  configure_zfs_encryption
  test_key_file
  backup_key_file

  echo
  print_step "ZFS key file setup completed successfully!"
  echo
  print_step "Next steps:"
  echo "1. Rebuild your NixOS configuration: sudo nixos-rebuild switch --flake .#naspi"
  echo "2. Reboot to test automatic unlock: sudo reboot"
  echo "3. Verify that ZFS pools mount automatically after reboot"
  echo
}

# Handle Ctrl+C gracefully
trap 'echo; print_error "Script interrupted"; exit 1' INT

main "$@"
